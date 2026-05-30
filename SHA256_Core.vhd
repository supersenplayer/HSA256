library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sha256_pkg.all;

-- SHA256_Core: top-level datapath
--   - Multi-block support: H_result accumulates across blocks
--   - Single-cycle round with pre-computed KW optimization for reduced
--     critical path (Kt+Wt sum is registered one cycle ahead)

entity SHA256_Core is port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    start     : in  std_logic;
    done      : out std_logic;
    mem_addr  : out std_logic_vector(15 downto 0);
    mem_data  : in  word;
    mem_wen   : out std_logic;
    mem_waddr : out std_logic_vector(15 downto 0);
    mem_wdata : out word
);
end entity;

architecture rtl of SHA256_Core is

    signal w_src, shift_e, round_en, hash_init, compute_done : std_logic;
    signal block_init : std_logic;
    signal sched_input, wt, kt : word;
    signal H_result : word_8;

    -- Working registers
    signal ra, rb, rc, rd, re, rf, rg, rh : word;
    signal n_a, n_b, n_c, n_d, n_e, n_f, n_g, n_h : word;

begin

    -- ==================== Scheduler ====================
    inst_sched : entity work.Scheduler port map (
        clk => clk, rst => rst,
        w_src => w_src, shift_e => shift_e,
        input => sched_input, output => wt
    );

    -- ==================== Round ====================
    inst_round : entity work.Round port map (
        wt => wt, kt => kt,
        a => ra, b => rb, c => rc, d => rd,
        e => re, f => rf, g => rg, h => rh,
        n_a => n_a, n_b => n_b, n_c => n_c, n_d => n_d,
        n_e => n_e, n_f => n_f, n_g => n_g, n_h => n_h
    );

    -- ==================== FSM ====================
    inst_fsm : entity work.SHA256_FSM port map (
        clk => clk, rst => rst, start => start, done => done,
        mem_addr => mem_addr, mem_data => mem_data,
        mem_wen => mem_wen, mem_waddr => mem_waddr, mem_wdata => mem_wdata,
        w_src => w_src, shift_e => shift_e,
        sched_input => sched_input, wt => wt, kt => kt,
        round_en => round_en, hash_init => hash_init,
        compute_done => compute_done, block_init => block_init,
        H_result => H_result
    );

    -- ==================== Datapath ====================
    process(clk)
    begin
        if rst = '1' then
            ra <= H_init(0); rb <= H_init(1);
            rc <= H_init(2); rd <= H_init(3);
            re <= H_init(4); rf <= H_init(5);
            rg <= H_init(6); rh <= H_init(7);
            H_result <= H_init;

        elsif rising_edge(clk) then

            -- Block init: H_result = H_init (first block only)
            if block_init = '1' then
                H_result <= H_init;
            end if;

            -- Per-block init: copy H_result -> working regs
            if hash_init = '1' then
                ra <= H_result(0); rb <= H_result(1);
                rc <= H_result(2); rd <= H_result(3);
                re <= H_result(4); rf <= H_result(5);
                rg <= H_result(6); rh <= H_result(7);
            -- Single-cycle round
            elsif round_en = '1' then
                ra <= n_a; rb <= n_b;
                rc <= n_c; rd <= n_d;
                re <= n_e; rf <= n_f;
                rg <= n_g; rh <= n_h;
            end if;

            -- Accumulate H at end of block
            if compute_done = '1' then
                H_result(0) <= add(H_result(0), ra);
                H_result(1) <= add(H_result(1), rb);
                H_result(2) <= add(H_result(2), rc);
                H_result(3) <= add(H_result(3), rd);
                H_result(4) <= add(H_result(4), re);
                H_result(5) <= add(H_result(5), rf);
                H_result(6) <= add(H_result(6), rg);
                H_result(7) <= add(H_result(7), rh);
            end if;

        end if;
    end process;

end architecture rtl;
