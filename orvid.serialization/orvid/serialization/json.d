module orvid.serialization.json;

import std.range : isOutputRange;
import orvid.serialization : BinaryOutputRange, ignoreUndefined, SerializationFormat;

// TODO: Add support for unions.
// TODO: Add support for Tuple's.
// TODO: Add support for private members.
// TODO: Provide a nice error message when trying to deserialize a member marked as nonSerialized.
final class JSONSerializationFormat : SerializationFormat
{
	import std.range : isInputRange;
	import std.traits : ForeachType, isAssociativeArray, isArray, KeyType, ValueType;
	import orvid.traitsExt : constructDefault, Dequal, isClass, isStruct, isOneOf;

//	// TODO: Unittest these 2 methods.
//	final override ubyte[] serialize(T)(T val) 
//	{
//		return cast(ubyte[])toJSON(val); 
//	}
	final override T deserialize(T)(ubyte[] data)
	{
		return fromJSON!T(cast(string)data); 
	}

	template isNativeSerializationSupported(T)
	{
		static if (is(Dequal!T == T))
		{
			static if (isDynamicType!T)
				enum isNativeSerializationSupported = true;
			else static if (isAssociativeArray!T)
				enum isNativeSerializationSupported = isNativeSerializationSupported!(Dequal!(KeyType!T)) && isNativeSerializationSupported!(ValueType!T);
			else static if (isArray!T)
				enum isNativeSerializationSupported = isNativeSerializationSupported!(ForeachType!T);
			else static if (isSerializable!T)
			{
				enum isNativeSerializationSupported =
					   isClass!T
					|| isStruct!T
					|| isOneOf!(T, byte, ubyte, short, ushort, int, uint, long, ulong/*, cent, ucent*/)
					|| isOneOf!(T, float, double, real)
					|| is(T == bool)
					|| isOneOf!(T, char, wchar, dchar)
				;
			}
			else
				enum isNativeSerializationSupported = false;
		}
		else
		{
			enum isNativeSerializationSupported = false;
		}
	}

	private static void serializeChar(bool writeQuotes = true, T, OR)(ref BinaryOutputRange!OR outputRange, T val)
		if (isOutputRange!(OR, ubyte[]) && isOneOf!(T, char, wchar, dchar))
	{
		import std.format : formattedWrite;
		
		static if (writeQuotes)
			outputRange.put('"');

		switch (val)
		{
			case '"':
				outputRange.put(`\"`);
				break;
			case '\\':
				outputRange.put("\\\\");
				break;
			case '/':
				outputRange.put("\\/");
				break;
			case '\b':
				outputRange.put("\\b");
				break;
			case '\f':
				outputRange.put("\\f");
				break;
			case '\n':
				outputRange.put("\\n");
				break;
			case '\r':
				outputRange.put("\\r");
				break;
			case '\t':
				outputRange.put("\\t");
				break;
			case 0x20, 0x21:
			case 0x23: .. case 0x2E:
			case 0x30: .. case 0x5B:
			case 0x5D: .. case 0x7E:
				outputRange.put(cast(char)val);
				break;
			default:
				if (val <= 0xFFFF)
					formattedWrite(outputRange, "\\u%04X", cast(ushort)val);
				else
					// NOTE: This is non-standard behaviour, but allows us to (de)serialize dchars.
					formattedWrite(outputRange, "\\x%08X", cast(uint)val);
				break;
		}

		static if (writeQuotes)
			outputRange.put('"');
	}

	protected static void serialize(T, OR)(ref BinaryOutputRange!OR output, T val) @trusted
		if (isOutputRange!(OR, ubyte[]))
	{
		static if (!is(Dequal!T == T))
		{
			serialize(output, cast(Dequal!T)val);
		}
		else static if (!isNativeSerializationSupported!T)
		{
			baseSerialize!JSONSerializationFormat(output, val);
		}
		else static if (isDynamicType!T)
		{
			if (val.isTypeBoolean)
				serialize(output, cast(bool)val);
			else if (val.isTypeString)
				serialize(output, cast(string)val);
			else if (val.isTypeArray)
			{
				output.put('[');
				for (size_t i = 0; i < cast(size_t)val.length; i++)
				{
					if (i != 0)
						output.put(',');
					serialize(output, val[i]);
				}
				output.put(']');
			}
			else if (val.isTypeObject)
			{
				if (!val)
					output.put("null");
				else
				{
					output.put('{');
					size_t i = 0;
					foreach (k, v; val)
					{
						if (i != 0)
							output.put(',');
						serialize(output, k);
						output.put(':');
						serialize(output, v);
						i++;
					}
					output.put('}');
				}
			}
			else if (val.isTypeNumeric)
			{
				if (val.isTypeIntegral)
					serialize(output, cast(long)val);
				else
					serialize(output, cast(real)val);
			}
			else
				output.put(`"<unknown>"`);
		}
		else static if (isClass!T || isStruct!T)
		{
			static if (isClass!T)
			{
				if (val is null)
				{
					output.put("null");
					return;
				}
			}
			ensurePublicConstructor!T();
			output.put('{');
			size_t i = 0;
			foreach (member; membersToSerialize!T)
			{
				import orvid.traitsExt : getMemberValue;
				
				if (!shouldSerializeValue!(T, member)(val))
					continue;
				if (i != 0)
					output.put(',');
				output.put(`"` ~ getFinalMemberName!(T, member) ~ `":`);
				serialize(output, getMemberValue!member(val));
				i++;
			}
			output.put('}');
		}
		else static if (isAssociativeArray!T)
		{
			output.put('{');
			bool first = true;
			foreach (ref k, ref v; val)
			{
				if (!first)
					output.put(',');
				serialize(output, k);
				output.put(':');
				serialize(output, v);
				first = false;
			}
			output.put('}');
		}
		else static if (isOneOf!(T, byte, ubyte, short, ushort, int, uint, long, ulong/*, cent, ucent*/))
		{
			import orvid.performance.conv : to;
			
			val.to!string(output);
		}
		else static if (isOneOf!(T, float, double, real))
		{
			import std.conv : to;
			
			if (cast(T)cast(long)val == val)
				serialize(output, cast(long)val);
			else
				output.put(val.to!string());
		}
		else static if (is(T == bool))
		{
			output.put(val ? "true" : "false");
		}
		else static if (isOneOf!(T, char, wchar, dchar))
		{
			serializeChar(output, val);
		}
		else static if (isArray!T)
		{
			static if (isOneOf!(ForeachType!T, char, wchar, dchar))
			{
				import orvid.performance.conv : to;
				
				static bool isAscii(S)(S str) @safe pure nothrow
				{
					foreach (ch; str)
					{
						switch (ch)
						{
							case 0x20, 0x21:
							case 0x23: .. case 0x2E:
							case 0x30: .. case 0x5B:
							case 0x5D: .. case 0x7E:
								break;
							default:
								return false;
						}
					}
					return true;
				}
				
				output.put('"');
				if (isAscii(val))
					output.put(to!string(val));
				else
				{
					foreach (dchar ch; val)
					{
						serializeChar!(false)(output, ch);
					}
				}
				output.put('"');
			}
			else
			{
				output.put('[');
				foreach(i, v; val)
				{
					if (i != 0)
						output.put(',');
					serialize(output, v);
				}
				output.put(']');
			}
		}
		else
			static assert(0, "Native serialization for the type was supported, but failed to determine how to serialize it!");
	}

