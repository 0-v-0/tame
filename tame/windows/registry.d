module tame.windows.registry;

import core.sys.windows.winbase;
import core.sys.windows.windef;
import core.sys.windows.winreg;
import std.internal.windows.advapi32;
import tame.windows.charset;

// dfmt off
version (Windows):
/// Enumeration of the recognised registry value types.
enum REG_VALUE_TYPE : DWORD {
	REG_UNKNOWN						= -1, 	///
	REG_NONE						= 0,	/// The null value type. (In practise this is treated as a zero-length binary array by the Win32 registry)
	REG_SZ							= 1,	/// A zero-terminated string
	REG_EXPAND_SZ					= 2,	/// A zero-terminated string containing expandable environment variable references
	REG_BINARY						= 3,	/// A binary blob
	REG_DWORD						= 4,	/// A 32-bit unsigned integer
	REG_DWORD_LITTLE_ENDIAN			= 4,	/// A 32-bit unsigned integer, stored in little-endian byte order
	REG_DWORD_BIG_ENDIAN			= 5,	/// A 32-bit unsigned integer, stored in big-endian byte order
	REG_LINK						= 6,	/// A registry link
	REG_MULTI_SZ					= 7,	/// A set of zero-terminated strings
	REG_RESOURCE_LIST				= 8,	/// A hardware resource list
	REG_FULL_RESOURCE_DESCRIPTOR	= 9,	/// A hardware resource descriptor
	REG_RESOURCE_REQUIREMENTS_LIST	= 10,	/// A hardware resource requirements list
	REG_QWORD						= 11,	/// A 64-bit unsigned integer
	REG_QWORD_LITTLE_ENDIAN			= 11,	/// A 64-bit unsigned integer, stored in little-endian byte order
}

/// Enumeration of the recognised registry access modes.
enum REGSAM {
	KEY_QUERY_VALUE         = 0x0001,   /// Permission to query subkey data
	KEY_SET_VALUE           = 0x0002,   /// Permission to set subkey data
	KEY_CREATE_SUB_KEY      = 0x0004,   /// Permission to create subkeys
	KEY_ENUMERATE_SUB_KEYS  = 0x0008,   /// Permission to enumerate subkeys
	KEY_NOTIFY              = 0x0010,   /// Permission for change notification
	KEY_CREATE_LINK         = 0x0020,   /// Permission to create a symbolic link
	KEY_WOW64_32KEY         = 0x0200,   /// Enables a 64- or 32-bit application to open a 32-bit key
	KEY_WOW64_64KEY         = 0x0100,   /// Enables a 64- or 32-bit application to open a 64-bit key
	KEY_WOW64_RES           = 0x0300,   ///
	KEY_READ                = (STANDARD_RIGHTS_READ
							| KEY_QUERY_VALUE | KEY_ENUMERATE_SUB_KEYS | KEY_NOTIFY)
							& ~(SYNCHRONIZE),
										/// Combines the STANDARD_RIGHTS_READ, KEY_QUERY_VALUE,
										/// KEY_ENUMERATE_SUB_KEYS, and KEY_NOTIFY access rights
	KEY_WRITE               = (STANDARD_RIGHTS_WRITE
							| KEY_SET_VALUE | KEY_CREATE_SUB_KEY)
							& ~(SYNCHRONIZE),
										/// Combines the STANDARD_RIGHTS_WRITE, KEY_SET_VALUE,
										/// and KEY_CREATE_SUB_KEY access rights
	KEY_EXECUTE             = KEY_READ & ~(SYNCHRONIZE),
										/// Permission for read access
	KEY_ALL_ACCESS          = (STANDARD_RIGHTS_ALL
							| KEY_QUERY_VALUE | KEY_SET_VALUE | KEY_CREATE_SUB_KEY
							| KEY_ENUMERATE_SUB_KEYS | KEY_NOTIFY | KEY_CREATE_LINK)
							& ~(SYNCHRONIZE),
										/// Combines the KEY_QUERY_VALUE, KEY_ENUMERATE_SUB_KEYS,
										/// KEY_NOTIFY, KEY_CREATE_SUB_KEY, KEY_CREATE_LINK, and
										/// KEY_SET_VALUE access rights, plus all the standard
										/// access rights except SYNCHRONIZE
}
// dfmt on

private:

REGSAM compatibleRegsam(REGSAM samDesired)
	=> isWow64 ? samDesired : cast(REGSAM)(samDesired & ~REGSAM.KEY_WOW64_RES);

LONG close(in HKEY hkey)
	=> hkey ? RegCloseKey(hkey) : ERROR_SUCCESS;
