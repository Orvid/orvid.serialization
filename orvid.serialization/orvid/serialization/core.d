module orvid.serialization.core;

import std.range : isOutputRange;

enum optional;
enum serializable;
enum nonSerialized;
enum ignoreUndefined;
struct serializeAs { string Name; }

/++
 + This is the output range used by the serialization mechanics to
 + allow a uniform interface. It uses a backing range internally.
 +/
struct BinaryOutputRange(OR)
	if (isOutputRange!(OR, ubyte[]))
{
	import std.traits : isIntegral, isSomeChar;

private:
	OR mInnerRange;
	
	// TODO: Support big endian output.
	version(BigEndian)
		static assert(0, "Support for a big-endian host still needs to be added!");
	
public:
	@property OR innerRange()
	{
		return mInnerRange;
	}
	
	this(OR init)
	{
		mInnerRange = init;
	}
	
	auto opDispatch(string s, Args...)(Args a) @trusted
	{
		mixin("return mInnerRange." ~ s ~ "(a);");
	}
	
	void put(C)(C[] arr) @trusted
		if (isIntegral!C || isSomeChar!C)
	{
		mInnerRange.put(cast(ubyte[])arr);
	}
	
	void put(C)(C c) @trusted
		if (isIntegral!C || isSomeChar!C)
	{
		static if (C.sizeof == 1)
		{
			mInnerRange.put(cast(ubyte)c);
		}
		else
		{
			if (__ctfe)
			{
				for (size_t i = 0; i < C.sizeof; i++)
					mInnerRange.put(cast(ubyte)((c >> (i * 8)) & 0xFF));
			}
			else
			{
				mInnerRange.put(cast(ubyte[])(&c)[0..C.sizeof]);
			}
		}
	}
}
unittest
{
	import std.array : Appender;
	import std.range : isOutputRange;
	
	static assert(isOutputRange!(BinaryOutputRange!(Appender!(ubyte[])), string));
	static assert(isOutputRange!(BinaryOutputRange!(Appender!(ubyte[])), wstring));
	static assert(isOutputRange!(BinaryOutputRange!(Appender!(ubyte[])), dstring));
	static assert(isOutputRange!(BinaryOutputRange!(Appender!(ubyte[])), byte[]));
	static assert(isOutputRange!(BinaryOutputRange!(Appender!(ubyte[])), ubyte[]));
	static assert(isOutputRange!(BinaryOutputRange!(Appender!(ubyte[])), short[]));
	static assert(isOutputRange!(BinaryOutputRange!(Appender!(ubyte[])), ushort[]));
	static assert(isOutputRange!(BinaryOutputRange!(Appender!(ubyte[])), int[]));
	static assert(isOutputRange!(BinaryOutputRange!(Appender!(ubyte[])), uint[]));
	static assert(isOutputRange!(BinaryOutputRange!(Appender!(ubyte[])), long[]));
	static assert(isOutputRange!(BinaryOutputRange!(Appender!(ubyte[])), ulong[]));
	static assert(!isOutputRange!(BinaryOutputRange!(Appender!(ubyte[])), float[]));
	static assert(!isOutputRange!(BinaryOutputRange!(Appender!(ubyte[])), double[]));
	static assert(!isOutputRange!(BinaryOutputRange!(Appender!(ubyte[])), real[]));
}


abstract class SerializationFormat
{
	import orvid.traitsExt : 
		Dequal,
		getDefaultMemberValue,
		getMemberAttribute,
		getMemberValue,
		hasAttribute,
		hasPublicDefaultConstructor,
		isClass,
		isStruct,
		isMemberField,
		MemberType,
		memberHasAttribute
	;
	
protected:
	static struct SerializedFieldSet(T)
	{
		import orvid.performance.bitmanip : BitArray;
		
		alias members = membersToSerialize!T;
		// TODO: This is currently required due to
		// an issue with evaluation order and templates.
		enum membersLength = members.length;
		
		mixin(genDeclarations());
		private static string genDeclarations()
		{
			import std.conv : to;
			import std.array : Appender;
			
			auto ret = Appender!string();
			
			ret.put(`BitArray!`);
			ret.put(to!string(membersLength));
			ret.put(` fieldMarkers;`);
			
			BitArray!membersLength expectedArr;
			foreach (i, m; members)
			{
				if (!isMemberOptional!(T, m))
					expectedArr[i] = true;
			}
			ret.put(`private enum expectedFieldsEnum = BitArray!`);
			ret.put(to!string(membersLength));
			ret.put(`([`);
			foreach (i, d; expectedArr.data)
			{
				if (i != 0)
					ret.put(',');
				ret.put(`0x`);
				ret.put(to!string(d, 16));
			}
			ret.put(`]);`);
			ret.put(`private static immutable expectedFields = expectedFieldsEnum;`);
			
			return ret.data;
		}
		
		@property void markSerialized(string member)() @safe pure nothrow
		{
			import std.traits : staticIndexOf;
			
			fieldMarkers[staticIndexOf!(member, members)] = true;
		}
		
		void ensureFullySerialized() @safe pure
		{
			// TODO: A bug in DMD means that expectedFields isn't accessible in
			//       CTFE. Once that's fixed, change this.
			if (__ctfe)
			{
				fieldMarkers &= expectedFieldsEnum;
				if (fieldMarkers != expectedFieldsEnum)
					throw new Exception("A required field was not deserialized!");
			}
			else
			{
				fieldMarkers &= expectedFields;
				if (fieldMarkers != expectedFields)
					throw new Exception("A required field was not deserialized!");
			}
		}
	}
	
	enum deserializationContext;
	enum isDeserializationContext(T) = hasAttribute!(T, deserializationContext);