	// TODO: Implement the generic input range based version.
	@deserializationContext
	private static struct JSONLexer(Range)
		if (is(Range == string))
	{
		static struct Token
		{
			TokenType type = TokenType.Unknown;
			string stringValue;
			
			string toString()
			{
				import std.conv : to;

				if (type == TokenType.String || type == TokenType.Number)
					return to!string(type) ~ ": " ~ stringValue;
				return to!string(type);
			}
		}
		enum TokenType
		{
			Unknown = 1 << 0,
			String = 1 << 1,
			Number = 1 << 2,
			LCurl = 1 << 3,
			RCurl = 1 << 4,
			LSquare = 1 << 5,
			RSquare = 1 << 6,
			Colon = 1 << 7,
			Comma = 1 << 8,
			False = 1 << 9,
			True = 1 << 10,
			Null = 1 << 11,
			EOF = 1 << 12,
		}
		Range input;
		Token current;
		@property bool EOF() { return current.type == TokenType.EOF; }
		
		this(Range inRange)
		{
			input = inRange;
			// Check for UTF-8 headers.
			if (input.length >= 3 && input[0..3] == x"EF BB BF")
				input = input[3..$];
			// TODO: Check for other UTF versions
			consume();
		}
		
		void expect(TokenTypes...)() @safe
		{
			debug import std.conv : to;
			import std.algorithm : reduce;

			// This right here is the reason the token types are flags;
			// it allows us to do a single direct branch, even for multiple
			// possible token types.
			enum expectedFlags = reduce!((a, b) => cast(ushort)a | cast(ushort)b)(0, [TokenTypes]);
			if ((current.type | expectedFlags) == expectedFlags)
				return;

			debug
				throw new Exception("Unexpected token! `" ~ to!string(current.type) ~ "`!");
			else
				throw new Exception("Unexpected token!"); // TODO: Make more descriptive
		}
		
		void consume() @trusted pure
		{
		Restart:
			if (!input.length)
			{
				current = Token(TokenType.EOF);
				return;
			}

			size_t curI = 0;
			while (curI < input.length)
			{
				switch (input[curI])
				{
					case ' ', '\t', '\v', '\r', '\n':
						input = input[1..$];
						goto Restart;
					case '{':
						current = Token(TokenType.LCurl);
						goto Return;
					case '}':
						current = Token(TokenType.RCurl);
						goto Return;
					case '[':
						current = Token(TokenType.LSquare);
						goto Return;
					case ']':
						current = Token(TokenType.RSquare);
						goto Return;
					case ':':
						current = Token(TokenType.Colon);
						goto Return;
					case ',':
						current = Token(TokenType.Comma);
						goto Return;
						
					case 'F', 'f':
						curI++;
						if (input[curI] != 'a' && input[curI] != 'A')
							goto IdentifierError;
						curI++;
						if (input[curI] != 'l' && input[curI] != 'L')
							goto IdentifierError;
						curI++;
						if (input[curI] != 's' && input[curI] != 'S')
							goto IdentifierError;
						curI++;
						if (input[curI] != 'e' && input[curI] != 'E')
							goto IdentifierError;
						current = Token(TokenType.False);
						goto Return;

					case 'T', 't':
						curI++;
						if (input[curI] != 'r' && input[curI] != 'R')
							goto IdentifierError;
						curI++;
						if (input[curI] != 'u' && input[curI] != 'U')
							goto IdentifierError;
						curI++;
						if (input[curI] != 'e' && input[curI] != 'E')
							goto IdentifierError;
						current = Token(TokenType.True);
						goto Return;

					case 'N', 'n':
						curI++;
						if (input[curI] != 'u' && input[curI] != 'U')
							goto IdentifierError;
						curI++;
						if (input[curI] != 'l' && input[curI] != 'L')
							goto IdentifierError;
						curI++;
						if (input[curI] != 'l' && input[curI] != 'L')
							goto IdentifierError;
						current = Token(TokenType.Null);
						goto Return;
						
					case '"':
						curI++;
						while (curI < input.length)
						{
							// TODO: Make this a switch statement for readability once DMD auto-expands small
							//       switch statements to if-else chains.
							if (input[curI] == '\\')
							{
								// This loop will end if we just passed
								// the end of the file, and throw an EOF
								// exception for us.
								curI += 2;
							}
							else if (input[curI] == '"')
							{
								current = Token(TokenType.String, input[1..curI]);
								goto Return;
							}
							else
								curI++;
						}
						goto EOF;
						
					case '-', '+':
					case '0': .. case '9':
						curI++;
						while (curI < input.length)
						{
							switch (input[curI])
							{
								case 'E', 'e', '+', '-', '.':
								case '0': .. case '9':
									curI++;
									break;
									
								default:
									current = Token(TokenType.Number, input[0..curI]);
									curI--; // Adjust for the +1 used when we return.
									goto Return;
							}
						}
						goto EOF;
						
					default:
						throw new Exception("Unknown input '" ~ input[curI] ~ "'!");
					IdentifierError:
						throw new Exception("Unknown identifier!");
					EOF:
						throw new Exception("Unexpected EOF!");
				}
			}
			
		Return:
			input = input[curI + 1..$];
		}
	}
	
