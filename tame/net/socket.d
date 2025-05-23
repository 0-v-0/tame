/++
	Socket primitives.
+/
module tame.net.socket;

// NOTE: When working on this module, be sure to run tests with -debug=std_socket
// E.g.: dmd -version=StdUnittest -debug=std_socket -unittest -main -run socket
// This will enable some tests which are too slow or flaky to run as part of CI.

import core.stdc.stdlib;
import core.time;
import tame.format : text;
public import tame.net.addr;
import tame.net.error;
import tame.unsafe.ptrop;
import tame.util;

@safe:

version (Windows) {
	pragma(lib, "ws2_32.lib");
	pragma(lib, "wsock32.lib");

	import core.sys.windows.winbase,
	core.sys.windows.winsock2;

	enum socket_t : SOCKET {
		_init
	}

	shared static this() @system {
		WSADATA wd;

		// Winsock will still load if an older version is present.
		// The version is just a request.
		if (const val = WSAStartup(0x2020, &wd)) // Request Winsock 2.2 for IPv6.
			throw new SocketOSException("Unable to initialize socket library", val);
	}

	shared static ~this() @system nothrow @nogc {
		WSACleanup();
	}

private:
	enum SO_REUSEPORT = 0;
	alias _close = .closesocket;

	// Windows uses int instead of size_t for length arguments.
	// Luckily, the send/recv functions make no guarantee that
	// all the data is sent, so we use that to send at most
	// int.max bytes.
	int capToInt(size_t size) nothrow @nogc pure
		=> size > size_t(int.max) ? int.max : cast(int)size;
} else version (Posix) {
	version (linux) {
		enum {
			TCP_KEEPIDLE = cast(SocketOption)4,
			TCP_KEEPINTVL = cast(SocketOption)5
		}
	}

	import core.stdc.errno;
	import core.sys.posix.fcntl,
	core.sys.posix.netinet.in_,
	core.sys.posix.netinet.tcp,
	core.sys.posix.sys.socket,
	core.sys.posix.sys.time,
	core.sys.posix.unistd;

	enum socket_t : int {
		_init = -1
	}

	package enum SOCKET_ERROR = -1;

private:
	alias _close = .close;

	enum : int {
		SD_RECEIVE = SHUT_RD,
		SD_SEND = SHUT_WR,
		SD_BOTH = SHUT_RDWR,
		SO_EXCLUSIVEADDRUSE = 0,
	}

	size_t capToInt(size_t size) nothrow @nogc pure => size;
} else
	static assert(0, "No socket support for this platform yet.");

/// How a socket is shutdown:
enum SocketShutdown {
	receive = SD_RECEIVE, /// socket receives are disallowed
	send = SD_SEND, /// socket sends are disallowed
	both = SD_BOTH, /// both RECEIVE and SEND
}

// dfmt off

/// Socket flags that may be OR'ed together:
enum SocketFlags: int {
	none =		0,				/// no flags specified
	OOB =		MSG_OOB,		/// out-of-band stream data
	PEEK =		MSG_PEEK,		/// peek at incoming data without removing it from the queue, only for receiving
	dontRoute =	MSG_DONTROUTE,	/// data should not be subject to routing; this flag may be ignored. Only for sending
}

/// The level at which a socket option is defined:
enum SocketOptionLevel: int {
	SOCKET =	SOL_SOCKET,		/// Socket level
	IP =		Protocol.IP,	/// Internet Protocol version 4 level
	ICMP =		Protocol.ICMP,	/// Internet Control Message Protocol level
	IGMP =		Protocol.IGMP,	/// Internet Group Management Protocol level
	GGP =		Protocol.GGP,	/// Gateway to Gateway Protocol level
	TCP =		Protocol.TCP,	/// Transmission Control Protocol level
	PUP =		Protocol.PUP,	/// PARC Universal Packet Protocol level
	UDP =		Protocol.UDP,	/// User Datagram Protocol level
	IDP =		Protocol.IDP,	/// Xerox NS protocol level
	RAW =		Protocol.RAW,	/// Raw IP packet level
	IPV6 =		Protocol.IPV6,	/// Internet Protocol version 6 level
}

