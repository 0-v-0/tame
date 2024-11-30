module tame.windows.registry;

// dfmt off
version (Windows):

import core.sys.windows.winbase;
import core.sys.windows.windef;
import core.sys.windows.winreg;
import tame.windows.charset;
public import core.sys.windows.windef : HKEY;

/// Enumeration of the recognised registry value types.
enum RegValueType : DWORD {
	NONE						= 0,	/// The null value type. (In practise this is treated as a zero-length binary array by the Win32 registry)
	SZ							= 1,	/// A zero-terminated string
	EXPAND_SZ					= 2,	/// A zero-terminated string containing expandable environment variable references
	BINARY						= 3,	/// A binary blob
	DWORD						= 4,	/// A 32-bit unsigned integer
	DWORD_LE					= 4,	/// A 32-bit unsigned integer, stored in little-endian byte order
	DWORD_BE					= 5,	/// A 32-bit unsigned integer, stored in big-endian byte order
	LINK						= 6,	/// A registry link
	MULTI_SZ					= 7,	/// A set of zero-terminated strings
	RESOURCE_LIST				= 8,	/// A hardware resource list
	FULL_RESOURCE_DESCRIPTOR	= 9,	/// A hardware resource descriptor
	RESOURCE_REQUIREMENTS_LIST	= 10,	/// A hardware resource requirements list
	QWORD						= 11,	/// A 64-bit unsigned integer
	QWORD_LE					= 11,	/// A 64-bit unsigned integer, stored in little-endian byte order
}

/// Enumeration of the recognised registry access modes.
enum REGSAM {
	KEY_QUERY_VALUE			= 0x0001,	/// Permission to query subkey data
	KEY_SET_VALUE			= 0x0002,	/// Permission to set subkey data
	KEY_CREATE_SUB_KEY		= 0x0004,	/// Permission to create subkeys
	KEY_ENUMERATE_SUB_KEYS	= 0x0008,	/// Permission to enumerate subkeys
	KEY_NOTIFY				= 0x0010,	/// Permission for change notification
	KEY_CREATE_LINK			= 0x0020,	/// Permission to create a symbolic link
	KEY_WOW64_32KEY			= 0x0200,	/// Enables a 64- or 32-bit application to open a 32-bit key
	KEY_WOW64_64KEY			= 0x0100,	/// Enables a 64- or 32-bit application to open a 64-bit key
	KEY_WOW64_RES			= 0x0300,	///
	KEY_READ				= (STANDARD_RIGHTS_READ
							| KEY_QUERY_VALUE | KEY_ENUMERATE_SUB_KEYS | KEY_NOTIFY)
							& ~SYNCHRONIZE,
										/// Combines the STANDARD_RIGHTS_READ, KEY_QUERY_VALUE,
										/// KEY_ENUMERATE_SUB_KEYS, and KEY_NOTIFY access rights
	KEY_WRITE               = (STANDARD_RIGHTS_WRITE
							| KEY_SET_VALUE | KEY_CREATE_SUB_KEY)
							& ~SYNCHRONIZE,
										/// Combines the STANDARD_RIGHTS_WRITE, KEY_SET_VALUE,
										/// and KEY_CREATE_SUB_KEY access rights
	KEY_EXECUTE             = KEY_READ & ~SYNCHRONIZE,
										/// Permission for read access
	KEY_ALL_ACCESS			= (STANDARD_RIGHTS_ALL
							| KEY_QUERY_VALUE | KEY_SET_VALUE | KEY_CREATE_SUB_KEY
							| KEY_ENUMERATE_SUB_KEYS | KEY_NOTIFY | KEY_CREATE_LINK)
							& ~SYNCHRONIZE,
										/// Combines the KEY_QUERY_VALUE, KEY_ENUMERATE_SUB_KEYS,
										/// KEY_NOTIFY, KEY_CREATE_SUB_KEY, KEY_CREATE_LINK, and
										/// KEY_SET_VALUE access rights, plus all the standard
										/// access rights except SYNCHRONIZE
}
// dfmt on

nothrow @nogc:

int tryOpen(in HKEY hkey, in wchar[] subKey, out HKEY result, REGSAM samDesired = REGSAM.KEY_READ)
in (hkey) {
	return RegOpenKeyExW(hkey, subKey.ptr, 0, compatibleRegsam(samDesired), &result);
}

int tryQuery(in HKEY hkey, in wchar[] name, wchar* data, ref uint len)
in (hkey) {
	DWORD type;
	const res = RegQueryValueExW(hkey, name.ptr, null, &type, data, &len);

	if (res == ERROR_SUCCESS && data) {
		switch (type) {
		case RegValueType.SZ:
		case RegValueType.EXPAND_SZ:
			debug {
				auto ws = (cast(immutable(wchar)*)data)[0 .. len / wchar.sizeof];
				assert(ws.length > 0 && ws[$ - 1] == '\0');
				if (ws.length && ws[$ - 1] == '\0')
					ws.length = ws.length - 1;
				assert(ws.length == 0 || ws[$ - 1] != '\0');
			}
			break;
		default:
			return ERROR_INVALID_DATA;
		}
	}
	return res;
}

LONG close(in HKEY hkey)
	=> hkey ? RegCloseKey(hkey) : ERROR_SUCCESS;

private REGSAM compatibleRegsam(REGSAM samDesired){
	BOOL isWow64;
	IsWow64Process(GetCurrentProcess(), &isWow64);
	return isWow64 ? samDesired : cast(REGSAM)(samDesired & ~REGSAM.KEY_WOW64_RES);
}
