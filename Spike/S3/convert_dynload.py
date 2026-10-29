#!/usr/bin/env python3
"""Convert in-bundle .so extension modules to .framework + .fwork.

Mirrors BeeWare Python-Apple-support's build/utils.sh `install_dylib`
(the official CPython-on-iOS packaging route): each .so under the
given lib-dynload directory is moved into
    <app>/Frameworks/<dotted.module.name>.framework/<module.name>
and replaced in place by a <name>.fwork pointer file whose content is
the framework path. CPython's AppleFrameworkLoader (importlib) reads
the .fwork and dlopens the framework binary. Signing is the caller's
job (the build script codesigns each framework after conversion).

Usage: convert_dynload.py <app_bundle> <template_plist> <bundle_id>
"""

import os
import plistlib
import shutil
import sys


def main() -> int:
    app, template, bundle_id = sys.argv[1], sys.argv[2], sys.argv[3]
    dynload_rel = os.path.join("python", "lib", "python3.13", "lib-dynload")
    dynload = os.path.join(app, dynload_rel)
    with open(template, "rb") as fh:
        template_plist = plistlib.load(fh)

    converted = []
    for name in sorted(os.listdir(dynload)):
        if not name.endswith(".so"):
            continue
        full_ext = os.path.join(dynload, name)
        module_name = name.split(".")[0]
        # lib-dynload is flat, so the dotted name is the module name.
        full_module_name = module_name
        framework_rel = os.path.join(
            "Frameworks", full_module_name + ".framework")
        framework_dir = os.path.join(app, framework_rel)
        os.makedirs(framework_dir, exist_ok=True)

        plist = dict(template_plist)
        plist["CFBundleExecutable"] = full_module_name
        plist["CFBundleIdentifier"] = (
            bundle_id + "." + full_module_name).replace("_", "-")
        plist.pop("CFBundleName", None)
        with open(os.path.join(framework_dir, "Info.plist"), "wb") as fh:
            plistlib.dump(plist, fh)

        dest = os.path.join(framework_dir, full_module_name)
        shutil.move(full_ext, dest)
        # .fwork pointer where the .so used to be.
        fwork_path = full_ext[: -len(".so")] + ".fwork"
        with open(fwork_path, "w", encoding="utf-8") as fh:
            fh.write(os.path.join(framework_rel, full_module_name) + "\n")
        # Back-reference inside the framework (utils.sh parity).
        with open(dest + ".origin", "w", encoding="utf-8") as fh:
            rel_ext = os.path.join(dynload_rel, name)
            fh.write(rel_ext[: -len(".so")] + ".fwork\n")
        converted.append(full_module_name)

    print("converted %d dynload modules to frameworks" % len(converted))
    return 0


if __name__ == "__main__":
    sys.exit(main())