/// Specifies a socket option:
enum SocketOption: int {
	DEBUG =			SO_DEBUG,		/// Record debugging information
	broadcast =		SO_BROADCAST,	/// Allow transmission of broadcast messages
	reuseAddr =		SO_REUSEADDR,	/// Allow local reuse of address
	linger =		SO_LINGER,		/// Linger on close if unsent data is present
	oobinline =		SO_OOBINLINE,	/// Receive out-of-band data in band
	sndbuf =		SO_SNDBUF,		/// Send buffer size
	rcvbuf =		SO_RCVBUF,		/// Receive buffer size
	dontRoute =		SO_DONTROUTE,	/// Do not route
	sndtimeo =		SO_SNDTIMEO,	/// Send timeout
	rcvtimeo =		SO_RCVTIMEO,	/// Receive timeout
	error =			SO_ERROR,		/// Retrieve and clear error status
	keepAlive =		SO_KEEPALIVE,	/// Enable keep-alive packets
	acceptConn =	SO_ACCEPTCONN,	/// Listen
	rcvlowat =		SO_RCVLOWAT,	/// Minimum number of input bytes to process
	sndlowat =		SO_SNDLOWAT,	/// Minimum number of output bytes to process
	type =			SO_TYPE,		/// Socket type

	reusePort =		SO_REUSEPORT,	/// Allow local reuse of port
	exclusiveAddr =	SO_EXCLUSIVEADDRUSE,/// Allow exclusive use of address

	// SocketOptionLevel.TCP:
	tcpNoDelay =		.TCP_NODELAY,	/// Disable the Nagle algorithm for send coalescing

	// SocketOptionLevel.IPV6:
	IPv6UnicastHops =	IPV6_UNICAST_HOPS,	/// IP unicast hop limit
	IPv6MulticastIf =	IPV6_MULTICAST_IF,	/// IP multicast interface
	IPv6MulticastLoop =	IPV6_MULTICAST_LOOP,/// IP multicast loopback
	IPv6MulticastHops =	IPV6_MULTICAST_HOPS,/// IP multicast hops
	IPv6JoinGroup =		IPV6_JOIN_GROUP,	/// Add an IP group membership
	IPv6LeaveGroup =	IPV6_LEAVE_GROUP,	/// Drop an IP group membership
	IPv6V6Only =		IPV6_V6ONLY,		/// Treat wildcard bind as AF_INET6-only
}

// dfmt on

/// _Linger information for use with SocketOption.LINGER.
struct Linger {
	linger clinger;

	private alias l_onoff_t = typeof(linger.l_onoff),
	l_linger_t = typeof(linger.l_linger);

pure nothrow @nogc @property:
	/// Nonzero for _on.
	ref inout(l_onoff_t) on() inout return  => clinger.l_onoff;

	/// Linger _time.
	ref inout(l_linger_t) time() inout return  => clinger.l_linger;
}

/++
A network communication endpoint using the Berkeley sockets interface.
+/
struct Socket {
private:
	mixin CompactPtr!(AddrFamily, "_family");
	socket_t sock;

	enum BIOFlag = cast(AddrFamily)0x8000;

	// The WinSock timeouts seem to be effectively skewed by a constant
	// offset of about half a second (value in milliseconds). This has
	// been confirmed on updated (as of Jun 2011) Windows XP, Windows 7
	// and Windows Server 2008 R2 boxes. The unittest below tests this
	// behavior.
	enum WINSOCK_TIMEOUT_SKEW = 500;

	@safe unittest {
		if (runSlowTests)
			softUnittest({
				import std.datetime.stopwatch : StopWatch;
				import std.typecons : Yes;

				enum ms = 1000;
				auto pair = socketPair();
				auto testSock = pair[0];
				testSock.setOption(SocketOptionLevel.SOCKET,
					SocketOption.rcvtimeo, ms.msecs);

				auto sw = StopWatch(Yes.autoStart);
				ubyte[1] buf;
				testSock.receive(buf);
				sw.stop();

				Duration readBack = void;
				testSock.getOption(SocketOptionLevel.SOCKET, SocketOption.rcvtimeo, readBack);

				assert(readBack.total!"msecs" == ms);
				assert(sw.peek().total!"msecs" > ms - 100 && sw.peek()
					.total!"msecs" < ms + 100);
			});
	}

