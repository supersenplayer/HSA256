----------------------------------------------------------------------------------
-- Company: 
-- Engineer: DIMRI Imad
-- 
-- Create Date: 05/17/2026 04:13:17 PM
-- Design Name: 
-- Module Name: TB - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sha256_pkg.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity Scheduler is port (
	clk		:	in std_logic;
	rst		:	in std_logic;
	
	w_src	:	in std_logic; 
	shift_e	:	in std_logic;
	
	input	:	in word;
	output	:	out word
);
end entity;

architecture rtl of Scheduler is
	signal w_window : word_16 := (others => (others => '0'));
	signal new_w	: word;
	begin
	
	new_w <= std_logic_vector(	unsigned(small_sigma1(w_window(14)))
							+	unsigned(w_window(9))
							+	unsigned(small_sigma0(w_window(1)))
							+	unsigned(w_window(0)));
	
	output <= w_window(15);
	
	process(clk)
		begin
		if rst = '1' then
			w_window <= (others => (others => '0'));
			
		elsif rising_edge(clk) then
			if shift_e ='1' then
				w_window(0 to 14) <= w_window(1 to 15); 
			end if;
		
			if w_src = '0' then
				w_window(15) <= input;
			else 
				w_window(15) <= new_w;
			end if;
		end if;
	end process;
	
	
	
end architecture rtl;