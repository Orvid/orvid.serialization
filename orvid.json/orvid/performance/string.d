module orvid.performance.string;

// TODO: Unittest.
bool contains(char c)(in string str) @trusted pure nothrow
{
	foreach (char cc; str)
	{
		if (cc == c)
			return true;
	}
	return false;
}

bool equal(string other, bool caseSensitive = true)(in string value) @trusted pure
{
	if (__ctfe)
	{
		static if (caseSensitive)
			return value == other;
		else
		{
			import std.string : toLower, toLowerInPlace;

			// The toLowerInPlace is needed to work around an unknown CTFE bug.
			auto tmp = value.dup;
			tmp.toLowerInPlace();
			return tmp == other.toLower();
		}
	}
	else
	{
		if (value.length != other.length)
			return false;

		static if (caseSensitive)
		{
			return other[] == value[];
		}
		else
		{
			import std.conv : to;
			import std.string : toLower;

			static bool staticEach(dstring a, int i)(dstring str)
			{
				if (str[i].toLower() != a[0])
					return false;

				static if (a.length == 1)
					return true;
				else
					return staticEach!(a[1..$], i + 1)(str);
			}
			return staticEach!(other.toLower().to!dstring(), 0)(value.to!dstring());
		}
	}
}
unittest
{
	import orvid.testing : assertStaticAndRuntime;

	assertStaticAndRuntime!("hello".equal!("hello"));
	assertStaticAndRuntime!(!"Hello".equal!("hello"));
	assertStaticAndRuntime!(!"hello there!".equal!("hello"));

	assertStaticAndRuntime!("hello".equal!("hello", false));
	assertStaticAndRuntime!("Hello".equal!("hello", false));
	assertStaticAndRuntime!(!"Hello There!".equal!("hello", false));
}