	void setSock(socket_t handle)
	in (handle != socket_t.init) {
		sock = handle;

		// Set the option to disable SIGPIPE on send() if the platform
		// has it (e.g. on OS X).
		static if (is(typeof(SO_NOSIGPIPE))) {
			setOption(SocketOptionLevel.SOCKET, cast(SocketOption)SO_NOSIGPIPE, true);
		}
	}

public:
	/++
		Returns: The local machine's host name
		Throws: `SocketOSException` if the host name cannot be obtained.
	+/
	static @property string hostName() @trusted {
		char[256] result = void; // Host names are limited to 255 chars.
		if (ERROR == gethostname(result.ptr, result.length))
			throw new SocketOSException("Unable to obtain host name");
		return text(result.ptr);
	}

	/++
		Create a blocking socket. If a single protocol type exists to support
		this socket type within the address family, the `Protocol` may be
		omitted.
	+/
	this(AddrFamily af, SocketType type, Protocol protocol = Protocol.IP) {
		_family = af;
		const handle = cast(socket_t)socket(af, type, protocol);
		if (handle == socket_t.init)
			throw new SocketOSException("Unable to create socket");
		setSock(handle);
	}

	/++
		Create a blocking socket using the parameters from the specified
		`AddrInfo` structure.
	+/
	this(in AddrInfo info) {
		this(info.family, info.type, info.protocol);
	}

	nothrow @nogc {
		/// Use an existing socket handle.
		this(socket_t s, AddrFamily af) pure
		in (s != socket_t.init) {
			sock = s;
			_family = af;
		}

		/// Get underlying socket handle.
		@property socket_t handle() const pure => sock;

		/++
			Releases the underlying socket handle from the Socket object. Once it
			is released, you cannot use the Socket object's methods anymore. This
			also means the Socket destructor will no longer close the socket - it
			becomes your responsibility.

			To get the handle without releasing it, use the `handle` property.
		+/
		@property socket_t release() pure {
			const h = sock;
			sock = socket_t.init;
			return h;
		}

		/// Get the socket's address family.
		@property AddrFamily family() const @trusted pure
			=> cast(AddrFamily)(_family & ~BIOFlag);

		alias addressFamily = family;

		/++
			Get/set socket's blocking flag.

			When a socket is blocking, calls to receive(), accept(), and send()
			will block and wait for data/action.
			A non-blocking socket will immediately return instead of blocking.
		+/
		@property bool blocking() @trusted const {
			version (Windows) {
				return (_family & BIOFlag) == 0;
			} else version (Posix) {
				return !(fcntl(handle, F_GETFL, 0) & O_NONBLOCK);
			}
		}
	}
	/// ditto
	@property int blocking(bool byes) @trusted {
		version (Windows) {
			uint num = !byes;
			if (ERROR == ioctlsocket(sock, FIONBIO, &num))
				return errno();
			if (num)
				_family |= BIOFlag;
			else
				_family &= ~BIOFlag;
		} else version (Posix) {
			int x = fcntl(sock, F_GETFL, 0);
			if (-1 == x)
				return errno();
			if (byes)
				x &= ~O_NONBLOCK;
			else
				x |= O_NONBLOCK;
			if (-1 == fcntl(sock, F_SETFL, x))
				return errno();
		}
		return 0;
	}

	/// Property that indicates if this is a valid, alive socket.
	@property bool isAlive() @trusted nothrow const {
		int type = void;
		auto typesize = cast(socklen_t)type.sizeof;
		return !getsockopt(sock, SOL_SOCKET, SO_TYPE, &type, &typesize);
	}

	/++
		Accept an incoming connection. If the socket is blocking, `accept`
		waits for a connection request. Returns Socket.init if the socket is
		unable to _accept. See `accepting` for use with derived classes.
	+/
	Socket accept() @trusted {
		auto newsock = cast(socket_t).accept(sock, null, null);
		if (socket_t.init == newsock)
			return Socket.init;

		//inherits blocking mode
		return Socket(newsock, _family);
	}

