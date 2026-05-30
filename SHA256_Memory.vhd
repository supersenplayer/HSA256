library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sha256_pkg.all;

entity SHA256_Memory is port (
    clk     : in  std_logic;
    rd_addr : in  std_logic_vector(15 downto 0);
    rd_data : out word;
    wr_en   : in  std_logic;
    wr_addr : in  std_logic_vector(15 downto 0);
    wr_data : in  word
);
end entity;

architecture rtl of SHA256_Memory is
    -- 4096 words = 16KB, covers 0x0000..0x3FFC (byte addresses)
    -- result area 0x2000..0x201C is at word indices 0x800..0x807
    type mem_t is array(0 to 4095) of word;
    signal mem : mem_t := (others => (others => '0'));
begin
    process(clk)
    begin
        if rising_edge(clk) then
            -- synchronous read : 1-cycle latency (addr in -> data next clock)
            rd_data <= mem(to_integer(unsigned(rd_addr(13 downto 2))));
            -- synchronous write
            if wr_en = '1' then
                mem(to_integer(unsigned(wr_addr(13 downto 2)))) <= wr_data;
            end if;
        end if;
    end process;
end architecture rtl;