	template isSerializable(T)
	{
		import std.traits : isBuiltinType;
		
		static if (isBuiltinType!T)
			enum isSerializable = true;
		else static if (hasAttribute!(T, serializable) || is(Dequal!T == Object))
			enum isSerializable = true;
		else
			enum isSerializable = false;
	}
	
	static void ensurePublicConstructor(T)() @safe pure nothrow
	{
		static if (isClass!T)
			static assert(hasPublicDefaultConstructor!T, `The class '` ~ T.stringof ~ `' doesn't have a publicly visible constructor!`);
		else static if (isStruct!T)
			static assert(__traits(getProtection, T) == "public", `The struct '` ~ T.stringof ~ `' doesn't have a publicly visible constructor!`);
		else
			static assert(0, "Not yet implemented!");
	}
	
	template membersToSerialize(T)
	{
		alias CTValSet(E...) = E;
		enum shouldSerializeMember(string member) = member != "this" && isMemberField!(T, member) && !memberHasAttribute!(T, member, nonSerialized);
		
		// TODO: This needs to deal with inherited members that have the same name.
		template membersToSerializeImpl(T, Members...)
		{
			static if (Members.length > 1)
			{
				static if (shouldSerializeMember!(Members[0]))
					alias membersToSerializeImpl = CTValSet!(Members[0], membersToSerializeImpl!(T, Members[1..$]));
				else
					alias membersToSerializeImpl = membersToSerializeImpl!(T, Members[1..$]);
			}
			else
			{
				static if (shouldSerializeMember!(Members[0]))
					alias membersToSerializeImpl = CTValSet!(Members[0]);
				else
					alias membersToSerializeImpl = CTValSet!();
			}
		}
		alias membersToSerialize = membersToSerializeImpl!(T, __traits(allMembers, T));
	}
	
	enum isMemberOptional(T, string member) = memberHasAttribute!(T, member, optional);

	export static bool shouldSerializeValue(T, string member)(T val) @trusted
	{
		static if (isMemberOptional!(T, member))
		{
			static if (!__traits(compiles, getDefaultMemberValue!(T, member) == getMemberValue!member(val)))
			{
				if (getDefaultMemberValue!(T, member) is getMemberValue!member(val))
					return false;
			}
			else
			{
				if (getDefaultMemberValue!(T, member) == getMemberValue!member(val))
					return false;
			}
		}
		return true;
	}
	enum getFinalMemberName(T, string member) = memberHasAttribute!(T, member, serializeAs) ? getMemberAttribute!(T, member, serializeAs).Name : member;

	// The parent parameter is needed to work around a limitation of template this parameters.
	protected static void baseSerialize(alias Parent, T, OR)(ref BinaryOutputRange!OR output, T val) @trusted
		if (isOutputRange!(OR, ubyte[]))
	{
		// This is designed to reduce the number of times the deserialization templates
		// are instantiated. (and make the type checks within them much simpler)
		static if (!is(Dequal!T == T))
		{
			baseSerialize(output, cast(Dequal!T)val);
		}
		else
		{
			import std.conv : to;
			import std.traits : isBuiltinType;
			import orvid.traitsExt : isEnum;
			
			// TODO: Figure out a way that this can be done without needing to
			//       allocate a string for the value. Unfortunately this currently
			//       is prevented by the need to process the actual string.
			static if (__traits(compiles, (cast(T)T.init).toString()) && !__traits(isSame, T.toString, Object.toString))
			{
				Parent.serialize(output, val.toString());
			}
			else static if ((isBuiltinType!T || isEnum!T) && __traits(compiles, to!string(cast(T)T.init)))
			{
				Parent.serialize(output, to!string(val));
			}
			else
				static assert(0, typeof(this).stringof ~ " does not support serializing a " ~ T.stringof ~ ", and the type does not implement toString!");
		}
	}

	protected static T baseDeserializeValue(T, PT)(ref PT ctx) @trusted
		if (isDeserializationContext!PT)
	{
		// This is designed to reduce the number of times the deserialization templates
		// are instantiated. (and make the type checks within them much simpler)
		static if (!is(Dequal!T == T))
		{
			return cast(T)deserializeValue!(Dequal!T)(ctx);
		}
		else
		{
			import std.conv : to;
			import std.traits : isBuiltinType;
			import orvid.traitsExt : isEnum;
			
			static if (__traits(compiles, T.parse("")))
			{
				T v = T.parse(ctx.current.stringValue);
				ctx.consume();
				return v;
			}
			else static if (__traits(compiles, to!T("")))
			{
				T v = to!T(ctx.current.stringValue);
				ctx.consume();
				return v;
			}
			else
				static assert(0, typeof(this).stringof ~ " does not support deserializing a " ~ T.stringof ~ ", and the type does not implement parse!");
		}
	}
	
public:
	@property static bool isDynamicType(T)()
	{
		T val;
		enum isDynamicType =
			__traits(compiles, cast(bool)val)
			&& __traits(compiles, val = true)
			&& __traits(compiles, cast(string)val)
			&& __traits(compiles, val = "")
			&& __traits(compiles, cast(long)val)
			&& __traits(compiles, val = 2L)
			&& __traits(compiles, cast(real)val)
			&& __traits(compiles, val = 2.0)
			&& __traits(compiles, (val["test"] = 2))
			&& __traits(compiles, val = null)
			&& is(typeof(val.isTypeBoolean()) == bool)
			&& is(typeof(val.isTypeString()) == bool)
			&& is(typeof(val.isTypeArray()) == bool)
			&& is(typeof(val.isTypeObject()) == bool)
			&& is(typeof(val.isTypeNumeric()) == bool)
			&& is(typeof(val.isTypeIntegral()) == bool)
		;
		return isDynamicType;
	}

	abstract ubyte[] serialize(T)(T val);
	abstract T deserialize(T)(ubyte[] data);
}
