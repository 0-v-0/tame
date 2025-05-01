module tame.net.addr;

import core.stdc.string;
import std.string : fromStringz;
import tame.format : globalSink, text;
import tame.net.error;
import tame.string : indexOf;

version (iOS)
	version = iOSDerived;
else version (TVOS)
	version = iOSDerived;
else version (WatchOS)
	version = iOSDerived;

version (Windows) {
	import core.sys.windows.winbase,
	core.sys.windows.winsock2;
} else version (Posix) {
	import core.sys.posix.netinet.in_,
	core.sys.posix.arpa.inet,
	core.sys.posix.netdb,
	core.sys.posix.sys.un : sockaddr_un;
}

@safe:

// dfmt off

/// The communication domain used to resolve an address.
enum AddrFamily: ushort {
	unspecified =	AF_UNSPEC,	// Unspecified address family
	UNIX =			AF_UNIX,	/// Local communication (Unix socket)
	IPv4 =			AF_INET,	/// Internet Protocol version 4
	IPv6 =			AF_INET6,	/// Internet Protocol version 6
}

/// Communication semantics
enum SocketType {
	unknown =	 -1,			/// unspecified socket type, mostly as resolve hint
	stream =	SOCK_STREAM,	/// Sequenced, reliable, two-way communication-based byte streams
	dgram =		SOCK_DGRAM,		/// Connectionless, unreliable datagrams with a fixed maximum length; data may be lost or arrive out of order
	raw =		SOCK_RAW,		/// Raw protocol access
	rdm =		SOCK_RDM,		/// Reliably-delivered message datagrams
	seqpacket =	SOCK_SEQPACKET,	/// Sequenced, reliable, two-way connection-based datagrams with a fixed maximum length
}

/// Protocol
enum Protocol {
	IP =    IPPROTO_IP,		/// Internet Protocol version 4
	ICMP =  IPPROTO_ICMP,	/// Internet Control Message Protocol
	IGMP =  IPPROTO_IGMP,	/// Internet Group Management Protocol
	GGP =   IPPROTO_GGP,	/// Gateway to Gateway Protocol
	TCP =   IPPROTO_TCP,	/// Transmission Control Protocol
	PUP =   IPPROTO_PUP,	/// PARC Universal Packet Protocol
	UDP =   IPPROTO_UDP,	/// User Datagram Protocol
	IDP =   IPPROTO_IDP,	/// Xerox NS protocol
	RAW =   IPPROTO_RAW,	/// Raw IP packets
	IPV6 =  IPPROTO_IPV6,	/// Internet Protocol version 6
}

// dfmt on

/// Holds information about a socket _address retrieved by `getAddrInfo`.
struct AddrInfo {
	AddrFamily family; /// Address _family
	SocketType type; /// Socket _type
	Protocol protocol; /// Protocol
	Address address; /// Socket _address
	string canonicalName; /// Canonical name, when `AddrInfoFlags.canonName` is used.
}

/++
A subset of flags supported on all platforms with getaddrinfo.
Specifies option flags for `getAddrInfo`.
+/
enum AddrInfoFlags {
	/// The resulting addresses will be used in a call to `Socket.bind`.
	passive = AI_PASSIVE,

	/// The canonical name is returned in `canonicalName` member in the first `AddrInfo`.
	canonName = AI_CANONNAME,

	/++
	The `node` parameter passed to `getAddrInfo` must be a numeric string.
	This will suppress any potentially lengthy network host address lookups.
	+/
	numericHost = AI_NUMERICHOST,
}

/++
Provides protocol-independent translation from host names to socket
addresses. If advanced functionality is not required, consider using
`getAddress` for compatibility with older systems.

Returns: Array with one `AddrInfo` per socket address.

Throws: `SocketParamException` on invalid parameters

Params:
	node     = string containing host name or numeric address
	options  = optional additional parameters, identified by type:
				`string` - service name or port number
				`AddrInfoFlags` - option flags
				`AddrFamily` - address family to filter by
				`SocketType` - socket type to filter by
				`Protocol` - protocol to filter by

Example:
---
// Roundtrip DNS resolution
auto results = getAddrInfo("www.digitalmars.com");
assert(!results.empty);

// Canonical name
results = getAddrInfo("www.digitalmars.com", AddrInfoFlags.canonName);
assert(!results.empty && results.front.canonicalName == "digitalmars.com");

