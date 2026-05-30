library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package sha256_pkg is 

subtype word is std_logic_vector(31 downto 0);
type word_8 is array (0 to 7) of word;
type word_16 is array (0 to 15) of word;
type word_64 is array (0 to 63) of word;

constant K_cons : word_64 := (
	x"428a2f98", x"71374491", x"b5c0fbcf", x"e9b5dba5",
    x"3956c25b", x"59f111f1", x"923f82a4", x"ab1c5ed5",
    x"d807aa98", x"12835b01", x"243185be", x"550c7dc3",
    x"72be5d74", x"80deb1fe", x"9bdc06a7", x"c19bf174",
    x"e49b69c1", x"efbe4786", x"0fc19dc6", x"240ca1cc",
    x"2de92c6f", x"4a7484aa", x"5cb0a9dc", x"76f988da",
    x"983e5152", x"a831c66d", x"b00327c8", x"bf597fc7",
    x"c6e00bf3", x"d5a79147", x"06ca6351", x"14292967",
    x"27b70a85", x"2e1b2138", x"4d2c6dfc", x"53380d13",
    x"650a7354", x"766a0abb", x"81c2c92e", x"92722c85",
    x"a2bfe8a1", x"a81a664b", x"c24b8b70", x"c76c51a3",
    x"d192e819", x"d6990624", x"f40e3585", x"106aa070",
    x"19a4c116", x"1e376c08", x"2748774c", x"34b0bcb5",
    x"391c0cb3", x"4ed8aa4a", x"5b9cca4f", x"682e6ff3",
    x"748f82ee", x"78a5636f", x"84c87814", x"8cc70208",
    x"90befffa", x"a4506ceb", x"bef9a3f7", x"c67178f2"
);
constant H_init : word_8 := (
	x"6a09e667", x"bb67ae85", x"3c6ef372", x"a54ff53a",
	x"510e527f", x"9b05688c", x"1f83d9ab", x"5be0cd19"
);

function CH (
	x : in word;
	y : in word;
	z : in word
	) 
	return word;
	
function MAJ (
	x : in word;
	y : in word;
	z : in word
	) 
	return word;	

function ROTR (
	x : in word;
	n : in integer
	)
	return word;
	
function SHR (
	x : in word;
	n : in integer
	)
	return word;
	
function small_sigma0 (
	x : in word
	)
	return word;
	
function small_sigma1 (
	x : in word
	)
	return word;
		
function big_sigma0 (
	x : in word
	)
	return word;
		
function big_sigma1 (
	x : in word
	)
	return word;
	
function add (
	x : in word;
	y : in word
	)
	return word;

end package sha256_pkg;

package body sha256_pkg is 	

function MAJ (x : in word; y : in word; z : in word) return word is
        begin
        return (x and y) xor (x and z) xor (y and z);
    end function MAJ;

function CH (x : in word; y : in word; z : in word) return word is
        begin 
        return (x and y) xor ((not x) and z);
    end function CH;

function ROTR (x : in word;	n : in integer)	return word is
		begin
		return x(n-1 downto 0) & x(31 downto n);
	end function ROTR; 
	
function SHR (x : in word;	n : in integer)	return word is
		begin
		return (n-1 downto 0 => '0') & x(31 downto n);
	end function SHR;
	
function small_sigma0 (x : in word)	return word is
		begin
		return ROTR(x,7) xor ROTR(x,18) xor SHR(x,3);
	end function small_sigma0;
	
function small_sigma1 (x : in word)	return word is
		begin
		return ROTR(x,17) xor ROTR(x,19) xor SHR(x,10);
	end function small_sigma1;

function big_sigma0 (x : in word)	return word is
		begin
		return ROTR(x,2) xor ROTR(x,13) xor ROTR(x,22);
	end function big_sigma0;
	
function big_sigma1 (x : in word)	return word is
		begin
		return ROTR(x,6) xor ROTR(x,11) xor ROTR(x,25);
	end function big_sigma1;
	
function add (x : in word;	y : in word)	return word is
		begin
		return std_logic_vector(unsigned(x)+unsigned(y));
	end function add;
	
end package body sha256_pkg;