	private static C getCharacter(C)(ref string input) @safe pure
		if (isOneOf!(C, char, wchar, dchar))
	{
		import std.conv : to;

		assert(input.length > 0);

		size_t readLength = 0;
		dchar decoded = '\0';
		
		if (input[0] == '\\')
		{
			if (input.length < 2)
				throw new Exception("Unexpected EOF!");
			switch (input[1])
			{
				case '\\':
				case '/':
				case '"':
					decoded = input[1];
					readLength += 2;
					break;
				case 'B', 'b':
					decoded = '\b';
					readLength += 2;
					break;
				case 'F', 'f':
					decoded = '\f';
					readLength += 2;
					break;
				case 'N', 'n':
					decoded = '\n';
					readLength += 2;
					break;
				case 'R', 'r':
					decoded = '\r';
					readLength += 2;
					break;
				case 'T', 't':
					decoded = '\t';
					readLength += 2;
					break;
					
				case 'U', 'u':
					if (input.length < 6)
						throw new Exception("Unexpected EOF!");
					decoded = to!dchar(to!wchar(to!ushort(input[2..6], 16)));
					readLength += 6;
					break;
				case 'X', 'x':
					if (input.length < 10)
						throw new Exception("Unexpected EOF!");
					decoded = to!dchar(to!uint(input[2..10], 16));
					readLength += 10;
					break;
				default:
					// REVIEW: Should we go for spec compliance (invalid) or for the ability to handle invalid input?
					version(none)
					{
						// Spec Compliance
						throw new Exception("Unknown escape sequence!");
					}
					else
					{
						// Unknown escape sequence, so use the character
						// immediately following the backslash as a literal.
						decoded = input[1];
						readLength += 2;
						break;
					}
			}
		}
		else
		{
			readLength++;
			decoded = input[0];
		}
		
		
		input = input[readLength..$];
		return to!C(decoded);
	}



	protected static T deserializeValue(T, PT)(ref PT parser) @safe
		if (isDeserializationContext!PT)
	{
		return deserializeValue!T(parser, (name, val) => val);
	}
	
	protected static T deserializeValue(T, PT)(ref PT parser, T delegate(string fieldName, T value) callback) @trusted
		if (isDeserializationContext!PT)
	{
		alias TokenType = PT.TokenType;

		// This is designed to reduce the number of times the deserialization templates
		// are instantiated. (and make the type checks within them much simpler)
		static if (!is(Dequal!T == T))
		{
			return cast(T)deserializeValue!(Dequal!T)(parser);
		}
		else static if (!isNativeSerializationSupported!T)
		{
			return baseDeserializeValue!T(parser);
		}
		else static if (isDynamicType!T)
		{
			import orvid.performance.conv : to;
			import orvid.performance.string : contains;

			T v;
			
			switch (parser.current.type)
			{
				case TokenType.LCurl:
					parser.consume();
					T[string] tmp;
					v = tmp;
					bool first = true;
					if (parser.current.type != TokenType.RCurl) do
					{
						if (!first) // The fact we've got here means the current token MUST be a comma.
							parser.consume();
						
						parser.expect!(TokenType.String);
						string fieldName = parser.current.stringValue;
						parser.consume();
						parser.expect!(TokenType.Colon);
						parser.consume();
						T tmpVal = deserializeValue!T(parser);
						v[fieldName] = callback(fieldName, tmpVal);
						
						first = false;
					} while (parser.current.type == TokenType.Comma);
					
					parser.expect!(TokenType.RCurl);
					parser.consume();
					break;
				case TokenType.LSquare:
					parser.consume();
					string[] tmp;
					v = tmp;
					size_t i = 0;
					if (parser.current.type != TokenType.RSquare) do
					{
						if (i != 0) // The fact we got here means that the current token MUST be a comma.
							parser.consume();
						
						v[i] = deserializeValue!T(parser);
						i++;
					} while (parser.current.type == TokenType.Comma);
					parser.expect!(TokenType.RSquare);
					parser.consume();
					break;
				case TokenType.Number:
					if (parser.current.stringValue.contains!('.'))
						v = to!real(parser.current.stringValue);
					else
						v = to!long(parser.current.stringValue);
					parser.consume();
					break;
				case TokenType.String:
					string strVal = parser.current.stringValue;
					if (strVal.contains!('\\'))
					{
						dchar[] dst = new dchar[strVal.length];
						size_t i;
						while (strVal.length > 0)
						{
							dst[i] = getCharacter!dchar(strVal);
							i++;
						}
						
						strVal = to!string(dst[0..i]);
					}
					v = strVal;
					parser.consume();
					break;
				case TokenType.True:
					parser.consume();
					v = true;
					break;
				case TokenType.False:
					parser.consume();
					v = false;
					break;
				case TokenType.Null:
					parser.consume();
					v = null;
					break;
					
				default:
					throw new Exception("Unknown token type!");
			}
			return callback("", v);
		}
		else static if (isClass!T || isStruct!T)
		{
			static void skipValue(ref PT parser)
			{
				switch (parser.current.type)
				{
					case TokenType.LCurl:
						parser.consume();
						bool first = true;
						if (parser.current.type != TokenType.RCurl) do
						{
							if (!first) // The fact we've got here means the current token MUST be a comma.
								parser.consume();
							
							parser.expect!(TokenType.String);
							parser.consume();
							parser.expect!(TokenType.Colon);
							parser.consume();
							skipValue(parser);

							first = false;
						} while (parser.current.type == TokenType.Comma);
						
						parser.expect!(TokenType.RCurl);
						parser.consume();
						break;
					case TokenType.LSquare:
						parser.consume();
						bool first = true;
						if (parser.current.type != TokenType.RSquare) do
						{
							if (!first) // The fact we got here means that the current token MUST be a comma.
								parser.consume();

							skipValue(parser);
							first = false;
						} while (parser.current.type == TokenType.Comma);
						parser.expect!(TokenType.RSquare);
						parser.consume();
						break;
					case TokenType.Number:
						parser.consume();
						break;
					case TokenType.String:
						parser.consume();
						break;
					case TokenType.True:
						parser.consume();
						break;
					case TokenType.False:
						parser.consume();
						break;
					case TokenType.Null:
						parser.consume();
						break;
						
					default:
						throw new Exception("Unknown token type!");
				}
			}
			
			if (parser.current.type == TokenType.Null)
			{
				parser.consume();
				return T.init;
			}
			else if (parser.current.type == TokenType.String)
			{
				import orvid.performance.string : equal;

				// TODO: Support classes/structs with toString & parse methods.
				if (parser.current.stringValue.equal!("null", false))
				{
					parser.consume();
					return T.init;
				}
			}

			ensurePublicConstructor!T();
			T parsedValue = constructDefault!T();
			auto serializedFields = SerializedFieldSet!T();
			bool first = true;
			parser.expect!(TokenType.LCurl);
			parser.consume();
			if (parser.current.type != TokenType.RCurl) do
			{
				if (!first) // The fact we've got here means the current token MUST be a comma.
					parser.consume();
				
				parser.expect!(TokenType.String);
				switch (parser.current.stringValue)
				{
					foreach (member; membersToSerialize!T)
					{
						import orvid.traitsExt : MemberType, setMemberValue;
						
						case getFinalMemberName!(T, member):
							parser.consume();
							parser.expect!(TokenType.Colon);
							parser.consume();
							setMemberValue!member(parsedValue, deserializeValue!(MemberType!(T, member))(parser));
							serializedFields.markSerialized!(member);
							goto ExitSwitch;
					}
					
					default:
						static if (!hasAttribute!(T, ignoreUndefined))
						{
							throw new Exception("Unknown member '" ~ parser.current.stringValue ~ "'!");
						}
						else
						{
							parser.consume();
							parser.expect!(TokenType.Colon);
							parser.consume();
							skipValue(parser);
							break;
						}
				}
				
			ExitSwitch:
				first = false;
				continue;
			} while (parser.current.type == TokenType.Comma);

			parser.expect!(TokenType.RCurl);
			parser.consume();
			
			serializedFields.ensureFullySerialized();
			return parsedValue;
		}
		else static if (isOneOf!(T, char, wchar, dchar))
		{
			parser.expect!(TokenType.String);
			string strVal = parser.current.stringValue;
			T val = getCharacter!T(strVal);
			assert(strVal.length == 0, "Data still remaining after parsing a character!");
			parser.consume();
			return val;
		}
		else static if (isOneOf!(T, float, double, real))
		{
			import std.conv : to;
			
			parser.expect!(TokenType.Number, TokenType.String);
			T val = to!T(parser.current.stringValue);
			parser.consume();
			return val;
		}
		else static if (isOneOf!(T, byte, ubyte, short, ushort, int, uint, long, ulong/*, cent, ucent*/))
		{
			import orvid.performance.conv : parse;
			
			parser.expect!(TokenType.Number, TokenType.String);
			T val = parse!T(parser.current.stringValue);
			parser.consume();
			return val;
		}
		else static if (is(T == bool))
		{
			bool ret;
			parser.expect!(TokenType.True, TokenType.False, TokenType.String);
			if (parser.current.type == TokenType.String)
			{
				import orvid.performance.string : equal;
				
				if (parser.current.stringValue.equal!("true", false))
					ret = true;
				else if (parser.current.stringValue.equal!("false", false))
					ret = false;
				else
					throw new Exception("Invalid string for a boolean!");
			}
			else
				ret = parser.current.type == TokenType.True;
			parser.consume();
			return ret;
		}
		else static if (isAssociativeArray!T)
		{
			bool first = true;
			ValueType!T[KeyType!T] val;
			
			parser.expect!(TokenType.LCurl);
			parser.consume();
			if (parser.current.type != TokenType.RCurl) do
			{
				if (!first) // The fact we've got here means the current token MUST be a comma.
					parser.consume();
				
				// Key types are const, so we have to remove that to get it to be nice...
				auto key = cast(const)deserializeValue!(Dequal!(KeyType!T))(parser);
				
				parser.expect!(TokenType.Colon);
				parser.consume();
				
				if (key in val)
					throw new Exception("Duplicate AA key encountered!");
				val[key] = deserializeValue!(ValueType!T)(parser);
				
				first = false;
			} while (parser.current.type == TokenType.Comma);
			
			parser.expect!(TokenType.RCurl);
			parser.consume();
			return val;
		}
		else static if (isArray!T)
		{
			static if (isOneOf!(ForeachType!T, char, wchar, dchar))
			{
				import orvid.performance.string : contains;
				import std.conv : to;
				
				parser.expect!(TokenType.String);
				string strVal = parser.current.stringValue;
				T val;
				// TODO: Account for strings that are part of a larger string, as well as strings that
				//       can be unescaped in-place. Also look into using alloca to allocate the required
				//       space on the stack for the intermediate string representation.
				if (!strVal.contains!('\\'))
				{
					val = to!T(strVal);
				}
				else
				{
					dchar[] dst = new dchar[strVal.length];
					size_t i;
					while (strVal.length > 0)
					{
						dst[i] = getCharacter!dchar(strVal);
						i++;
					}
					
					val = to!T(dst[0..i]);
				}
				
				parser.consume();
				return val;
			}
			else
			{
				parser.expect!(TokenType.LSquare);
				parser.consume();
				
				// Due to the fact most arrays in JSON will
				// be fairly small arrays, not 4-8k elements,
				// just appending to an existing array is the
				// fastest way to do this.
				T arrVal;
				bool first = true;
				
				if (parser.current.type != TokenType.RSquare) do
				{
					if (!first) // The fact we got here means that the current token MUST be a comma.
						parser.consume();
					
					arrVal ~= deserializeValue!(ForeachType!T)(parser);
					first = false;
				} while (parser.current.type == TokenType.Comma);
				
				parser.expect!(TokenType.RSquare);
				parser.consume();
				
				return arrVal;
			}
		}
		else
			static assert(0, "Native serialization was supported for type, but unable to determine how to serialize it!");
	}
	