// IPv6 resolution
results = getAddrInfo("ipv6.google.com");
assert(results.front.family == AddrFamily.IPv6);

// Multihomed resolution
results = getAddrInfo("google.com");
uint length;
foreach (_; results)
	++length;
assert(length > 1);

// Parsing IPv4
results = getAddrInfo("127.0.0.1", AddrInfoFlags.numericHost);
assert(!results.empty && results.front.family == AddrFamily.IPv4);

// Parsing IPv6
results = getAddrInfo("::1", AddrInfoFlags.numericHost);
assert(!results.empty && results.front.family == AddrFamily.IPv6);
---
+/
auto getAddrInfo(A...)(in char[] node, scope A options) {
	const(char)[] service = null;
	addrinfo hints;
	hints.ai_family = AF_UNSPEC;

	foreach (i, opt; options) {
		alias T = typeof(opt);
		static if (is(T : const(char)[]))
			service = options[i];
		else static if (is(T == AddrInfoFlags))
			hints.ai_flags |= opt;
		else static if (is(T == AddrFamily))
			hints.ai_family = opt;
		else static if (is(T == SocketType))
			hints.ai_socktype = opt;
		else static if (is(T == Protocol))
			hints.ai_protocol = opt;
		else
			static assert(0, "Unknown getAddrInfo option type: " ~ T.stringof);
	}

	if (node.length > NI_MAXHOST - 1)
		throw new SocketParamException("Host name too long");
	if (service.length > NI_MAXSERV - 1)
		throw new SocketParamException("Service name too long");
	return (() @trusted => getAddressInfoImpl(node, service, &hints))();
}

@system unittest {
	struct Oops {
		const(char[]) unsafeOp() {
			*cast(int*)0xcafebabe = 0xdeadbeef;
			return null;
		}

		alias unsafeOp this;
	}

	assert(!__traits(compiles, () { getAddrInfo("", Oops.init); }), "getAddrInfo breaks @safe");
}

struct AddrInfoList {
	private {
		addrinfo* head;
		union {
			addrinfo* ai;
			int err;
		}
	}

nothrow @nogc:
	this(addrinfo* info, int errCode = 0) @trusted {
		if (errCode) {
			head = null;
			err = errCode;
			return;
		}
		head = info;
		ai = info;
	}

	@disable this(this);

	~this() @trusted
		=> freeaddrinfo(head);

pure:
	@property const {
		bool empty() @trusted => !head || !ai;

		int errCode() @trusted => head ? 0 : err;

		AddrInfo front() @trusted
		in (head && ai) =>
			AddrInfo(
				cast(AddrFamily)ai.ai_family,
				cast(SocketType)ai.ai_socktype,
				cast(Protocol)ai.ai_protocol,
				Address(cast(sockaddr*)ai.ai_addr, cast(socklen_t)ai.ai_addrlen),
				cast(string)fromStringz(ai.ai_canonname));
	}

	void popFront() @trusted
	in (head && ai) {
		ai = ai.ai_next;
	}
}

private auto getAddressInfoImpl(in char[] node, in char[] service, addrinfo* hints) @system {
	addrinfo* res = void;
	char[NI_MAXHOST] nbuf = void;
	if (node.length)
		(cast(char*)memcpy(nbuf.ptr, node.ptr, node.length))[node.length] = 0;
	char[NI_MAXSERV] sbuf = void;
	if (service.length)
		(cast(char*)memcpy(sbuf.ptr, service.ptr, service.length))[service.length] = 0;
	const err = getaddrinfo(node.length ? nbuf.ptr : null,
		service.length ? sbuf.ptr : null, hints, &res);
	enforce(err == 0, new SocketOSException("getaddrinfo error", err));
	return AddrInfoList(res, err);
}