	/++
		Associate a local address with this socket.

		Params:
			addr = The $(LREF Address) to associate this socket with.

		Throws: $(LREF SocketOSException) when unable to bind the socket.
	+/
	void bind(in Address addr) @trusted
		=> checkError(.bind(sock, addr.name, addr.nameLen),
			"Unable to bind socket");

	/++
		Establish a connection. If the socket is blocking, connect waits for
		the connection to be made. If the socket is nonblocking, connect
		returns immediately and the connection attempt is still in progress.
	+/
	void connect(in Address to) @trusted {
		if (ERROR == .connect(sock, to.name, to.nameLen)) {
			const err = errno();

			version (Windows) {
				if (WSAEWOULDBLOCK == err)
					return;
			} else version (Posix) {
				if (EINPROGRESS == err)
					return;
			}
			throw new SocketOSException("Unable to connect socket", err);
		}
	}

	/++
		Listen for an incoming connection. `bind` must be called before calling `listen`.
		Params:
			backlog = The maximum number of pending connections.
	+/
	void listen(int backlog = 128) @trusted
		=> checkError(.listen(sock, backlog), "Unable to listen on socket");

	nothrow @nogc {
		/// Disables sends and/or receives.
		int shutdown(SocketShutdown how) @trusted
			=> .shutdown(sock, how);

		/++
			Immediately drop any connections and release socket resources.
			The `Socket` object is no longer usable after `close`.
			Calling `shutdown` before `close` is recommended
			for connection-oriented sockets.
		+/
		void close() @trusted {
			free(ptr);
			_close(sock);
			sock = socket_t.init;
		}
	}

	/// Remote endpoint `Address`.
	@property Address remoteAddr() @trusted
	out (addr; addr.family == family) {
		Address addr = createAddr();
		socklen_t nameLen = addr.nameLen;
		checkError(.getpeername(sock, addr.name, &nameLen),
			"Unable to obtain remote socket address");
		addr.nameLen = nameLen;
		return addr;
	}

	/// Local endpoint `Address`.
	@property Address localAddr() @trusted
	out (addr; addr.family == family) {
		Address addr = createAddr();
		socklen_t nameLen = addr.nameLen;
		checkError(.getsockname(sock, addr.name, &nameLen),
			"Unable to obtain local socket address");
		addr.nameLen = nameLen;
		return addr;
	}

	/++
		Send or receive error code. See `wouldHaveBlocked`,
		`lastSocketError` and `Socket.getErrorText` for obtaining more
		information about the error.
	+/
	enum int ERROR = SOCKET_ERROR;

	/++
		Send data on the connection. If the socket is blocking and there is no
		buffer space left, `send` waits.
		Returns: The number of bytes actually sent, or `Socket.ERROR` on
		failure.
	+/
	ptrdiff_t send(in void[] buf, SocketFlags flags) @trusted nothrow {
		static if (is(typeof(MSG_NOSIGNAL))) {
			flags = cast(SocketFlags)(flags | MSG_NOSIGNAL);
		}
		return .send(sock, buf.ptr, capToInt(buf.length), flags);
	}

	/// ditto
	ptrdiff_t send(in void[] buf) nothrow
		=> send(buf, SocketFlags.none);

	/++
		Send data to a specific destination Address. If the destination address is
		not specified, a connection must have been made and that address is used.
		If the socket is blocking and there is no buffer space left, `sendTo` waits.
		Returns: The number of bytes actually sent, or `Socket.ERROR` on
		failure.
	+/
	ptrdiff_t sendTo(in void[] buf, SocketFlags flags, in Address to) @trusted {
		static if (is(typeof(MSG_NOSIGNAL))) {
			flags = cast(SocketFlags)(flags | MSG_NOSIGNAL);
		}
		return .sendto(sock, buf.ptr, capToInt(buf.length), flags, to.name, to.nameLen);
	}

	/// ditto
	ptrdiff_t sendTo(in void[] buf, in Address to)
		=> sendTo(buf, SocketFlags.none, to);

