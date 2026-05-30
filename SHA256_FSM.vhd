library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sha256_pkg.all;

-- Multi-block SHA-256 FSM
--
-- Memory layout (host pre-pads the message into N x 512-bit blocks):
--   0x0000 : number of blocks N (32-bit unsigned, only low 8 bits used)
--   0x0004 + block*64 + word*4 : W[word] of each block (16 words per block)
-- Result written to 0x2000..0x201C (H0..H7)
--
-- Address pipeline: synchronous RAM has 1-cycle read latency. The address
-- present on rd_addr BEFORE a rising_edge determines rd_data AFTER that edge.
-- States are arranged so that the address for W[N] is driven 1 cycle before
-- it is needed.
--
-- First block:  IDLE(start) -> READ_NBLK -> LOAD(x16) -> COMPUTE -> ACCUM
-- Next blocks:  ACCUM -> PREFETCH -> LOAD(x16) -> COMPUTE -> ACCUM
-- Final:        ACCUM -> WRITEBACK -> IDLE

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
    hash_init    : out std_logic;   -- copy H_result -> working regs a..h
    compute_done : out std_logic;   -- 1-cycle pulse: block's 64 rounds done
    block_init   : out std_logic;   -- 1-cycle pulse: H_result <= H_init

    H_result     : in  word_8
);
end entity;

architecture rtl of SHA256_FSM is

    type state_t is (IDLE, READ_NBLK, PREFETCH, LOAD, COMPUTE, ACCUM, WRITEBACK);
    signal state : state_t := IDLE;

    signal counter      : integer range 0 to 64 := 0;
    signal counter_prev : integer range 0 to 64 := 0;

    signal wb_cnt     : integer range 0 to 7 := 0;
    signal addr_reg   : std_logic_vector(15 downto 0) := x"0000";
    signal num_blocks : integer range 0 to 255 := 0;
    signal block_idx  : integer range 0 to 255 := 0;
    signal cdone_i    : std_logic := '0';
    signal binit_i    : std_logic := '0';

    -- Helper: byte-address of W[0] of block B = 0x0004 + B*64
    function blk_word_addr(blk : integer; w : integer) return integer is
    begin
        return 4 + blk * 64 + w * 4;
    end function;

begin

    process(clk)
    begin
        if rst = '1' then
            state        <= IDLE;
            counter      <= 0;
            counter_prev <= 0;
            wb_cnt       <= 0;
            addr_reg     <= x"0000";
            num_blocks   <= 0;
            block_idx    <= 0;
            cdone_i      <= '0';
            binit_i      <= '0';

        elsif rising_edge(clk) then
            cdone_i      <= '0';
            binit_i      <= '0';
            counter_prev <= counter;

            case state is

                when IDLE =>
                    counter <= 0;
                    if start = '1' then
                        -- Drive W[0] addr of block 0 (= 0x0004).
                        -- mem will deliver num_blocks next cycle (from steady 0x0000).
                        addr_reg <= std_logic_vector(to_unsigned(blk_word_addr(0, 0), 16));
                        state    <= READ_NBLK;
                    else
                        -- Keep 0x0000 on the bus so num_blocks is pre-fetched
                        addr_reg <= x"0000";
                    end if;

                when READ_NBLK =>
                    -- mem_data = mem[0x0000] = num_blocks (from IDLE's steady addr)
                    num_blocks <= to_integer(unsigned(mem_data(7 downto 0)));
                    block_idx  <= 0;
                    binit_i    <= '1';   -- H_result <= H_init
                    -- Drive W[1] addr of block 0 (= 0x0008)
                    addr_reg   <= std_logic_vector(to_unsigned(blk_word_addr(0, 1), 16));
                    counter    <= 0;
                    state      <= LOAD;
                    -- hash_init fires combinationally during READ_NBLK (see below)

                when PREFETCH =>
                    -- Used for blocks 1,2,... after ACCUM loops back.
                    -- ACCUM already drove W[0] addr of new block.
                    -- Now drive W[1] addr.
                    addr_reg <= std_logic_vector(
                        to_unsigned(blk_word_addr(block_idx, 1), 16));
                    counter  <= 0;
                    state    <= LOAD;

                when LOAD =>
                    -- mem_data = W[counter] of current block.
                    -- Drive address for W[counter+2].
                    addr_reg <= std_logic_vector(
                        to_unsigned(blk_word_addr(block_idx, counter + 2), 16));
                    if counter = 15 then
                        state   <= COMPUTE;
                        counter <= 16;
                    else
                        counter <= counter + 1;
                    end if;

                when COMPUTE =>
                    if counter = 64 then
                        cdone_i <= '1';
                        state   <= ACCUM;
                    else
                        counter <= counter + 1;
                    end if;

                when ACCUM =>
                    -- compute_done was high prev cycle; Core latches H += a..h now.
                    if block_idx + 1 < num_blocks then
                        -- More blocks: drive W[0] addr of next block
                        block_idx <= block_idx + 1;
                        addr_reg  <= std_logic_vector(
                            to_unsigned(blk_word_addr(block_idx + 1, 0), 16));
                        state     <= PREFETCH;
                    else
                        wb_cnt <= 0;
                        state  <= WRITEBACK;
                    end if;

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

    mem_addr    <= addr_reg;

    -- Scheduler input: pass memory data directly (host pre-pads)
    sched_input <= mem_data when state = LOAD else (others => '0');

    -- Scheduler control
    w_src   <= '0' when state = LOAD else '1';
    shift_e <= '1' when state = LOAD or state = COMPUTE else '0';

    -- Round constant: counter_prev aligns kt with wt (valid range 0..63)
    kt <= K_cons(counter_prev)
          when ((state = LOAD or state = COMPUTE) and counter_prev < 64)
          else (others => '0');

    -- Round enable: disabled at LOAD counter=0 (scheduler not yet loaded)
    round_en <= '1' when ((state = LOAD and counter > 0) or state = COMPUTE)
                else '0';

    -- hash_init: fires during READ_NBLK (first block) and PREFETCH (subsequent blocks)
    -- This copies current H_result into working registers a..h.
    hash_init <= '1' when (state = READ_NBLK or state = PREFETCH) else '0';

    -- block_init: fires once to set H_result = H_init
    block_init <= binit_i;

    -- compute_done
    compute_done <= cdone_i;

    -- Writeback
    mem_wen   <= '1' when state = WRITEBACK else '0';
    mem_waddr <= std_logic_vector(to_unsigned(16#2000# + wb_cnt * 4, 16));
    mem_wdata <= H_result(wb_cnt);

    -- Done
    done <= '1' when state = IDLE else '0';

end architecture rtl;