	static T fromJSON(T)(string val) @safe
	{
		auto parser = JSONLexer!string(val);

		auto v = deserializeValue!T(parser);
		assert(parser.current.type == JSONLexer!string.TokenType.EOF);
		return v;
	}

	static T fromJSON(T)(string val, T delegate(string name, T val) callback) @safe
		if (isDynamicType!T)
	{
		auto parser = JSONLexer!string(val);
		
		auto v = deserializeValue!T(parser, callback);
		assert(parser.current.type == JSONLexer!string.TokenType.EOF);
		return v;
	}
}

void toJSON(T, OR)(T val, ref OR buf) @safe
	if (isOutputRange!(OR, ubyte[]))
{
	auto bor = BinaryOutputRange!OR(buf);
	JSONSerializationFormat.InnerFunStuff!(OR).serialize(bor, val);
	buf = bor.innerRange;
}

string toJSON(T)(T val) @trusted 
{
	import std.array : Appender;

	auto ret = BinaryOutputRange!(Appender!(ubyte[]))();
	ret.put(""); // This ensures everything is initialized.
	JSONSerializationFormat.serialize(ret, val);
	return cast(string)ret.data;
}
T fromJSON(T)(string val) @safe 
{
	return JSONSerializationFormat.fromJSON!T(val); 
}
T fromJSON(T)(string val, T delegate(string name, T val) callback)
	if (SerializationFormat.isDynamicType!T)
{
	return JSONSerializationFormat.fromJSON!T(val, callback);
}

