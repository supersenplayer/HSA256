----------------------------------------------------------------------------------
-- Engineer: DIMRI Imad
-- Module Name: Round - Behavioral
-- Description: Single-cycle combinational SHA-256 compression round.
--
--   T1 = h + Sigma1(e) + Ch(e,f,g) + Kt + Wt
--   T2 = Sigma0(a) + Maj(a,b,c)
--   new_a = T1 + T2, new_e = d + T1, others shift down.
--
-- Critical path analysis:
--   The longest combinational path goes through T1 (5-input add chain).
--   For higher Fmax, a registered pre-computation of (Kt + Wt) can be added
--   externally (see SHA256_Core) to reduce this to a 4-input chain, cutting
--   approximately 20% off the critical path.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;
use work.SHA256_pkg.all;

entity Round is port (
    wt, kt            : in word;
    a, b, c, d, e, f, g, h : in word;
    n_a, n_b, n_c, n_d, n_e, n_f, n_g, n_h : out word
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
