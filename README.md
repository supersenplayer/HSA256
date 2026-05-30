# HSA256 — SHA-256 Hardware Accelerator (Co-processor)

A synthesizable VHDL implementation of the SHA-256 hash function, structured as a
memory-mapped co-processor. The host writes a message into a shared memory, pulses
`start`, and the core computes the 256-bit digest and writes it back to memory.

## Architecture

| File | Module | Role |
|------|--------|------|
| `SHA256_pkg.vhd`    | `sha256_pkg`    | Types, the `K` round constants, `H_init`, and the logical functions (`Ch`, `Maj`, `ROTR`, `SHR`, `σ0/σ1`, `Σ0/Σ1`, `add`). |
| `Round.vhd`         | `Round`         | Combinational compression round (computes `T1`/`T2` and the next `a..h`). |
| `Scheduler.vhd`     | `Scheduler`     | 16-word sliding-window message schedule generating `W[t]`. |
| `SHA256_FSM.vhd`    | `SHA256_FSM`    | Control FSM, memory address pipeline, scheduler input mux, `K` selection, writeback. |
| `SHA256_Core.vhd`   | `SHA256_Core`   | Top of the datapath: wires Scheduler + Round + FSM, holds working registers `a..h` and the `H` accumulator. |
| `SHA256_Memory.vhd` | `SHA256_Memory` | Simple synchronous RAM (1-cycle read latency) used as the shared buffer. |
| `SHA256_tb.vhd`     | `SHA256_tb`     | Self-checking testbench (see below). |

### Data flow

```
        start                         done
          |                            ^
          v                            |
   +----------------+   ctrl   +----------------+
   |   SHA256_FSM   |--------->|   Scheduler    |--W[t]--+
   |  (control)     |          +----------------+        |
   |                |                                    v
   |  addr / wen    |          +----------------+   +---------+
   +----------------+          |     Round      |<--| a..h    |
        ^   |                  +----------------+   | regs +  |
   rd   |   | wr                      |             | H accum |
        |   v                         +------------>+---------+
   +----------------+
   | SHA256_Memory  |
   +----------------+
```

## Memory map

The core uses a byte-addressed view of the RAM (word index = byte address / 4):

| Byte address | Contents |
|--------------|----------|
| `0x0000`            | Message length **in bits** (also used to derive the number of data words). |
| `0x0004`, `0x0008`… | Message data words `W[0]`, `W[1]`, … (big-endian within each 32-bit word). |
| `0x2000`–`0x201C`   | Result digest `H0..H7` written back by the core (8 words). |

### Protocol

1. Host loads the length word and the message data words into memory.
2. Host pulses `start` high for one cycle while the core is in `IDLE` (`done = '1'`).
3. The core walks `IDLE → FETCH → LOAD → COMPUTE → ACCUM → WRITEBACK → IDLE`,
   performs the 64 rounds, and writes the digest to `0x2000`.
4. `done` returns high when the core is back in `IDLE`.

## Current limitations

These are design simplifications, not bugs — worth knowing before reuse:

- **Single 512-bit block only.** No multi-block message loop yet.
- **Word-granular padding.** The padding `0x80…` byte is appended as a whole
  32-bit word, so the message bit-length must be a multiple of 32. (Messages such
  as the 24-bit string `"abc"` are not directly supported; pad to a word boundary
  in software first, or extend the padding logic.)
- **Length field uses the low 9 bits**, so the message must be `< 512` bits.

## Simulation

A self-checking testbench (`SHA256_tb.vhd`) instantiates the core together with the
memory, preloads several messages, and compares the captured digest against the
known-good SHA-256 values (verified with Python `hashlib`):

- empty string
- `"abcd"`   (32-bit)
- `"abcdefgh"` (64-bit)
- `"OpenAI-GPT!!"` (96-bit)

It was validated with [GHDL](https://github.com/ghdl/ghdl):

```sh
ghdl -a --std=08 SHA256_pkg.vhd Round.vhd Scheduler.vhd \
                 SHA256_Memory.vhd SHA256_FSM.vhd SHA256_Core.vhd SHA256_tb.vhd
ghdl -e --std=08 SHA256_tb
ghdl -r --std=08 SHA256_tb --stop-time=200us
```

A passing run ends with `ALL TESTS PASSED`.

## Notes on the verification / fixes

Bringing the design up under simulation surfaced two timing bugs in `SHA256_FSM.vhd`,
both now fixed:

1. **Message-word fetch off-by-one.** The read-address register was advanced one
   cycle too late, so `LOAD counter=0` returned `mem[0]` (the length word) instead of
   `mem[1]` (`W[0]`), shifting every data word by one slot. Fixed by driving the
   `W[0]` address (`0x0004`) during `FETCH` and offsetting the `LOAD` address
   arithmetic by one word.
2. **Stale first digest word.** The writeback began on the same cycle the final
   `H = H_init + working vars` accumulation was still settling, so `H0` was written
   with the stale initial value. Fixed by adding a one-cycle `ACCUM` state between
   `COMPUTE` and `WRITEBACK`.

With both fixes, all four test vectors match the reference digests.
