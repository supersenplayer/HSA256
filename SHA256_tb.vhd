----------------------------------------------------------------------------------
-- Self-checking testbench for the SHA-256 co-processor (v2)
--
-- Supports multi-block messages. Host pre-pads the message before loading.
-- Memory layout:
--   0x0000 : number of 512-bit blocks (N)
--   0x0004 + block*64 + word*4 : W[word] of each block
--
-- Tests:
--   1. "abc"  (1 block)  -- classic NIST vector
--   2. "abcd" (1 block)  -- regression from v1
--   3. 56-byte NIST vector (2 blocks) -- multi-block test
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sha256_pkg.all;

entity SHA256_tb is
end entity;

architecture sim of SHA256_tb is

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

    signal core_raddr : std_logic_vector(15 downto 0);
    signal mem_rdata  : word;
    signal core_wen   : std_logic;
    signal core_waddr : std_logic_vector(15 downto 0);
    signal core_wdata : word;

    signal mem_wen   : std_logic;
    signal mem_waddr : std_logic_vector(15 downto 0);
    signal mem_wdata : word;

    signal tb_load  : std_logic := '1';
    signal tb_wen   : std_logic := '0';
    signal tb_waddr : std_logic_vector(15 downto 0) := (others => '0');
    signal tb_wdata : word := (others => '0');

    signal sim_done : boolean := false;
    signal fail_cnt : integer := 0;

    type wvec is array (natural range <>) of word;

    -- Expected digests (verified with Python hashlib.sha256)
    -- "abc"
    constant EXP_ABC : word_8 := (
        x"ba7816bf", x"8f01cfea", x"414140de", x"5dae2223",
        x"b00361a3", x"96177a9c", x"b410ff61", x"f20015ad");
    -- "abcd"
    constant EXP_ABCD : word_8 := (
        x"88d4266f", x"d4e6338d", x"13b845fc", x"f289579d",
        x"209c8978", x"23b9217d", x"a3e16193", x"6f031589");
    -- 56-byte NIST: "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
    constant EXP_2BLK : word_8 := (
        x"248d6a61", x"d20638b8", x"e5c02693", x"0c3e6039",
        x"a33ce459", x"64ff2167", x"f6ecedd4", x"19db06c1");

    -- Pre-padded message words
    -- "abc" (1 block = 16 words)
    constant MSG_ABC : wvec(0 to 15) := (
        x"61626380", x"00000000", x"00000000", x"00000000",
        x"00000000", x"00000000", x"00000000", x"00000000",
        x"00000000", x"00000000", x"00000000", x"00000000",
        x"00000000", x"00000000", x"00000000", x"00000018");

    -- "abcd" (1 block = 16 words)
    constant MSG_ABCD : wvec(0 to 15) := (
        x"61626364", x"80000000", x"00000000", x"00000000",
        x"00000000", x"00000000", x"00000000", x"00000000",
        x"00000000", x"00000000", x"00000000", x"00000000",
        x"00000000", x"00000000", x"00000000", x"00000020");

    -- 56-byte NIST (2 blocks = 32 words)
    constant MSG_2BLK : wvec(0 to 31) := (
        x"61626364", x"62636465", x"63646566", x"64656667",
        x"65666768", x"66676869", x"6768696a", x"68696a6b",
        x"696a6b6c", x"6a6b6c6d", x"6b6c6d6e", x"6c6d6e6f",
        x"6d6e6f70", x"6e6f7071", x"80000000", x"00000000",
        x"00000000", x"00000000", x"00000000", x"00000000",
        x"00000000", x"00000000", x"00000000", x"00000000",
        x"00000000", x"00000000", x"00000000", x"00000000",
        x"00000000", x"00000000", x"00000000", x"000001c0");

begin

    clk <= '0' when sim_done else not clk after T/2;

    dut_core : entity work.SHA256_Core
        port map (
            clk => clk, rst => rst, start => start, done => done,
            mem_addr => core_raddr, mem_data => mem_rdata,
            mem_wen => core_wen, mem_waddr => core_waddr, mem_wdata => core_wdata);

    mem_wen   <= tb_wen   when tb_load = '1' else core_wen;
    mem_waddr <= tb_waddr when tb_load = '1' else core_waddr;
    mem_wdata <= tb_wdata when tb_load = '1' else core_wdata;

    dut_mem : entity work.SHA256_Memory
        port map (
            clk => clk,
            rd_addr => core_raddr, rd_data => mem_rdata,
            wr_en => mem_wen, wr_addr => mem_waddr, wr_data => mem_wdata);

    stim : process

        procedure mem_write(addr : in integer; data : in word) is
        begin
            tb_wen   <= '1';
            tb_waddr <= std_logic_vector(to_unsigned(addr, 16));
            tb_wdata <= data;
            wait until rising_edge(clk);
        end procedure;

        procedure run_test(name       : in string;
                           num_blocks : in integer;
                           data       : in wvec;
                           expected   : in word_8) is
            variable captured : word_8 := (others => (others => '0'));
            variable idx      : integer;
        begin
            rst     <= '1';
            start   <= '0';
            tb_load <= '1';
            tb_wen  <= '0';
            wait until rising_edge(clk);
            wait until rising_edge(clk);

            -- Write number of blocks at 0x0000
            mem_write(16#0000#, std_logic_vector(to_unsigned(num_blocks, 32)));
            -- Write all pre-padded data words starting at 0x0004
            for i in data'range loop
                mem_write(16#0004# + i * 4, data(i));
            end loop;
            tb_wen  <= '0';
            tb_load <= '0';

            rst <= '0';
            wait until rising_edge(clk);
            wait until rising_edge(clk);

            start <= '1';
            wait until rising_edge(clk);
            start <= '0';

            -- Wait for writeback (8 words)
            idx := 0;
            while idx < 8 loop
                wait until rising_edge(clk);
                if core_wen = '1' then
                    captured(idx) := core_wdata;
                    idx := idx + 1;
                end if;
                -- timeout safety
                if now > 100 us then
                    report "TIMEOUT waiting for writeback!" severity failure;
                end if;
            end loop;

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

            wait until rising_edge(clk);
            wait until rising_edge(clk);
        end procedure;

    begin
        -- Single-block tests
        run_test("abc (1 block)", 1, MSG_ABC, EXP_ABC);
        run_test("abcd (1 block)", 1, MSG_ABCD, EXP_ABCD);
        -- Multi-block test
        run_test("56-byte NIST (2 blocks)", 2, MSG_2BLK, EXP_2BLK);

        report "================================";
        if fail_cnt = 0 then
            report "ALL TESTS PASSED";
        else
            report integer'image(fail_cnt) & " WORD MISMATCH(ES)" severity error;
        end if;
        report "================================";

        sim_done <= true;
        wait;
    end process;

end architecture sim;
