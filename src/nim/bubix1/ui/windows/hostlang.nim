## Win32 backend for ui/hostlang.nim.

proc getUserDefaultUILanguage(): uint16
  {.importc: "GetUserDefaultUILanguage", stdcall, dynlib: "kernel32".}

const LangJapanese = 0x11'u16 ## LANG_JAPANESE, the low 10 bits of an LCID.

proc languageTag*(): string =
  ## Only Japanese is named, because that is the only language besides
  ## English this app has a catalog for and an LCID cannot be turned into
  ## a tag without a table. Anything else reads as "unknown", which the
  ## facade resolves to English - the same answer a full tag would give
  ## today. Swap in `GetUserDefaultLocaleName`, which returns a BCP 47
  ## name directly, when Windows is actually built and a third catalog
  ## makes the distinction matter.
  if (getUserDefaultUILanguage() and 0x3ff'u16) == LangJapanese: "ja" else: ""
