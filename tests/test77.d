//T compiles:yes
//T retval:0
//T has-passed:no

void main()
{
	string str = "foobar";

    // This is narrowing, but valid.
	foreach(byte i, c; str) {}
}
