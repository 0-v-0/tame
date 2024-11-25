module tame.fixed.stack;

@safe pure nothrow @nogc:

/// Fixed-size stack.
struct Stack(T, uint N = 16) {
	enum capacity = N;

	void push(T value)
	in (len < N, "Stack is full") {
		data[len++] = value;
	}

	T pop()
	in (len, "Stack is empty") {
		return data[--len];
	}

	@property T top()
	in (len, "Stack is empty") {
		return data[len - 1];
	}

	void clear() {
		len = 0;
	}

	@property bool empty() const => !len;
	@property size_t length() const => len;
	alias front = top;

private:
	T[N] data;
	uint len;
}

unittest {
	Stack!int stack;
	assert(stack.empty);
	stack.push(1);
	assert(!stack.empty);
	stack.push(2);
	assert(stack.length == 2);
	assert(stack.pop == 2);
	assert(stack.pop == 1);
	assert(stack.empty);
	stack.push(3);
	assert(stack.top == 3);
	stack.clear();
	assert(stack.empty);
}