unittest {
	softUnittest({
		// Roundtrip DNS resolution
		auto results = getAddrInfo("www.digitalmars.com");
		assert(!results.empty);

		// Canonical name
		results = getAddrInfo("www.digitalmars.com", AddrInfoFlags.canonName);
		assert(!results.empty && results.front.canonicalName == "digitalmars.com");

		// IPv6 resolution
		//results = getAddrInfo("ipv6.google.com");
		//assert(results.front.family == AddrFamily.IPv6);

		// Multihomed resolution
		//results = getAddrInfo("google.com");
		//uint length;
		//foreach (_; results)
		//	++length;
		//assert(length > 1);

		// Parsing IPv4
		results = getAddrInfo("127.0.0.1", AddrInfoFlags.numericHost);
		assert(!results.empty && results.front.family == AddrFamily.IPv4);

		// Parsing IPv6
		results = getAddrInfo("::1", AddrInfoFlags.numericHost);
		assert(!results.empty && results.front.family == AddrFamily.IPv6);
	});

	auto results = getAddrInfo(null, "1234", AddrInfoFlags.passive,
		SocketType.stream, Protocol.TCP, AddrFamily.IPv4);
	assert(!results.empty && results.front.address.toString() == "0.0.0.0:1234");
}

struct AddressList {
	AddrInfoList infos;

pure nothrow @nogc:
	@property bool empty() const => infos.empty;
	@property Address front() const => infos.front.address;
	void popFront() {
		infos.popFront();
	}
}

/++
Provides _protocol-independent translation from host names to socket
addresses. Uses `getAddrInfo` if the current system supports it,
and `InternetHost` otherwise.

Returns: Array with one `Address` instance per socket address.

Throws: `SocketOSException` on failure.

Example:
---
writeln("Resolving www.digitalmars.com:");
try
{
    auto addresses = getAddress("www.digitalmars.com");
    foreach (address; addresses)
        writefln("  IP: %s", address.toAddrString());
}
catch (SocketException e)
    writefln("  Lookup failed: %s", e.msg);
---
+/
auto getAddress(in char[] hostname, in char[] service = null) {
	return AddressList(getAddrInfo(hostname, service));
}

unittest {
	softUnittest({
		auto addresses = getAddress("63.105.9.61");
		assert(!addresses.empty && addresses.front.toAddrString() == "63.105.9.61");
	});
}

/++
Provides _protocol-independent parsing of network addresses. Does not
attempt name resolution. Uses `getAddrInfo` with
`AddrInfoFlags.numericHost` if the current system supports it, and
`IPv4Addr` otherwise.

Returns: An `Address` instance representing specified address.

Throws: `SocketException` on failure.

Example:
---
writeln("Enter IP address:");
string ip = readln().chomp();
try {
	Address address = parseAddress(ip);
	writefln("Looking up reverse of %s:",
		address.toAddrString());
	try {
		string reverse = address.toHostName();
		if (reverse)
			writefln("  Reverse name: %s", reverse);
		else
			writeln("  Reverse hostname not found.");
	}
	catch (SocketException e)
		writefln("  Lookup error: %s", e.msg);
} catch (SocketException e) {
	writefln("  %s is not a valid IP address: %s",
		ip, e.msg);
}
---
+/
auto parseAddress(in char[] host, in char[] service = null) {
	auto info = getAddrInfo(host, service, AddrInfoFlags.numericHost);
	return info.front.address;
}

unittest {
	softUnittest(() @safe {
		const address = parseAddress("63.105.9.61");
		assert(address.toAddrString() == "63.105.9.61");

		try {
			address.toHostName();
			assert(0, "Reverse lookup should fail");
		} catch (SocketException) {
		}

		try {
			parseAddress("Invalid Address");
			assert(0, "Invalid address should fail");
		} catch (SocketException) {
		}
	});
}

/// Class for exceptions thrown from an `Address`.
class AddressException : SocketOSException {
	mixin socketOSExceptionCtors;
}

/// represent a socket address
struct Address {
	sockaddr* name;
	socklen_t nameLen;

	/++
	Attempts to retrieve the host address as a human-readable string.

	Throws: `AddressException` on failure
	+/
	string toAddrString() const => toHostString(true);

	/++
	Attempts to retrieve the host name as a fully qualified domain name.

	Returns: The FQDN corresponding to this `Address`, or `null` if
	the host name did not resolve.

	Throws: `AddressException` on error
	+/
	string toHostName() const => toHostString(false);

	/++
	Attempts to retrieve the numeric port number as a string.

	Throws: `AddressException` on failure
	+/
	string toPortString() const => toServiceString(true);

	/++
	Attempts to retrieve the service name as a string.

	Throws: `AddressException` on failure
	+/
	string toServiceName() const => toServiceString(false);

