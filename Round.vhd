----------------------------------------------------------------------------------
-- Company: 
-- Engineer: DIMRI Imad
-- 
-- Create Date: 05/17/2026 07:23:54 PM
-- Design Name: 
-- Module Name: Round - Behavioral
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


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all; 
use work.SHA256_pkg.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity Round is port (
    wt ,kt :   in word;
    a ,b ,c ,d ,e ,f ,g ,h   : in word;
    n_a ,n_b ,n_c ,n_d ,n_e ,n_f ,n_g ,n_h : out word
    );
end Round;

architecture Behavioral of Round is
    signal t1, t2 : word;
begin

    t1 <= std_logic_vector( unsigned(h)
                          + unsigned(big_sigma1(e))
                          + unsigned(ch(e, f, g))
                          + unsigned(kt)
                          + unsigned(wt) );

    t2 <= std_logic_vector( unsigned(big_sigma0(a))
                          + unsigned(maj(a, b, c)) );

   
    n_h <= g;
    n_g <= f;
    n_f <= e;
    n_e <= std_logic_vector(unsigned(d) + unsigned(t1));
    n_d <= c;
    n_c <= b;
    n_b <= a;
    n_a <= std_logic_vector(unsigned(t1) + unsigned(t2));

end Behavioral;
