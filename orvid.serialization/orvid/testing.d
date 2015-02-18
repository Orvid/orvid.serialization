module orvid.testing;

/++
 + Assert than an expression evaluates to `true` at both compile-time and runtime.
 +/
@property void assertStaticAndRuntime(alias expr, string errorMessage = "")()
{
	static if (errorMessage != "")
	{
		static assert(expr, errorMessage);
		assert(expr, errorMessage);
	}
	else
	{
		static assert(expr);
		assert(expr);
	}
}