	// Common code for toAddrString and toHostName
	private string toHostString(bool numeric) @trusted const {
		char[NI_MAXHOST] buf = void;
		const ret = getnameinfo(
			name, nameLen,
			buf.ptr, cast(uint)buf.length,
			null, 0,
			numeric ? NI_NUMERICHOST : NI_NAMEREQD);

		if (!numeric) {
			if (ret == EAI_NONAME)
				return null;
			version (Windows)
				if (ret == WSANO_DATA)
					return null;
		}

		enforce(ret == 0, new AddressException("Could not get " ~
				(numeric ? "host address" : "host name")));
		return text(buf.ptr);
	}

	// Common code for toPortString and toServiceName
	private string toServiceString(bool numeric) @trusted const {
		char[NI_MAXSERV] buf = void;
		enforce(getnameinfo(
				name, nameLen,
				null, 0,
				buf.ptr, cast(uint)buf.length,
				numeric ? NI_NUMERICSERV : NI_NAMEREQD
		) == 0, new AddressException("Could not get " ~
				(numeric ? "port number" : "service name")));
		return text(buf.ptr);
	}

	void toString(R)(ref R r) const {
		try {
			const host = toAddrString();
			if (host.indexOf(':') >= 0) {
				r ~= '[';
				r ~= host;
				r ~= "]:";
			} else {
				r ~= host;
				r ~= ':';
			}
			r ~= toPortString();
		} catch (Exception) {
		}
	}

	string toString() const nothrow {
		import std.array : appender;

		auto r = appender!string;
		toString(r);
		return r[];
	}

pure nothrow @nogc:
	this(sockaddr* sa, socklen_t len)
	in (sa) {
		name = sa;
		nameLen = len;
	}

	/// Family of this address.
	@property auto family() const
		=> name ? cast(AddrFamily)name.sa_family : AddrFamily.unspecified;

	alias addressFamily = family;
}

struct IPv4Addr {
	alias address this;

	private sockaddr_in sin;

	enum any = INADDR_ANY; /// Any IPv4 host address.
	enum loopback = INADDR_LOOPBACK; /// The IPv4 loopback address.
	enum none = INADDR_NONE; /// An invalid IPv4 host address.
	enum ushort anyPort = 0; /// Any IPv4 port number.

	/++
	Construct a new `IPv4Addr`.
	Params:
		addr = an IPv4 address string in the dotted-decimal form a.b.c.d.
		port = port number, may be `anyPort`.
	+/
	this(in char[] addr, ushort port) {
		sin.sin_family = AddrFamily.IPv4;
		sin.sin_addr.s_addr = htonl(parse(addr));
		sin.sin_port = htons(port);
	}

nothrow @nogc:

	/// Returns the IPv4 _port number (in host byte order).
	@property pure {
		ushort port() const => ntohs(sin.sin_port);

		/// Returns the IPv4 address number (in host byte order).
		uint addr() const => ntohl(sin.sin_addr.s_addr);

		Address address() const @trusted =>
			Address(cast(sockaddr*)&sin, cast(socklen_t)sin.sizeof);
	}

	/++
	Construct a new `IPv4Addr`.
	Params:
		addr = (optional) an IPv4 address in host byte order, may be `ADDR_ANY`.
		port = port number, may be `anyPort`.
	+/
	this(uint addr, ushort port) pure {
		sin.sin_family = AddrFamily.IPv4;
		sin.sin_addr.s_addr = htonl(addr);
		sin.sin_port = htons(port);
	}

	/// ditto
	this(ushort port) pure {
		sin.sin_family = AddrFamily.IPv4;
		sin.sin_addr.s_addr = any;
		sin.sin_port = htons(port);
	}

	/++
	Construct a new `IPv4Addr`.
	Params:
		addr = A sockaddr_in as obtained from lower-level API calls such as getifaddrs.
	+/
	this(in sockaddr_in addr) pure
	in (addr.sin_family == AddrFamily.IPv4, "Socket address is not of IPv4 family.") {
		sin = addr;
	}

	/++
	Parse an IPv4 address string in the dotted-decimal form $(I a.b.c.d)
	and return the number.
	Returns: If the string is not a legitimate IPv4 address,
	`ADDR_NONE` is returned.
	+/
	static uint parse(in char[] addr) @trusted {
		if (addr.length > 15)
			return none;

		char[16] buf = void;
		strncpy(buf.ptr, addr.ptr, addr.length)[addr.length] = 0;
		return ntohl(inet_addr(buf.ptr));
	}

