module tame.promise;

import std.traits;

alias
	ResolveFunc(T) = void delegate(Arg!T) nothrow,
	RejectFunc = void delegate(Exception) nothrow;

private template Flatten(S) {
	static if (is(Unqual!S : Promise!U, U))
		alias Flatten = U;
	else
		alias Flatten = S;
}

private template Arg(T) {
	static if (is(T == void))
		alias Arg = imported!"std.meta".AliasSeq!();
	else
		alias Arg = T;
}

immutable noop = delegate() {};
immutable thrower = delegate(Exception e) => throw e;

struct Promise(T) if (!is(Unqual!T : Exception) && !is(Unqual!T : Promise!K, K)) {
	private {
		ResolveFunc!void next;

		static if (!is(T == void))
			T value;
		bool hasValue;
	}
	Exception exception;

	@property @safe @nogc nothrow {
		bool isPending() const {
			return !hasValue;
		}

		bool isFulfilled() const {
			return !isPending && exception is null;
		}

		bool isRejected() const {
			return !isPending && exception !is null;
		}
	}

	this(void delegate(ResolveFunc!T resolve) nothrow executer) nothrow
	in (executer !is null) {
		next = noop;
		executer((Arg!T) {
			if (isPending) {
				static if (!is(T == void))
					value = __traits(parameters)[0];
				hasValue = true;
				next();
			}
		});
	}

	this(void delegate(ResolveFunc!T resolve, RejectFunc reject) executer) nothrow
	in (executer !is null) {
		this((res) nothrow{
			void rej(Exception ex) {
				exception = ex;
				hasValue = true;
			}

			try
				executer(res, &rej);
			catch (Exception e)
				rej(e);
		});
	}

	static if (!is(T == void))
		Promise!(Flatten!S) then(S, U)(
			S delegate(T) onFulfilled,
			U delegate(Exception) onRejected = cast(S delegate(Exception))thrower
		) if (is(Flatten!S == Flatten!U))
		in (onFulfilled !is null)
		in (onRejected !is null) {
			return then(() => onFulfilled(value), onRejected);
		}

	Promise!(Flatten!S) then(S, U)(
		S delegate() onFulfilled,
		U delegate(Exception) onRejected = cast(S delegate(Exception))thrower
	) if (is(Flatten!S == Flatten!U))
	in (onFulfilled !is null)
	in (onRejected !is null) {
		typeof(return) child;
		child.next = noop;
		next = () {
			static if (is(S : Promise!K, K)) {
				enum resolveFunc(F) = (Arg!T) {
					static if (!is(F == void))
						child.value = __traits(parameters)[0];
					child.hasValue = true;
					child.next();
				};

				auto rejectFunc = (Exception e) {
					child.exception = e;
					child.hasValue = true;
					child.next();
				};
			}

			try {
				if (hasValue && exception is null) { // fulfill
					static if (is(S : Promise!K, K))
						onFulfilled().then(resolveFunc!(Flatten!S), rejectFunc);
					else {
						static if (is(Flatten!S == void))
							onFulfilled();
						else
							child.value = onFulfilled();
						child.hasValue = true;
						child.next();
					}
				} else { // reject
					static if (is(U : Promise!K, K))
						onRejected(exception).then(resolveFunc!(Flatten!U), rejectFunc);
					else {
						static if (is(Flatten!U == void))
							onRejected(exception);
						else
							child.value = onRejected(exception);
						child.hasValue = true;
						child.next();
					}
				}
			} catch (Exception e) {
				child.exception = e;
				child.next();
			}
		};
		if (!isPending)
			next();
		return child;
	}

	Promise!T fail(T delegate(Exception) reject = cast(T delegate(Exception))thrower)nothrow {
		return then({
			static if (!is(T == void))
				return value;
		}, reject);
	}

static @safe @nogc pure nothrow:
	Promise!T resolve(Arg!T) {
		Promise!T p;
		static if (!is(T == void))
			p.value = __traits(parameters)[0];
		p.hasValue = true;
		return p;
	}

	Promise!T reject(Exception ex)
	in (ex !is null) {
		Promise!T p;
		p.exception = ex;
		p.hasValue = true;
		return p;
	}
}

unittest {
	import std.stdio;

	writeln("start test");
	Promise!int((resolve, reject) { resolve(10); }).then((int x) {
		x.writeln;
		return x + 3; //13
	}).then((a) {
		return Promise!int((res, rej) { //Return promise
			a.writeln;
			res(a + 3);
		});
	}).then((a) { a.writeln; });

	//Error handling
	Promise!string((resolve, reject) { throw new Exception("test"); })
		.fail((e) { return e.msg; })
		.then((a) { a.writeln; });
}

import core.thread : Fiber;
import std.concurrency : Generator, yield;

auto async(T)(T delegate() dg)
if (!is(Unqual!T : Exception) && !is(Unqual!T : Promise!K, K))
in (dg !is null) {
	return Promise!T((res, rej) {
		static if (is(T == void)) {
			alias value = Arg!T;
			alias p = dg;
		} else {
			T value;
			alias p = { value = dg(); };
		}

		auto gen = new Generator!(Promise!T)(p);

		void inner() {
			if (gen.empty)
				res(value);
			else
				gen.front.then({ gen.popFront; inner(); }, rej);
		}

		inner();
	});
}

T await(T)(Promise!T promise)
in (cast(Generator!(Promise!T))Fiber.getThis()) {
	yield(promise);

	if (promise.isFulfilled) {
		static if (!is(T == void))
			return promise.value;
	} else {
		if (promise.isRejected)
			throw promise.exception;
		assert(0);
	}
}

unittest {
	import core.thread,
	core.time,
	std.stdio;

	auto func = () {
		auto t = Promise!string((res) {
			Thread.sleep(dur!"msecs"(50));
			res("50 ms");
		}).then((a) { a.writeln; });
	};
	new Thread(func).start();
	async(noop);

	"0 ms".writeln;
}
