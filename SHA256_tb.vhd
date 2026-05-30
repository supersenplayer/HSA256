----------------------------------------------------------------------------------
-- Self-checking testbench for the SHA256 co-processor.
--
-- Instantiates SHA256_Core + SHA256_Memory, preloads a message into memory,
-- pulses start, waits for completion, then snoops the writeback bus to capture
-- the 8 result words (H0..H7) and compares them against known-good digests.
--
-- NOTE on padding: the FSM appends padding at 32-bit word granularity, so the
-- test messages all have a bit-length that is a multiple of 32. For those
-- messages the hardware padding matches standard SHA-256, so the expected
-- digests below are the real SHA-256 digests (verified with Python hashlib).
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sha256_pkg.all;

entity SHA256_tb is
end entity;

architecture sim of SHA256_tb is

    -- Helper: convert a 32-bit word to an 8-character hex string.
    -- Works with VHDL-93/2002 (no to_hstring dependency).
    function word_to_hex(v : std_logic_vector(31 downto 0)) return string is
        constant HEX_CHARS : string(1 to 16) := "0123456789ABCDEF";
        variable result    : string(1 to 8);
        variable nibble    : integer;
    begin
        for i in 0 to 7 loop
            nibble := to_integer(unsigned(v(31 - i*4 downto 28 - i*4)));
            result(i + 1) := HEX_CHARS(nibble + 1);
        end loop;
        return result;
    end function;

    constant T : time := 10 ns;

    signal clk   : std_logic := '0';
    signal rst   : std_logic := '1';
    signal start : std_logic := '0';
    signal done  : std_logic;

    -- Core <-> Memory wiring
    signal core_raddr : std_logic_vector(15 downto 0);
    signal mem_rdata  : word;
    signal core_wen   : std_logic;
    signal core_waddr : std_logic_vector(15 downto 0);
    signal core_wdata : word;

    -- memory write port (muxed between TB preload and Core writeback)
    signal mem_wen   : std_logic;
    signal mem_waddr : std_logic_vector(15 downto 0);
    signal mem_wdata : word;

    -- TB preload controls
    signal tb_load  : std_logic := '1';
    signal tb_wen   : std_logic := '0';
    signal tb_waddr : std_logic_vector(15 downto 0) := (others => '0');
    signal tb_wdata : word := (others => '0');

    signal sim_done : boolean := false;
    signal fail_cnt : integer := 0;

    -- message vector type: up to 14 data words
    type wvec is array (natural range <>) of word;

    -- expected digests (real SHA-256, verified with Python)
    constant EXP_EMPTY : word_8 := (
        x"e3b0c442", x"98fc1c14", x"9afbf4c8", x"996fb924",
        x"27ae41e4", x"649b934c", x"a495991b", x"7852b855");
    constant EXP_ABCD : word_8 := (   -- "abcd"
        x"88d4266f", x"d4e6338d", x"13b845fc", x"f289579d",
        x"209c8978", x"23b9217d", x"a3e16193", x"6f031589");
    constant EXP_ABCDEFGH : word_8 := (   -- "abcdefgh"
        x"9c56cc51", x"b374c3ba", x"189210d5", x"b6d4bf57",
        x"790d351c", x"96c47c02", x"190ecf1e", x"430635ab");
    constant EXP_12B : word_8 := (   -- "OpenAI-GPT!!"
        x"f0b43cf9", x"bb2e9372", x"607ad44d", x"cf6d2176",
        x"1fcf27a9", x"c0228efb", x"9c04fabd", x"215991f4");

