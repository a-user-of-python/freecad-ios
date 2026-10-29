#pragma once
/* S4 spike shim: FreeCAD's <FCGlobal.h> export-macro header.
 * SoMouseWheelEvent.h needs GuiExport; in this static spike build all
 * export/import annotations are empty. */
#ifndef GuiExport
#define GuiExport
#endif
#ifndef GuiImport
#define GuiImport
#endif
#ifndef AppExport
#define AppExport
#endif
#ifndef BaseExport
#define BaseExport
#endif