	//assumes you connect()ed
	/// ditto
	ptrdiff_t sendTo(in void[] buf, SocketFlags flags = SocketFlags.none) @trusted {
		static if (is(typeof(MSG_NOSIGNAL))) {
			flags = cast(SocketFlags)(flags | MSG_NOSIGNAL);
		}
		return .sendto(sock, buf.ptr, capToInt(buf.length), flags, null, 0);
	}

	/++
		Receive data on the connection. If the socket is blocking, `receive`
		waits until there is data to be received.
		Returns: The number of bytes actually received, `0` if the remote side
		has closed the connection, or `Socket.ERROR` on failure.
	+/
	ptrdiff_t receive(scope void[] buf, SocketFlags flags = SocketFlags.none) @trusted {
		return buf.length ? .recv(sock, buf.ptr, capToInt(buf.length), flags) : 0;
	}

	/++
		Receive data and get the remote endpoint `Address`.
		If the socket is blocking, `receiveFrom` waits until there is data to
		be received.
		Returns: The number of bytes actually received, `0` if the remote side
		has closed the connection, or `Socket.ERROR` on failure.
	+/
	ptrdiff_t receiveFrom(scope void[] buf, SocketFlags flags, ref Address from) @trusted {
		if (!buf.length) //return 0 and don't think the connection closed
			return 0;
		if (from.family != family)
			from = createAddr();
		socklen_t nameLen = from.nameLen;
		const read = .recvfrom(sock, buf.ptr, capToInt(buf.length), flags, from.name, &nameLen);

		if (read >= 0) {
			from.nameLen = nameLen;
			assert(from.family == family, "Address family mismatch");
		}
		return read;
	}

	/// ditto
	ptrdiff_t receiveFrom(scope void[] buf, ref Address from)
		=> receiveFrom(buf, SocketFlags.none, from);

	//assumes you connect()ed
	/// ditto
	ptrdiff_t receiveFrom(scope void[] buf, SocketFlags flags = SocketFlags.none) @trusted {
		if (!buf.length) //return 0 and don't think the connection closed
			return 0;
		return .recvfrom(sock, buf.ptr, capToInt(buf.length), flags, null, null);
	}

	/++
		Get a socket option.
		Returns: The number of bytes written to `result`.
		The length, in bytes, of the actual result - very different from getsockopt()
	+/
	int getOption(SocketOptionLevel level, SocketOption option, scope void[] result) @trusted {
		auto len = cast(socklen_t)result.length;
		checkError(.getsockopt(sock, level, option, result.ptr, &len),
			"Unable to get socket option");
		return len;
	}

	/// Common case of getting integer and boolean options.
	int getOption(SocketOptionLevel level, SocketOption option, out int result) @trusted {
		return getOption(level, option, (&result)[0 .. 1]);
	}

	/// Get the linger option.
	int getOption(SocketOptionLevel level, SocketOption option, out Linger result) @trusted {
		//return getOption(cast(SocketOptionLevel) SocketOptionLevel.SOCKET, SocketOption.LINGER, (&result)[0 .. 1]);
		return getOption(level, option, (&result.clinger)[0 .. 1]);
	}

	/// Get a timeout (duration) option.
	void getOption(SocketOptionLevel level, SocketOption option, out Duration result) @trusted {
		enforce(option == SocketOption.sndtimeo || option == SocketOption.rcvtimeo,
			new SocketParamException(text("Not a valid timeout option: ", option)));
		// WinSock returns the timeout values as a milliseconds DWORD,
		// while Linux and BSD return a timeval struct.
		version (Windows) {
			int ms;
			getOption(level, option, (&ms)[0 .. 1]);
			if (option == SocketOption.rcvtimeo)
				ms += WINSOCK_TIMEOUT_SKEW;
			result = ms.msecs;
		} else version (Posix) {
			timeval tv;
			getOption(level, option, (&tv)[0 .. 1]);
			result = tv.tv_sec.seconds + tv.tv_usec.usecs;
		} else
			static assert(0, "No socket support for this platform yet.");
	}

	/// Set a socket option.
	void setOption(SocketOptionLevel level, SocketOption option, scope void[] value) @trusted
		=> checkError(.setsockopt(sock, level, option, value.ptr, cast(uint)value.length),
			"Unable to set socket option");

