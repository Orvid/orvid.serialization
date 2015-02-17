module orvid.performance.bitmanip;

// TODO: Unittest.
/++
 + A bit array of a length that is known at compile-time.
 +/
struct BitArray(int length)
{
	import orvid.traitsExt : Dequal;

	enum bitsPerSizeT = size_t.sizeof * 8;
	enum dataLength = (length + (bitsPerSizeT - 1)) / bitsPerSizeT;
	size_t[dataLength] data;

	this(scope size_t[dataLength] initialData)
	{
		this.data = initialData;
	}

	/**********************************************
     * Gets the `i`'th bit in the `BitArray`.
     */
	bool opIndex(size_t i) const @trusted pure nothrow @nogc
	{
		import core.bitop : bt;

		assert(i < length);
		return cast(bool)bt(data.ptr, i);
	}
	
	/**********************************************
     * Sets the `i`'th bit in the `BitArray`.
     */
	bool opIndexAssign(bool b, size_t i) @trusted pure nothrow @nogc
	{
		assert(i < length);

		if (__ctfe)
		{
			if (b)
				data[i / bitsPerSizeT] |= (1 << (i & (bitsPerSizeT - 1)));
			else
				data[i / bitsPerSizeT] &= ~(1 << (i & (bitsPerSizeT - 1)));
		}
		else
		{
			import core.bitop : bts, btr;

			if (b)
				bts(data.ptr, i);
			else
				btr(data.ptr, i);
		}
		return b;
	}

	BitArray!length opOpAssign(string op : "&", Barr)(auto ref in Barr a2) @safe pure nothrow @nogc
		if (is(Dequal!Barr == BitArray!length))
	{
		static if (dataLength == 1)
		{
			data[0] &= a2.data[0];
		}
		else
		{
			this.data[] &= a2.data[];
		}
		return this;
	}

	bool opEquals(Barr)(auto ref in Barr a2) @trusted pure nothrow @nogc
		if (is(Dequal!Barr == BitArray!length))
	{
		static if (dataLength == 1)
		{
			return data[0] == a2.data[0];
		}
		else
		{
			return data[] == a2.data[];
		}
	}
}