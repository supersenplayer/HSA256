library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sha256_pkg.all;

entity SHA256_FSM is port (
    clk          : in  std_logic;
    rst          : in  std_logic;
    start        : in  std_logic;
    done         : out std_logic;

    mem_addr     : out std_logic_vector(15 downto 0);
    mem_data     : in  word;
    mem_wen      : out std_logic;
    mem_waddr    : out std_logic_vector(15 downto 0);
    mem_wdata    : out word;

    w_src        : out std_logic;
    shift_e      : out std_logic;
    sched_input  : out word;
    wt           : in  word;

    kt           : out word;
    round_en     : out std_logic;
    hash_init    : out std_logic;   -- pulses in FETCH : resets a..h to H_init
    compute_done : out std_logic;   -- pulses 1 cycle when round 63 finishes

    H_result     : in  word_8
);
end entity;

architecture rtl of SHA256_FSM is

    type state_t is (IDLE, FETCH, LOAD, COMPUTE, ACCUM, WRITEBACK);
    signal state : state_t := IDLE;

    -- counter  : drives scheduler slot index and memory address
    -- counter goes 0..15 in LOAD, 16..64 in COMPUTE; round 63 fires at 64,
    -- then one ACCUM cycle finalises H_result before WRITEBACK.
    signal counter      : integer range 0 to 64 := 0;
    -- counter_prev : 1-cycle delayed counter, used for kt
    -- because scheduler output W[N] becomes valid 1 cycle AFTER loading
    signal counter_prev : integer range 0 to 64 := 0;

    signal wb_cnt        : integer range 0 to 7 := 0;
    signal addr_reg      : std_logic_vector(15 downto 0) := x"0000";
    signal msg_len_bits  : word := (others => '0');
    signal msg_len_words : integer range 0 to 14 := 0;
    signal cdone_i       : std_logic := '0';

begin

    -- ----------------------------------------------------------------
    -- Sequential logic
    -- ----------------------------------------------------------------
    process(clk)
    begin
        if rst = '1' then
            state         <= IDLE;
            counter       <= 0;
            counter_prev  <= 0;
            wb_cnt        <= 0;
            addr_reg      <= x"0000";
            msg_len_bits  <= (others => '0');
            msg_len_words <= 0;
            cdone_i       <= '0';

        elsif rising_edge(clk) then
            cdone_i      <= '0';          -- default: not done
            counter_prev <= counter;      -- always lag by 1

            case state is

                when IDLE =>
                    counter <= 0;
                    if start = '1' then
                        -- BUGFIX(addr pipeline): drive 0x0004 during the upcoming
                        -- FETCH cycle so that mem[1]=W[0] is the value returned at
                        -- LOAD counter=0. (length word mem[0] is already in flight.)
                        addr_reg <= x"0004";
                        state    <= FETCH;
                    else
                        -- keep addr at 0x0000 so memory pre-fetches the length word
                        addr_reg <= x"0000";
                    end if;

                when FETCH =>
                    -- mem_data = memory[0x0000] = length in bits
                    -- (IDLE held addr=0x0000 for >=1 cycle, memory answered)
                    msg_len_bits  <= mem_data;
                    msg_len_words <= (to_integer(unsigned(mem_data(8 downto 0))) + 31) / 32;
                    -- W[0] (mem[1] @ 0x0004) is already in flight from IDLE.
                    -- Queue W[1] (mem[2] @ 0x0008) so it is ready at LOAD counter=1.
                    addr_reg <= x"0008";
                    counter  <= 0;
                    state    <= LOAD;

                when LOAD =>
                    -- pipeline: queue the data word two counts ahead so that
                    -- mem_data at LOAD counter=N equals W[N] = mem[N+1].
                    addr_reg <= std_logic_vector(
                        to_unsigned(16#0004# + (counter + 2) * 4, 16));
                    if counter = 15 then
                        state   <= COMPUTE;
                        counter <= 16;
                    else
                        counter <= counter + 1;
                    end if;

                when COMPUTE =>
                    -- round 63 fires at counter=64; move to ACCUM so the Core has
                    -- one full cycle to add the working vars into H_result before
                    -- the writeback reads H_result.
                    if counter = 64 then
                        cdone_i <= '1';
                        state   <= ACCUM;
                    else
                        counter <= counter + 1;
                    end if;

                when ACCUM =>
                    -- compute_done is high this cycle (cdone_i was set in COMPUTE),
                    -- so the Core latches H_result = H_init + working vars at the
                    -- end of this cycle. Then start the writeback.
                    wb_cnt <= 0;
                    state  <= WRITEBACK;

                when WRITEBACK =>
                    if wb_cnt = 7 then
                        state    <= IDLE;
                        addr_reg <= x"0000";
                    else
                        wb_cnt <= wb_cnt + 1;
                    end if;

            end case;
        end if;
    end process;

    -- ----------------------------------------------------------------
    -- Combinational outputs
    -- ----------------------------------------------------------------

    -- memory read address comes from pipelined register
    mem_addr <= addr_reg;

    -- scheduler input mux
    -- at LOAD counter=N : mem_data = W[N] from memory (pipelined correctly)
    process(state, counter, mem_data, msg_len_bits, msg_len_words)
    begin
        sched_input <= (others => '0');
        if state = LOAD then
            if counter = 15 then
                sched_input <= msg_len_bits;       -- W[15] = 64-bit length (low word)
            elsif counter < msg_len_words then
                sched_input <= mem_data;           -- real message word
            elsif counter = msg_len_words then
                sched_input <= x"80000000";        -- first padding word
            -- else: zero padding (default)
            end if;
        end if;
    end process;

    -- scheduler control
    w_src   <= '0' when state = LOAD else '1';
    shift_e <= '1' when state = LOAD or state = COMPUTE else '0';

    -- round constant
    -- use counter_prev (1 cycle behind) to match when W[N] becomes visible on wt
    -- round N fires at edge N+1: wt=W[N], kt=K[N] (counter_prev = N)
    kt <= K_cons(counter_prev)
          when (state = LOAD or state = COMPUTE)
          else (others => '0');

    -- round enable
    -- disabled at LOAD counter=0 : wt is still 0 (scheduler not yet loaded)
    -- all other LOAD cycles and all COMPUTE cycles are valid
    round_en <= '1' when ((state = LOAD and counter > 0) or state = COMPUTE)
                else '0';

    -- hash_init : fires during FETCH, Core uses it to reset a..h to H_init
    hash_init <= '1' when state = FETCH else '0';

    -- compute_done : 1-cycle pulse when round 63 finishes
    compute_done <= cdone_i;

    -- writeback to memory at 0x2000
    mem_wen   <= '1' when state = WRITEBACK else '0';
    mem_waddr <= std_logic_vector(to_unsigned(16#2000# + wb_cnt * 4, 16));
    mem_wdata <= H_result(wb_cnt);

    -- done: high in IDLE (not busy)
    done <= '1' when state = IDLE else '0';

end architecture rtl;