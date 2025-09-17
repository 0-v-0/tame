module tame.windows.clipboard;

version (Windows)  : import core.sys.windows.windows;
import tame.unsafe.string;

/++
	Copies the given text to the Windows clipboard.
	Params:
		text = Text to copy to clipboard.
	Returns: 0 on success, or an error code on failure.
+/
int copyTextToClipboard(string text) {
	if (!OpenClipboard(null))
		return GetLastError();
	scope (exit) {
		CloseClipboard();
	}
	if (!EmptyClipboard()) {
		return GetLastError();
	}
	const wideCount = MultiByteToWideChar(
		CP_UTF8,
		0,
		text.ptr, cast(int)text.length,
		null, 0
	);
	auto hMem = GlobalAlloc(GMEM_MOVEABLE, (wideCount + 1) * wchar.sizeof);
	if (hMem is null) {
		return GetLastError();
	}
	auto pMem = cast(wchar*)GlobalLock(hMem);
	if (pMem is null) {
		GlobalFree(hMem);
		return GetLastError();
	}
	const len = MultiByteToWideChar(
		CP_UTF8,
		0,
		text.ptr, cast(int)text.length,
		pMem, wideCount
	);
	pMem[len] = 0;
	if (!GlobalUnlock(hMem)) {
		const err = GetLastError();
		if (err != NO_ERROR) {
			GlobalFree(hMem);
			return err;
		}
	}
	if (!SetClipboardData(CF_UNICODETEXT, hMem))
		return GetLastError();
	return 0;
}

extern (Windows) nothrow @nogc {
	BOOL AddClipboardFormatListener(HWND hwnd);
	BOOL RemoveClipboardFormatListener(HWND hwnd);
}