@safe unittest
{
	import std.algorithm : equal;

	import orvid.serialization : nonSerialized, optional, serializable, serializeAs;
	import orvid.testing : assertStaticAndRuntime;

	@serializable static class PrivateConstructor { private this() { } @optional int A = 3; int B = 5; }
	static assert(!__traits(compiles, { assertStaticAndRuntime!(toJSON(new PrivateConstructor()) == `{"B":5}`); }), "A private constructor was allowed for a serializable class while attempting serialization!");
	static assert(!__traits(compiles, { assertStaticAndRuntime!(fromJSON!PrivateConstructor(`{"B":5}`).B == 5); }), "A private constructor was allowed for a serializable class while attempting deserialization!");
	
	
	static class NonSerializable { @optional int A = 3; int B = 5; }
	assertStaticAndRuntime!(!__traits(compiles, { assert(toJSON(new NonSerializable()) == `{"B":5}`); }), "A class not marked with @serializable was allowed while attempting serialization!");
	assertStaticAndRuntime!(!__traits(compiles, { assert(fromJSON!NonSerializable(`{"B":5}`).B == 5); }), "A class not marked with @serializable was allowed while attempting deserialization!");
	
	
	@serializable static class OptionalField { @optional int A = 3; int B = 5; }
	assertStaticAndRuntime!(toJSON(new OptionalField()) == `{"B":5}`, "An optional field set to its default value was not excluded!");
	assertStaticAndRuntime!(() {
		auto cfa = fromJSON!OptionalField(`{"B":5}`);
		assert(cfa.A == 3);
		assert(cfa.B == 5);
		return true;
	}(), "Failed to correctly deserialize a class with an optional field!");
	
	
	@serializable static class NonSerializedField { int A = 3; @nonSerialized int B = 2; }
	assertStaticAndRuntime!(toJSON(new NonSerializedField()) == `{"A":3}`, "A field marked with @nonSerialized was included!");
	assertStaticAndRuntime!(fromJSON!NonSerializedField(`{"A":3}`).A == 3, "Failed to correctly deserialize a class when a field marked with @nonSerialized was present!");
	
	
	@serializable static class SerializeAsField { int A = 3; @serializeAs(`D`) int B = 5; @nonSerialized int D = 7; }
	assertStaticAndRuntime!(toJSON(new SerializeAsField()) == `{"A":3,"D":5}`, "A field marked with @serializeAs(`D`) failed to serialize as D!");
	assertStaticAndRuntime!(() {
		auto cfa = fromJSON!SerializeAsField(`{"A":3,"D":5}`);
		assert(cfa.A == 3);
		assert(cfa.B == 5);
		assert(cfa.D == 7);
		return true;
	}(), "Failed to correctly deserialize a class when a field marked with @serializeAs was present!");
	
	
	@serializable static class ByteField { byte A = -3; }
	assertStaticAndRuntime!(toJSON(new ByteField()) == `{"A":-3}`, "Failed to correctly serialize a byte field!");
	assertStaticAndRuntime!(fromJSON!ByteField(`{"A":-3}`).A == -3, "Failed to correctly deserialize a byte field!");
	assertStaticAndRuntime!(fromJSON!ByteField(`{"A":"-3"}`).A == -3, "Failed to correctly deserialize a byte field set to the quoted value '-3'!");
	
	
	@serializable static class UByteField { ubyte A = 159; }
	assertStaticAndRuntime!(toJSON(new UByteField()) == `{"A":159}`, "Failed to correctly serialize a ubyte field!");
	assertStaticAndRuntime!(fromJSON!UByteField(`{"A":159}`).A == 159, "Failed to correctly deserialize a ubyte field!");
	assertStaticAndRuntime!(fromJSON!UByteField(`{"A":"159"}`).A == 159, "Failed to correctly deserialize a ubyte field set to the quoted value '159'!");
	
	
	@serializable static class ShortField { short A = -26125; }
	assertStaticAndRuntime!(toJSON(new ShortField()) == `{"A":-26125}`, "Failed to correctly serialize a short field!");
	assertStaticAndRuntime!(fromJSON!ShortField(`{"A":-26125}`).A == -26125, "Failed to correctly deserialize a short field!");
	assertStaticAndRuntime!(fromJSON!ShortField(`{"A":"-26125"}`).A == -26125, "Failed to correctly deserialize a short field set to the quoted value '-26125'!");
	
	
	@serializable static class UShortField { ushort A = 65313; }
	assertStaticAndRuntime!(toJSON(new UShortField()) == `{"A":65313}`, "Failed to correctly serialize a ushort field!");
	assertStaticAndRuntime!(fromJSON!UShortField(`{"A":65313}`).A == 65313, "Failed to correctly deserialize a ushort field!");
	assertStaticAndRuntime!(fromJSON!UShortField(`{"A":"65313"}`).A == 65313, "Failed to correctly deserialize a ushort field set to the quoted value '65313'!");
	
	
	@serializable static class IntField { int A = -2032534342; }
	assertStaticAndRuntime!(toJSON(new IntField()) == `{"A":-2032534342}`, "Failed to correctly serialize an int field!");
	assertStaticAndRuntime!(fromJSON!IntField(`{"A":-2032534342}`).A == -2032534342, "Failed to correctly deserialize an int field!");
	assertStaticAndRuntime!(fromJSON!IntField(`{"A":"-2032534342"}`).A == -2032534342, "Failed to correctly deserialize an int field set to the quoted value '-2032534342'!");
	
	
	@serializable static class UIntField { uint A = 2520041234; }
	assertStaticAndRuntime!(toJSON(new UIntField()) == `{"A":2520041234}`, "Failed to correctly serialize a uint field!");
	assertStaticAndRuntime!(fromJSON!UIntField(`{"A":2520041234}`).A == 2520041234, "Failed to correctly deserialize a uint field!");
	assertStaticAndRuntime!(fromJSON!UIntField(`{"A":"2520041234"}`).A == 2520041234, "Failed to correctly deserialize a uint field set to the quoted value '2520041234'!");
	
	
	@serializable static class LongField { long A = -2305393212345134623; }
	assertStaticAndRuntime!(toJSON(new LongField()) == `{"A":-2305393212345134623}`, "Failed to correctly serialize a long field!");
	assertStaticAndRuntime!(fromJSON!LongField(`{"A":-2305393212345134623}`).A == -2305393212345134623, "Failed to correctly deserialize a long field!");
	assertStaticAndRuntime!(fromJSON!LongField(`{"A":"-2305393212345134623"}`).A == -2305393212345134623, "Failed to correctly deserialize a long field set to the quoted value '-2305393212345134623'!");
	
	
	@serializable static class ULongField { ulong A = 4021352154138321354; }
	assertStaticAndRuntime!(toJSON(new ULongField()) == `{"A":4021352154138321354}`, "Failed to correctly serialize a ulong field!");
	assertStaticAndRuntime!(fromJSON!ULongField(`{"A":4021352154138321354}`).A == 4021352154138321354, "Failed to correctly deserialize a ulong field!");
	assertStaticAndRuntime!(fromJSON!ULongField(`{"A":"4021352154138321354"}`).A == 4021352154138321354, "Failed to correctly deserialize a ulong field set to the quoted value '4021352154138321354'!");
	
	
	//@serializable static class CentField { cent A = -23932104152349231532145324134; }
	//assertStaticAndRuntime!(toJSON(new CentField()) == `{"A":-23932104152349231532145324134}`, "Failed to correctly serialize a cent field!");
	//assertStaticAndRuntime!(fromJSON!CentField(`{"A":-23932104152349231532145324134}`).A == -23932104152349231532145324134, "Failed to correctly deserialize a cent field!");
	//assertStaticAndRuntime!(fromJSON!CentField(`{"A":"-23932104152349231532145324134"}`).A == -23932104152349231532145324134, "Failed to correctly deserialize a cent field set to the quoted value '-23932104152349231532145324134'!");
	
	
	//@serializable static class UCentField { ucent A = 40532432168321451235829354323; }
	//assertStaticAndRuntime!(toJSON(new UCentField()) == `{"A":40532432168321451235829354323}`, "Failed to correctly serialize a ucent field!");
	//assertStaticAndRuntime!(fromJSON!UCentField(`{"A":40532432168321451235829354323}`).A == 40532432168321451235829354323, "Failed to correctly deserialize a ucent field!");
	//assertStaticAndRuntime!(fromJSON!UCentField(`{"A":"40532432168321451235829354323"}`).A == 40532432168321451235829354323, "Failed to correctly deserialize a ucent field set to the quoted value '40532432168321451235829354323'!");
	
	
	// TODO: Test NaN and infinite support.
	// TODO: Why on earth does this have no decimals???
	@serializable static class FloatField { float A = -433200; }
	// TODO: Make this static once float -> string conversion is possible in CTFE
	assert(toJSON(new FloatField()) == `{"A":-433200}`, "Failed to correctly serialize a float field!");
	assertStaticAndRuntime!(fromJSON!FloatField(`{"A":-433200}`).A == -433200, "Failed to correctly deserialize a float field!");
	assertStaticAndRuntime!(fromJSON!FloatField(`{"A":"-433200"}`).A == -433200, "Failed to correctly deserialize a float field set to the quoted value '-433200'!");
	
	
	@serializable static class DoubleField { double A = 3.25432e+53; }
	// TODO: Make this static once double -> string conversion is possible in CTFE
	assert(toJSON(new DoubleField()) == `{"A":3.25432e+53}`, "Failed to correctly serialize a double field!" ~ toJSON(new DoubleField()));
	assertStaticAndRuntime!(fromJSON!DoubleField(`{"A":3.25432e+53}`).A == 3.25432e+53, "Failed to correctly deserialize a double field!");
	assertStaticAndRuntime!(fromJSON!DoubleField(`{"A":"3.25432e+53"}`).A == 3.25432e+53, "Failed to correctly deserialize a double field set to the quoted value '3.25432e+53'!");
	
	
	@serializable static class RealField { real A = -2.13954e+104; }
	// TODO: Make this static once real -> string conversion is possible in CTFE
	assert(toJSON(new RealField()) == `{"A":-2.13954e+104}`, "Failed to correctly serialize a real field!");
	assertStaticAndRuntime!(fromJSON!RealField(`{"A":-2.13954e+104}`).A == -2.13954e+104, "Failed to correctly deserialize a real field!");
	assertStaticAndRuntime!(fromJSON!RealField(`{"A":"-2.13954e+104"}`).A == -2.13954e+104, "Failed to correctly deserialize a real field set to the quoted value '-2.13954e+104'!");
	
	
	@serializable static class CharField { char A = '\x05'; }
	assertStaticAndRuntime!(toJSON(new CharField()) == `{"A":"\u0005"}`, "Failed to correctly serialize a char field!");
	assertStaticAndRuntime!(fromJSON!CharField(`{"A":"\u0005"}`).A == '\x05', "Failed to correctly deserialize a char field!");
	
	
	@serializable static class WCharField { wchar A = '\u04DA'; }
	assertStaticAndRuntime!(toJSON(new WCharField()) == `{"A":"\u04DA"}`, "Failed to correctly serialize a wchar field!");
	assertStaticAndRuntime!(fromJSON!WCharField(`{"A":"\u04DA"}`).A == '\u04DA', "Failed to correctly deserialize a wchar field!");
	
	
	@serializable static class DCharField { dchar A = '\U0010FFFF'; }
	assertStaticAndRuntime!(toJSON(new DCharField()) == `{"A":"\x0010FFFF"}`, "Failed to correctly serialize a dchar field!");
	assertStaticAndRuntime!(fromJSON!DCharField(`{"A":"\x0010FFFF"}`).A == '\U0010FFFF', "Failed to correctly deserialize a dchar field!");
	
	
	@serializable static class StringField { string A = "Hello!\b\"\u08A8\U0010FFFF"; }
	assertStaticAndRuntime!(toJSON(new StringField()) == `{"A":"Hello!\b\"\u08A8\x0010FFFF"}`, "Failed to correctly serialize a string field!");
	assertStaticAndRuntime!(fromJSON!StringField(`{"A":"Hello!\b\"\u08A8\x0010FFFF"}`).A == "Hello!\b\"\u08A8\U0010FFFF", "Failed to correctly deserialize a string field!");
	
	
	@serializable static class WStringField { wstring A = "Hello!\b\"\u08A8\U0010FFFF"w; }
	assertStaticAndRuntime!(toJSON(new WStringField()) == `{"A":"Hello!\b\"\u08A8\x0010FFFF"}`, "Failed to correctly serialize a wstring field!");
	assertStaticAndRuntime!(fromJSON!WStringField(`{"A":"Hello!\b\"\u08A8\x0010FFFF"}`).A == "Hello!\b\"\u08A8\U0010FFFF"w, "Failed to correctly deserialize a wstring field!");
	
	
	() @trusted {
		@serializable static class WCharArrayField { wchar[] A = cast(wchar[])"Hello!\b\"\u08A8\U0010FFFF"w; }
		assertStaticAndRuntime!(toJSON(new WCharArrayField()) == `{"A":"Hello!\b\"\u08A8\x0010FFFF"}`, "Failed to correctly serialize a wchar[] field!");
		assertStaticAndRuntime!(fromJSON!WCharArrayField(`{"A":"Hello!\b\"\u08A8\x0010FFFF"}`).A.equal(cast(wchar[])"Hello!\b\"\u08A8\U0010FFFF"w), "Failed to correctly deserialize a wchar[] field!");
	}();
	
	
	@serializable static class ConstWCharArrayField { const(wchar)[] A = "Hello!\b\"\u08A8\U0010FFFF"w; }
	assertStaticAndRuntime!(toJSON(new ConstWCharArrayField()) == `{"A":"Hello!\b\"\u08A8\x0010FFFF"}`, "Failed to correctly serialize a const(wchar)[] field!");
	assertStaticAndRuntime!(fromJSON!ConstWCharArrayField(`{"A":"Hello!\b\"\u08A8\x0010FFFF"}`).A.equal("Hello!\b\"\u08A8\U0010FFFF"w), "Failed to correctly deserialize a const(wchar)[] field!");
	
	
	@serializable static class DStringField { dstring A = "Hello!\b\"\u08A8\U0010FFFF"d; }
	assertStaticAndRuntime!(toJSON(new DStringField()) == `{"A":"Hello!\b\"\u08A8\x0010FFFF"}`, "Failed to correctly serialize a dstring field!");
	assertStaticAndRuntime!(fromJSON!DStringField(`{"A":"Hello!\b\"\u08A8\x0010FFFF"}`).A == "Hello!\b\"\u08A8\U0010FFFF"d, "Failed to correctly deserialize a dstring field!");
	

	@serializable static class FalseBoolField { bool A; auto Init() { A = false; return this; } }
	assertStaticAndRuntime!(toJSON((new FalseBoolField()).Init()) == `{"A":false}`, "Failed to correctly serialize a bool field set to false!");
	assertStaticAndRuntime!(fromJSON!FalseBoolField(`{"A":false}`).A == false, "Failed to correctly deserialize a bool field set to false!");
	assertStaticAndRuntime!(fromJSON!FalseBoolField(`{"A":"false"}`).A == false, "Failed to correctly deserialize a bool field set to false!");

	
	@serializable static class TrueBoolField { bool A; auto Init() { A = true; return this; } }
	assertStaticAndRuntime!(toJSON((new TrueBoolField()).Init()) == `{"A":true}`, "Failed to correctly serialize a bool field set to true!");
	assertStaticAndRuntime!(fromJSON!TrueBoolField(`{"A":true}`).A == true, "Failed to correctly deserialize a bool field set to true!");
	assertStaticAndRuntime!(fromJSON!TrueBoolField(`{"A":"true"}`).A == true, "Failed to correctly deserialize a bool field set to true!");
	assertStaticAndRuntime!(fromJSON!TrueBoolField(`{"A":"True"}`).A == true, "Failed to correctly deserialize a bool field set to true!");
	assertStaticAndRuntime!(fromJSON!TrueBoolField(`{"A":"tRUe"}`).A == true, "Failed to correctly deserialize a bool field set to true!");

	
	@serializable static class NullObjectField { Object A = null; }
	assertStaticAndRuntime!(toJSON(new NullObjectField()) == `{"A":null}`, "Failed to correctly serialize an Object field set to null!");
	assertStaticAndRuntime!(fromJSON!NullObjectField(`{"A":null}`).A is null, "Failed to correctly deserialize an Object field set to null!");
	assertStaticAndRuntime!(fromJSON!NullObjectField(`{"A":"null"}`).A is null, "Failed to correctly deserialize an Object field set to null!");
	
	
	@serializable static class SerializeAsField2 { int A = 3; @serializeAs(`D`) int B = 5; @nonSerialized int D = 7; }
	@serializable static class ClassField { SerializeAsField2 A = new SerializeAsField2(); }
	assertStaticAndRuntime!(toJSON(new ClassField()) == `{"A":{"A":3,"D":5}}`, "Failed to correctly serialize a class field!");
	assertStaticAndRuntime!(() {
		auto cfa = fromJSON!ClassField(`{"A":{"A":3,"D":5}}`);
		assert(cfa.A);
		assert(cfa.A.A == 3);
		assert(cfa.A.B == 5);
		assert(cfa.A.D == 7);
		return true;
	}(), "Failed to correctly deserialize a class field!");
	
	
	@serializable static class SerializeAsField3 { int A = 3; @serializeAs(`D`) int B = 5; @nonSerialized int D = 7; }
	@serializable static class ClassArrayField { SerializeAsField3[] A = [new SerializeAsField3(), new SerializeAsField3()]; }
	assertStaticAndRuntime!(toJSON(new ClassArrayField()) == `{"A":[{"A":3,"D":5},{"A":3,"D":5}]}`, "Failed to correctly serialize a class array field!");
	assertStaticAndRuntime!(() {
		auto cfa = fromJSON!ClassArrayField(`{"A":[{"A":3,"D":5},{"A":3,"D":5}]}`);
		assert(cfa.A);
		assert(cfa.A.length == 2);
		assert(cfa.A[0].A == 3);
		assert(cfa.A[0].B == 5);
		assert(cfa.A[1].A == 3);
		assert(cfa.A[1].B == 5);
		return true;
	}(), "Failed to correctly deserialize a class array field!");
	
	
	@serializable static class IntArrayField { int[] A = [-3, 6, 190]; }
	assertStaticAndRuntime!(toJSON(new IntArrayField()) == `{"A":[-3,6,190]}`, "Failed to correctly serialize an int[] field!");
	assertStaticAndRuntime!(fromJSON!IntArrayField(`{"A":[-3,6,190]}`).A.equal([-3, 6, 190]), "Failed to correctly deserialize an int[] field!");
	
	
	@serializable static struct StructParent { int A = 3; }
	assertStaticAndRuntime!(toJSON(StructParent()) == `{"A":3}`, "Failed to correctly serialize a structure!");
	assertStaticAndRuntime!(fromJSON!StructParent(`{"A":3}`).A == 3, "Failed to correctly deserialize a structure!");
	
	
	@serializable static struct StructParent2 { int A = 3; }
	@serializable static struct StructField { StructParent2 A; }
	assertStaticAndRuntime!(toJSON(StructField()) == `{"A":{"A":3}}`, "Failed to correctly serialize a struct field!");
	assertStaticAndRuntime!(fromJSON!StructField(`{"A":{"A":3}}`).A.A == 3, "Failed to correctly deserialize a struct field!");
	

	static class ParsableClass 
	{
		import std.conv : to;
		
		int A = 3;
		
		override string toString() @safe pure { return to!string(A); }
		static typeof(this) parse(string str) @safe pure
		{
			auto p = new ParsableClass();
			p.A = to!int(str);
			return p;
		}
	}
	@serializable static class ParsableClassField { ParsableClass A = new ParsableClass(); }
	assertStaticAndRuntime!(toJSON(new ParsableClassField()) == `{"A":"3"}`, "Failed to correctly serialize a non-serializable parsable class!" ~ toJSON(new ParsableClassField()));
	assertStaticAndRuntime!(fromJSON!ParsableClassField(`{"A":"3"}`).A.A == 3, "Failed to correctly deserialize a non-serializable parsable class!");
	
	
	enum EnumTest { valA, valB, valC }
	@serializable static class EnumField { EnumTest A = EnumTest.valB; }
	assertStaticAndRuntime!(toJSON(new EnumField()) == `{"A":"valB"}`, "Failed to correctly serialize an enum!");
	assertStaticAndRuntime!(fromJSON!EnumField(`{"A":"valB"}`).A == EnumTest.valB, "Failed to correctly deserialize an enum!");
}