	/++
	Convert an IPv4 address number in host byte order to a human readable
	string representing the IPv4 address in dotted-decimal form.
	+/
	static string addrToString(uint addr) @trusted {
		in_addr sin_addr;
		sin_addr.s_addr = htonl(addr);
		return cast(string)fromStringz(inet_ntoa(sin_addr));
	}
}

unittest {
	softUnittest({
		const ia = IPv4Addr("63.105.9.61", 80);
		assert(ia.toString() == "63.105.9.61:80");
	});

	softUnittest({
		// test construction from a sockaddr_in
		sockaddr_in sin;

		sin.sin_addr.s_addr = htonl(0x7F_00_00_01); // 127.0.0.1
		sin.sin_family = AddrFamily.IPv4;
		sin.sin_port = htons(80);

		const ia = IPv4Addr(sin);
		assert(ia.toString() == "127.0.0.1:80");
	});

	if (runSlowTests)
		softUnittest({
			// test failing reverse lookup
			const ia = IPv4Addr("255.255.255.255", 80);
			assert(ia.toHostName() is null);
		});
}

struct IPv6Addr {
	alias address this;

	private sockaddr_in6 sin6;

	enum ushort anyPort = 0; /// Any IPv6 port number.

	/++
	Construct a new `IPv6Addr`.
	Params:
		addr = an IPv6 address string in the colon-separated form a:b:c:d:e:f:g:h.
		port = port number, may be `anyPort`.
	+/
	this(in char[] addr, ushort port = anyPort) {
		this(parse(addr), port);
	}

	/++
	Parse an IPv6 host address string as described in RFC 2373, and return the
	address.
	+/
	static ubyte[16] parse(in char[] addr) @trusted {
		// Although we could use inet_pton here, it's only available on Windows
		// versions starting with Vista, so use getAddrInfo with numericHost
		// instead.
		auto results = getAddrInfo(addr, AddrInfoFlags.numericHost);
		if (!results.empty && results.front.family == AddrFamily.IPv6)
			return (cast(sockaddr_in6*)results.front.address.name).sin6_addr.s6_addr;
		return any;
	}

pure nothrow @nogc:

	/++
	Construct a new `IPv6Addr`.
	Params:
		addr = A sockaddr_in6 as obtained from lower-level API calls such as getifaddrs.
	+/
	this(in sockaddr_in6 addr)
	in (addr.sin6_family == AddrFamily.IPv6, "Socket address is not of IPv6 family.") {
		sin6 = addr;
	}

	/++
	Construct a new `IPv6Addr`.
	Params:
		addr = (optional) an IPv6 host address in host byte order, or `ADDR_ANY`.
		port = port number, may be `anyPort`.
	+/
	this(in ubyte[16] addr, ushort port) {
		sin6.sin6_family = AddrFamily.IPv6;
		sin6.sin6_port = htons(port);
		sin6.sin6_addr.s6_addr = addr;
	}

	/// ditto
	this(ushort port) {
		this(any, port);
	}

@property:

	/// Any IPv6 host address.
	static ref const(ubyte)[16] any() {
		static if (is(typeof(IN6ADDR_ANY))) {
			static immutable addr = IN6ADDR_ANY.s6_addr;
			return addr;
		} else static if (is(typeof(in6addr_any)))
			return in6addr_any.s6_addr;
		else
			static assert(0);
	}

	/// The IPv6 loopback address.
	static ref const(ubyte)[16] loopback() {
		static if (is(typeof(IN6ADDR_LOOPBACK))) {
			static immutable addr = IN6ADDR_LOOPBACK.s6_addr;
			return addr;
		} else static if (is(typeof(in6addr_loopback)))
			return in6addr_loopback.s6_addr;
		else
			static assert(0);
	}
	/// Returns the IPv6 port number.
	ushort port() const => ntohs(sin6.sin6_port);

	/// Returns the IPv6 address.
	ubyte[16] addr() const => sin6.sin6_addr.s6_addr;

	Address address() const @trusted
		=> Address(cast(sockaddr*)&sin6, cast(socklen_t)sin6.sizeof);
}

