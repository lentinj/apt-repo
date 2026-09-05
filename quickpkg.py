#!/usr/bin/python3
import configparser
import os
import os.path
import re
import subprocess
import shutil

def cfg_to_package(cfg_path, base="/tmp/quickpkg", distribution="stable"):
    config = read_cfg(cfg_path)
    pkg = config[configparser.UNNAMED_SECTION]

    package_path = os.path.join(base, "%s-%s" % (pkg["Name"], pkg["Version"]))
    if os.path.exists(package_path):
        shutil.rmtree(package_path)

    deb_path = os.path.join(package_path, "debian")
    os.makedirs(os.path.join(deb_path, "source"))
    with open(os.path.join(deb_path, "control"), "w") as f:
        f.write(package_control(pkg))
        f.write("\n")
    with open(os.path.join(deb_path, "changelog"), "w") as f:
        if "changelog" in config:
            f.write("".join(re.split(r'^[|] ?', config["changelog"]["content"], flags=re.MULTILINE)[1:]))
        else:
            f.write(package_changelog(pkg, distribution=distribution))
        f.write("\n")
    with open(os.path.join(deb_path, "copyright"), "w") as f:
        f.write(package_copyright(pkg))
        f.write("\n")
    with open(os.path.join(deb_path, "rules"), "w") as f:
        f.write(package_rules(pkg))
        f.write("\n")
    with open(os.path.join(deb_path, "source", "format"), "w") as f:
        f.write("3.0 (native)\n")
    os.chmod(os.path.join(deb_path, "rules"), 0o755)

    with open(os.path.join(deb_path, "%s.install" % pkg["Name"]), "w") as dh_install_f:
        for source_path, dest_path, content, chmod_mode in package_files(config):
            os.makedirs(os.path.join(package_path, os.path.dirname(source_path)), exist_ok=True)
            with open(os.path.join(package_path, source_path), "wb") as f:
                f.write(content)
            os.chmod(os.path.join(package_path, source_path), chmod_mode)
            dh_install_f.write("%s %s\n" % (source_path, os.path.dirname(dest_path)))

    cmd = ["/usr/bin/dpkg-buildpackage"]
    if not os.environ.get("KEY_AUTHOR"):
        cmd.extend(["-us", "-uc"])
    subprocess.run(cmd, cwd=package_path, check=True)


def read_cfg(cfg_path):
    config = configparser.ConfigParser(allow_unnamed_section=True, interpolation=None)
    config.read(cfg_path)
    pkg = config[configparser.UNNAMED_SECTION]

    if os.environ.get("KEY_AUTHOR"):
        authors = [os.environ["KEY_AUTHOR"]]
    else:
        authors = [x for x in _git("log", "--pretty=format:%an <%ae>", cfg_path) if x]
    is_dirty = "\n".join(_git("diff", "--stat", cfg_path)) != ""
    pkg["Path"] = cfg_path
    if "Name" not in pkg:
        pkg["Name"] = os.path.splitext(os.path.basename(cfg_path))[0]
    if "Version" not in pkg:
        pkg["Version"] = "%d.%d" % (len(authors), 1 if is_dirty else 0)
    if "Author" not in pkg:
        pkg["Author"] = authors[0] if len(authors) > 0 else "unknown <unknown@example.com>"
    if "Origin" not in pkg:
        pkg["Origin"] = "".join(_git("remote", "get-url", "origin"))
    if "License" not in pkg:
        pkg["License"] = "closed"
    if "Section" not in pkg:
        pkg["Section"] = "misc"
    if "Date" not in pkg:
        pkg["Date"] = _git("log", "--pretty=format:'%as'", cfg_path)[0]
    return config


def package_control(pkg):
    # https://www.debian.org/doc/debian-policy/ch-controlfields.html

    def _as_control_list(name, val):
        if not val or val.strip() == "":
            return ""
        items = [x.strip() for x in val.split("\n") if x.strip()] 
        
        return "%s:\n %s" % (
            name,
            ",\n ".join(items),
        )

    return f"""
Source: {pkg["Name"]}
Section: {pkg["Section"]}
Priority: optional
Maintainer: {pkg["Author"]}
Rules-Requires-Root: no
Build-Depends:
 debhelper-compat (= 13),
Standards-Version: 4.7.2
Vcs-Git: {pkg["Origin"]}

Package: {pkg["Name"]}
Architecture: all
Description: {"\n ".join(l.strip() for l in pkg.get("Description", "").split("\n"))}
{_as_control_list("Depends", pkg.get("Depends"))}{_as_control_list("Recommends", pkg.get("Recommends"))}{_as_control_list("Suggests", pkg.get("Suggests"))}{_as_control_list("Enhances", pkg.get("Enhances"))}
    """.strip()


def package_changelog(pkg, distribution="stable"):
    # https://www.debian.org/doc/debian-policy/ch-source.html#s-dpkgchangelog
    if pkg["Version"].startswith("0."):
        return f"""
{pkg["Name"]} ({pkg["Version"]}) {distribution}; urgency=medium

  Uncommitted package.

 -- {pkg["Author"]}  Wed, 24 Sep 2025 11:08:59 +0000
        """.strip()

    changelog = "\n".join(_git("log", f"--pretty=format:pkgname (##) {distribution}; urgency=medium%n%n  %s%n%n -- %an <%ae>  %aD%n", pkg["Path"]))

    ver = 1
    prevlog = ""
    while prevlog != changelog:
        prevlog = changelog
        changelog = re.sub(r'^pkgname \(##\)', "%s (%d.0)" % (pkg["Name"], ver), changelog, count = 1, flags=re.MULTILINE)
        ver = ver + 1
    return changelog


def package_copyright(pkg):
    return f"""
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Source: <url://{pkg["Origin"]}>
Upstream-Name: {pkg["Name"]}
Upstream-Contact: {pkg["Author"]}

Files:
 *
Copyright: {pkg["Date"][0:4]} {pkg["Author"]}
License: {"\n  ".join(pkg["License"].split("\n"))}
    """.strip()


def package_rules(pkg):
    return f"""
#!/usr/bin/make -f
%:
	dh $@
    """.strip()


def package_files(config):
    for n in config.sections():
        if n == configparser.UNNAMED_SECTION or not n.startswith("/"):
            continue
        dest_path = n
        source_path = re.sub("^/", "", n)
        if 'content' in config[n]:
            content = ("".join(re.split(r'^[|] ?', config[n]['content'], flags=re.MULTILINE)[1:])).encode("utf8")
        elif 'content_hex' in config[n]:
            content = bytes.fromhex("".join(re.split(r'^[|] ?', config[n]['content_hex'], flags=re.MULTILINE)[1:]).replace("\n", ""))
        if config[n].get('executable', False) or dest_path.startswith("/bin/") or dest_path.startswith("/usr/bin/") or dest_path.startswith("/sbin/") or dest_path.startswith("/usr/sbin/"):
            chmod_mode = 0o775
        else:
            chmod_mode = 0o664
        yield source_path, dest_path, content, chmod_mode


def _git(*args):
    result = subprocess.run(['/usr/bin/git', *args], check=True, stdout=subprocess.PIPE, encoding="utf8")
    return result.stdout.strip().split("\n")


if __name__ == "__main__":
    import sys
    cfg_to_package(sys.argv[2], base=sys.argv[1], distribution=sys.argv[3])