	/// Common case for setting integer and boolean options.
	void setOption(SocketOptionLevel level, SocketOption option, int value) @trusted
		=> setOption(level, option, (&value)[0 .. 1]);

	/// Set the linger option.
	void setOption(SocketOptionLevel level, SocketOption option, Linger value) @trusted
		=> setOption(level, option, (&value)[0 .. 1]);

	/++
		Sets a timeout (duration) option, i.e. `SocketOption.sndtimeo` or
		`rcvtimeo`. Zero indicates no timeout.

		In a typical application, you might also want to consider using
		a non-blocking socket instead of setting a timeout on a blocking one.

		Note: While the receive timeout setting is generally quite accurate
		on *nix systems even for smaller durations, there are two issues to
		be aware of on Windows: First, although undocumented, the effective
		timeout duration seems to be the one set on the socket plus half
		a second. `setOption()` tries to compensate for that, but still,
		timeouts under 500ms are not possible on Windows. Second, be aware
		that the actual amount of time spent until a blocking call returns
		randomly varies on the order of 10ms.

		Params:
			level  = The level at which a socket option is defined.
			option = Either `SocketOption.sndtimeo` or `SocketOption.rcvtimeo`.
			value  = The timeout duration to set. Must not be negative.

		Throws: `SocketException` if setting the options fails.

		Example:
		---
		import std.datetime;
		import std.typecons;
		auto pair = socketPair();
		scope(exit) foreach (s; pair) s.close();

		// Set a receive timeout, and then wait at one end of
		// the socket pair, knowing that no data will arrive.
		pair[0].setOption(SocketOptionLevel.SOCKET,
			SocketOption.rcvtimeo, 1.seconds);

		auto sw = StopWatch(Yes.autoStart);
		ubyte[1] buffer;
		pair[0].receive(buffer);
		writefln("Waited %s ms until the socket timed out.",
			sw.peek.msecs);
		---
	+/
	void setOption(SocketOptionLevel level, SocketOption option, Duration value) @trusted {
		enforce(option == SocketOption.sndtimeo || option == SocketOption.rcvtimeo,
			new SocketParamException(text("Not a valid timeout option: ", option)));

		enforce(value >= 0.hnsecs, new SocketParamException(
				"Timeout duration must not be negative."));

		version (Windows) {
			import std.algorithm : max;

			int ms = cast(int)value.total!"msecs";
			if (ms != 0 && option == SocketOption.rcvtimeo)
				ms = max(1, ms - WINSOCK_TIMEOUT_SKEW);
			setOption(level, option, ms);
		} else version (Posix) {
			timeval tv;
			tv.tv_sec = cast(int)value.total!"seconds";
			tv.tv_usec = cast(int)value.total!"usecs" % 1_000_000;
			setOption(level, option, (&tv)[0 .. 1]);
		} else
			static assert(0, "No socket support for this platform yet.");
	}

	/++
		Get a text description of this socket's error status, and clear the
		socket's error status.
	+/
	string getErrorText() @trusted {
		int err = void;
		getOption(SocketOptionLevel.SOCKET, SocketOption.error, err);
		return formatSocketError(err);
	}

	/++
		Enables TCP keep-alive with the specified parameters.

		Params:
		time     = Number of seconds with no activity until the first
					keep-alive packet is sent.
		interval = Number of seconds between when successive keep-alive
					packets are sent if no acknowledgement is received.

		Throws: `SocketOSException` if setting the options fails, or
		`SocketFeatureException` if setting keep-alive parameters is
		unsupported on the current platform.
	+/
	void setKeepAlive(int time, int interval) @trusted {
		version (Windows) {
			tcp_keepalive options;
			options.onoff = 1;
			options.keepalivetime = time * 1000;
			options.keepaliveinterval = interval * 1000;
			uint cbBytesReturned = void;
			checkError(WSAIoctl(sock, SIO_KEEPALIVE_VALS,
					&options, options.sizeof, null, 0,
					&cbBytesReturned, null, null), "Error setting keep-alive");
		} else static if (is(typeof(TCP_KEEPIDLE)) && is(typeof(TCP_KEEPINTVL))) {
			setOption(SocketOptionLevel.TCP, TCP_KEEPIDLE, time);
			setOption(SocketOptionLevel.TCP, TCP_KEEPINTVL, interval);
			setOption(SocketOptionLevel.SOCKET, SocketOption.keepAlive, true);
		} else
			throw new SocketFeatureException(
				"Setting keep-alive options is not supported on this platform");
	}