version (none)
{
	enum JSONElementType
	{
		unknown,
		array,
		boolean,
		number,
		object,
		string,
	}

	final class JSONElement
	{
	private:
		JSONElementType type = JSONElementType.unknown;
		string innerValue;
		
		union
		{
			JSONElement[] arrayValueCache;
			JSONElement[string] objectValueCache;
		}
		
		template jsonElementTypeOf(T)
		{
			import std.traits : isArray, isNumeric, isSomeString;
			
			static if (isArray!T)
				enum jsonElementTypeOf = JSONElementType.array;
			else static if (isNumeric!T)
				enum jsonElementTypeOf = JSONElementType.number;
			else static if (isSomeString!T)
				enum jsonElementTypeOf = JSONElementType.string;
			else static if (is(T == bool))
				enum jsonElementTypeOf = JSONElementType.boolean;
			else
				enum jsonElementTypeOf = JSONElementType.object;
		}

		void ensureObject() @safe pure nothrow
		{
			if (type == JSONElementType.unknown)
				type = JSONElementType.object;
			assert(type == JSONElementType.object);
			if (!objectValueCache && innerValue)
				objectValueCache = fromJSON!(JSONElement[string])(innerValue);
		}

		void ensureArray() @safe pure nothrow
		{
			if (type == JSONElementType.unknown)
				type = JSONElementType.array;
			assert(type == JSONElementType.array);
			if (!arrayValueCache && innerValue)
				arrayValueCache = fromJSON!(JSONElement[])(innerValue);
		}
		
	public:
		this(T val, T)()
		{
			innerValue = toJSON!(val);
			type = jsonElementTypeOf!(T);
		}
		this(T)(in T val)
		{
			innerValue = toJSON(val);
			type = jsonElementTypeOf!(T);
		}
		this()()
		{
		}
		
		JSONElement opIndex(size_t i) @safe pure nothrow
		{
			ensureArray();
			return arrayValueCache[i];
		}

		JSONElement opIndex(in string key) @safe pure nothrow
		{
			ensureObject();
			return objectValueCache[key];
		}
		
		JSONElement opIndexAssign(T)(in T val, in string key) @safe pure nothrow
		{
			ensureObject();
			return objectValueCache[key] = new JSONElement(val);
		}
		
		JSONElement opBinary(string op : "in")(in string key) @safe pure nothrow
		{
			ensureObject();
			return key in objectValueCache;
		}
		
		@property T value(T)() @safe pure nothrow
		{
			return fromJSON!T(innerValue);
		}
	}


	import std.range : isOutputRange;

	final class JSONWriter(OutputRange)
		if (isOutputRange!(OutputRange, string))
	{
		import std.collections : Stack;
		
	private:
		enum WriteContext
		{
			array,
			field,
			object,
		}
		OutputRange output;
		Stack!WriteContext contextStack = new Stack!WriteContext();
		// Believe it or not, we only need a single
		// bool here regardless of how deep the json
		// is, due to the fact that if we've written
		// a value, it's no longer the first element.
		bool firstElement = true;
		
		void checkWriteComma() @safe pure nothrow
		{
			if (!firstElement)
				output.put(",");
		}
		
	public:
		this(OutputRange outputRange) @safe pure nothrow
		{
			output = outputRange;
		}
		
		void startObject() @safe pure nothrow
		{
			import std.range : put;
			
			checkWriteComma();
			output.put("{");
			contextStack.push(WriteContext.object);
			firstElement = true;
		}
		
		void endObject() @safe pure nothrow
		{
			import std.range : put;
			
			assert(contextStack.pop() == WriteContext.object, "Tried to end an object while in a non-object context!");
			output.put("}");
			firstElement = false;
		}
		
		void startArray() @safe pure nothrow
		{
			import std.range : put;
			
			checkWriteComma();
			output.put("[");
			contextStack.push(WriteContext.array);
			firstElement = true;
		}
		
		void endArray() @safe pure nothrow
		{
			import std.range : put;
			
			assert(contextStack.pop() == WriteContext.array, "Tried to end an array while in a non-array context!");
			output.put("]");
			firstElement = false;
		}
		
		void startField(string name)() @safe pure nothrow
		{
			import std.range : put;
			
			checkWriteComma();
			output.put(`"` ~ JSONSerializationFormat.EscapeString(name) ~ `":`);
			contextStack.push(WriteContext.field);
			firstElement = true;
		}
		
		void startField(in string name) @safe pure
		{
			import std.range : put;
			
			checkWriteComma();
			output.put(`"`);
			JSONSerializationFormat.putString(output, name);
			output.put(`":`);
			contextStack.push(WriteContext.field);
			firstElement = true;
		}
		
		void endField() @safe pure nothrow
		{
			assert(contextStack.pop() == WriteContext.field, "Tried to end a field while in a non-field context!");
			firstElement = false;
		}
		
		void writeValue(T val, T)() @safe
		{
			checkWriteComma();
			toJSON!(val)(output);
			firstElement = false;
		}
		
		void writeValue(T)(in T val) @safe
		{
			checkWriteComma();
			toJSON(val, output);
			firstElement = false;
		}
		
		void writeField(string field, T val, T)() @safe
		{
			checkWriteComma();
			startField!(field);
			writeValue!(val);
			endField();
			firstElement = false;
		}
		
		void writeField(string field, T)(in T val) @safe
		{
			checkWriteComma();
			startField!(field);
			writeValue(val);
			endField();
			firstElement = false;
		}
		
		void writeField(T)(in string field, in T val) @safe
		{
			checkWriteComma();
			startField(field);
			writeValue(val);
			endField();
			firstElement = false;
		}
	}
	@safe unittest
	{
		import std.range : Appender;

		auto dst = Appender!string();
		auto wtr = new JSONWriter!(Appender!string)(dst);
	}
}

version (unittest)
{
	void main()
	{
	}
}