begin

    -- ---------------- clock ----------------
    clk <= '0' when sim_done else not clk after T/2;

    -- ---------------- DUTs ----------------
    dut_core : entity work.SHA256_Core
        port map (
            clk => clk, rst => rst, start => start, done => done,
            mem_addr => core_raddr, mem_data => mem_rdata,
            mem_wen => core_wen, mem_waddr => core_waddr, mem_wdata => core_wdata);

    -- memory write port mux: TB drives during preload, Core drives otherwise
    mem_wen   <= tb_wen   when tb_load = '1' else core_wen;
    mem_waddr <= tb_waddr when tb_load = '1' else core_waddr;
    mem_wdata <= tb_wdata when tb_load = '1' else core_wdata;

    dut_mem : entity work.SHA256_Memory
        port map (
            clk => clk,
            rd_addr => core_raddr, rd_data => mem_rdata,
            wr_en => mem_wen, wr_addr => mem_waddr, wr_data => mem_wdata);

    -- ---------------- stimulus ----------------
    stim : process

        -- write one word into memory at byte address (synchronous)
        procedure mem_write(addr : in integer; data : in word) is
        begin
            tb_wen   <= '1';
            tb_waddr <= std_logic_vector(to_unsigned(addr, 16));
            tb_wdata <= data;
            wait until rising_edge(clk);
        end procedure;

        -- run one hash: preload msg, start, wait, capture digest, compare
        procedure run_test(name     : in string;
                            data     : in wvec;
                            len_bits : in integer;
                            expected : in word_8) is
            variable captured : word_8 := (others => (others => '0'));
            variable idx      : integer;
        begin
            -- reset the core and enter preload mode
            rst     <= '1';
            start   <= '0';
            tb_load <= '1';
            tb_wen  <= '0';
            wait until rising_edge(clk);
            wait until rising_edge(clk);

            -- preload length word at 0x0000
            mem_write(16#0000#, std_logic_vector(to_unsigned(len_bits, 32)));
            -- preload data words starting at 0x0004
            for i in data'range loop
                mem_write(16#0004# + i * 4, data(i));
            end loop;
            tb_wen  <= '0';
            tb_load <= '0';

            -- release reset, let FSM settle in IDLE
            rst <= '0';
            wait until rising_edge(clk);
            wait until rising_edge(clk);

            -- pulse start for one cycle
            start <= '1';
            wait until rising_edge(clk);
            start <= '0';

            -- capture the 8 writeback words (core_wen pulses 8x in WRITEBACK)
            idx := 0;
            while idx < 8 loop
                wait until rising_edge(clk);
                if core_wen = '1' then
                    captured(idx) := core_wdata;
                    idx := idx + 1;
                end if;
            end loop;

            -- compare
            report "=== Test: " & name & " ===";
            for i in 0 to 7 loop
                if captured(i) /= expected(i) then
                    fail_cnt <= fail_cnt + 1;
                    report "  H" & integer'image(i) &
                           " MISMATCH  got=" & word_to_hex(captured(i)) &
                           "  exp=" & word_to_hex(expected(i))
                           severity error;
                else
                    report "  H" & integer'image(i) & " ok  " &
                           word_to_hex(captured(i));
                end if;
            end loop;

            -- a few idle cycles before next test
            wait until rising_edge(clk);
            wait until rising_edge(clk);
        end procedure;

        variable empty_data : wvec(0 to -1);  -- zero-length
    begin
        -- empty message
        run_test("empty string", empty_data, 0, EXP_EMPTY);
        -- "abcd" (1 word, 32 bits)
        run_test("abcd", wvec'(0 => x"61626364"), 32, EXP_ABCD);
        -- "abcdefgh" (2 words, 64 bits)
        run_test("abcdefgh", wvec'(x"61626364", x"65666768"), 64, EXP_ABCDEFGH);
        -- "OpenAI-GPT!!" (3 words, 96 bits)
        run_test("OpenAI-GPT!!", wvec'(x"4f70656e", x"41492d47", x"50542121"), 96, EXP_12B);

        report "================================";
        if fail_cnt = 0 then
            report "ALL TESTS PASSED";
        else
            report integer'image(fail_cnt) & " WORD MISMATCH(ES) -- SEE ABOVE" severity error;
        end if;
        report "================================";

        sim_done <= true;
        wait;
    end process;

end architecture sim;