unittest {
	softUnittest({
		const ia = IPv6Addr("::1", 80);
		assert(ia.toString() == "[::1]:80");
	});

	softUnittest({
		const ia = IPv6Addr(IPv6Addr.loopback, 80);
		assert(ia.toString() == "[::1]:80");
	});
}

static if (is(sockaddr_un)) {
	struct UnixAddr {
		alias address this;

		private sockaddr_un sun = sockaddr_un(AddrFamily.UNIX, '?');
		socklen_t nameLen = sun.sizeof;

@safe pure:
		/++
		Construct a new `UnixAddr`.
		Params:
			path = a string containing the path to the Unix domain socket.
		+/
		this(in char[] path) @trusted pure {
			enforce(path.length <= sun.sun_path.sizeof, new SocketParamException(
					"Path too long"));
			sun.sun_family = AddrFamily.UNIX;
			strncpy(cast(char*)sun.sun_path.ptr, path.ptr, sun.sun_path.length);
			auto len = sockaddr_un.init.sun_path.offsetof + path.length;
			// Pathname socket address must be terminated with '\0'
			// which must be included in the address length.
			if (sun.sun_path[0]) {
				sun.sun_path[path.length] = 0;
				++len;
			}
			nameLen = cast(socklen_t)len;
		}

	nothrow @nogc:
		/++
		Construct a new `UnixAddr`.
		Params:
		  addr = a sockaddr_un as obtained from lower-level API calls such as getifaddrs.
		+/
		this(in sockaddr_un addr)
		in (addr.sun_family == AddrFamily.UNIX, "Socket address is not of UNIX family.") {
			sun = addr;
		}

	@property:
		/// Returns the path to the Unix domain socket.
		string path() const @trusted
			=> cast(string)fromStringz(cast(const char*)sun.sun_path.ptr);

		Address address() const @trusted
			=> Address(cast(sockaddr*)&sun, nameLen);
	}

	unittest {
		import core.stdc.stdio : remove;
		import std.internal.cstring;
		import tame.net.socket;

		version (iOSDerived) {
			// Slightly different version of `std.file.deleteme` to reduce the path
			// length on iOS derived platforms. Due to the sandbox, the length
			// of paths can quickly become too long.
			static string deleteme() {
				import std.file : tempDir;
				import std.process : thisProcessID;
				import tame.format : text;

				return text(tempDir, thisProcessID);
			}
		} else
			import std.file : deleteme;

		enum ubyte[4] data = [1, 2, 3, 4];
		Socket[2] pair;

		const basePath = deleteme;
		auto names = [basePath ~ "-socket"];
		version (linux)
			names ~= "\0" ~ basePath ~ "-abstract\0unix\0socket";

		foreach (name; names) {
			auto addr = UnixAddr(name);

			auto listener = Socket(AddrFamily.UNIX, SocketType.stream);
			scope (exit)
				listener.close();
			listener.bind(addr);
			scope (exit)
				() @trusted {
				if (name[0])
					remove(name.tempCString());
			}();
			//assert(listener.localAddr.toString() == name);

			listener.listen(1);

			pair[0] = Socket(AddrFamily.UNIX, SocketType.stream);
			scope (exit)
				listener.close();

			pair[0].connect(addr);
			scope (exit)
				pair[0].close();

			pair[1] = listener.accept();
			scope (exit)
				pair[1].close();

			pair[0].send(data);

			ubyte[data.length] buf;
			pair[1].receive(buf);
			assert(buf == data);

			// getpeername is free to return an empty name for a unix
			// domain socket pair or unbound socket. Let's confirm it
			// returns successfully and doesn't throw anything.
			// See https://issues.dlang.org/show_bug.cgi?id=20544
			pair[1].remoteAddr.toString();
		}
	}
}

struct UnknownAddr {
	alias address this;

	private sockaddr sa;

pure nothrow @nogc:
	/++
	Construct a new `UnknownAddr`.
	Params:
	addr = a sockaddr as obtained from lower-level API calls such as getifaddrs.
	+/
	this(sockaddr addr) {
		sa = addr;
	}

@property:
	/// Returns the address.
	Address address() const @trusted
		=> Address(cast(sockaddr*)&sa, cast(socklen_t)sa.sizeof);
}