	/++
		Returns: A new `Address` object for the current address family.
	+/
	private Address createAddr() nothrow @nogc @trusted {
		free(ptr);
		switch (family) {
			static if (is(UnixAddr)) {
		case AddrFamily.UNIX:
				ptr = alloc!(UnixAddr, false);
				return *cast(UnixAddr*)ptr = UnixAddr.init;
			}
		case AddrFamily.IPv4:
			ptr = alloc!IPv4Addr;
			return *cast(IPv4Addr*)ptr;
		case AddrFamily.IPv6:
			ptr = alloc!IPv6Addr;
			return *cast(IPv6Addr*)ptr;
		default:
		}
		ptr = alloc!UnknownAddr;
		return *cast(UnknownAddr*)ptr;
	}
}

/// Constructs a blocking TCP Socket.
auto tcpSocket(AddrFamily af = AddrFamily.IPv4)
	=> Socket(af, SocketType.stream, Protocol.TCP);

/// Constructs a blocking TCP Socket and connects to the given `Address`.
auto tcpSocket(in Address connectTo) {
	auto s = tcpSocket(connectTo.family);
	s.connect(connectTo);
	return s;
}

/// Constructs a blocking UDP Socket.
auto udpSocket(AddrFamily af = AddrFamily.IPv4)
	=> Socket(af, SocketType.dgram, Protocol.UDP);

@safe unittest {
	byte[] buf;
	buf.length = 1;
	auto s = udpSocket();
	assert(s.blocking);
	s.blocking = false;
	s.bind(IPv4Addr(IPv4Addr.anyPort));
	Address addr;
	s.receiveFrom(buf, addr);
}

/++
Returns: a pair of connected sockets.

The two sockets are indistinguishable.

Throws: `SocketException` if creation of the sockets fails.
+/
Socket[2] socketPair() {
	version (Posix) {
		int[2] socks;
		if (socketpair(AF_UNIX, SOCK_STREAM, 0, socks) == SOCKET_ERROR)
			throw new SocketOSException("Unable to create socket pair");

		return [
			Socket(cast(socket_t)socks[0], AddrFamily.UNIX),
			Socket(cast(socket_t)socks[1], AddrFamily.UNIX)
		];
	} else version (Windows) {
		// We do not have socketpair() on Windows, just manually create a
		// pair of sockets connected over some localhost port.

		auto listener = tcpSocket();
		listener.setOption(SocketOptionLevel.SOCKET, SocketOption.reuseAddr, true);
		listener.bind(IPv4Addr(INADDR_LOOPBACK, IPv4Addr.anyPort));
		const addr = listener.localAddr;
		listener.listen(1);

		Socket[2] result = [
			tcpSocket(addr),
			listener.accept()
		];

		listener.close();
		return result;
	}
}

///
@safe unittest {
	immutable ubyte[4] data = [1, 2, 3, 4];
	auto pair = socketPair();
	scope (exit)
		foreach (s; pair)
			s.close();

	pair[0].send(data[]);

	ubyte[data.length] buf;
	pair[1].receive(buf);
	assert(buf == data);
}

/++
Returns:
`true` if the last socket operation failed because the socket
was in non-blocking mode and the operation would have blocked,
or if the socket is in blocking mode and set a `sndtimeo` or `rcvtimeo`,
and the operation timed out.
+/
bool wouldHaveBlocked() nothrow @nogc {
	version (Windows)
		return errno() == WSAEWOULDBLOCK || errno() == WSAETIMEDOUT;
	else version (Posix)
		return errno() == EAGAIN;
}

@safe unittest {
	auto sockets = socketPair();
	auto s = sockets[0];
	s.setOption(SocketOptionLevel.SOCKET, SocketOption.rcvtimeo, 10.msecs);
	ubyte[16] buffer;
	auto rec = s.receive(buffer);
	assert(rec == -1 && wouldHaveBlocked());
}
