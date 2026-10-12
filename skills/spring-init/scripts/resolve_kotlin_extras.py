#!/usr/bin/env python3
"""Resolve the newest stable versions of the Kotlin extras spring-init adds.

Usage: resolve_kotlin_extras.py <boot-version-id>

Prints one JSON object keyed by extra name, each value holding `version` (or
null) plus an optional `note`. Exits 1 when any lookup failed, so the caller
can leave that extra out instead of guessing a version that may not exist.
"""

import json
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET

METADATA_URLS = {
    "ktlint-gradle": "https://plugins.gradle.org/m2/org/jlleitschuh/gradle/ktlint/"
    "org.jlleitschuh.gradle.ktlint.gradle.plugin/maven-metadata.xml",
    "kotlin-logging": "https://repo1.maven.org/maven2/io/github/oshai/kotlin-logging-jvm/maven-metadata.xml",
    "springmockk": "https://repo1.maven.org/maven2/com/ninja-squad/springmockk/maven-metadata.xml",
}

# springmockk clones Spring's own mock-bean support, so each major only works
# with one Spring generation: 5.x needs Framework 7 (Boot 4), 4.x is Boot 3.
SPRINGMOCKK_MAJOR_FOR_BOOT = {3: 4, 4: 5}
SPRINGMOCKK_COMPAT_URL = "https://github.com/Ninja-Squad/springmockk#versions-compatibility"

# Only digits and dots count as stable. Pre-releases in these repos use
# -rc.N, -beta-NN and -SNAPSHOT, all of which this pattern rejects.
STABLE = re.compile(r"^\d+(\.\d+)*$")


def fetch_versions(url):
    request = urllib.request.Request(url, headers={"User-Agent": "spring-init-skill"})
    with urllib.request.urlopen(request, timeout=15) as response:
        root = ET.fromstring(response.read())
    return [v.text.strip() for v in root.iter("version") if v.text]


def numeric_key(version):
    # Compare as integers: kotlin-logging publishes 8.0.03 before 8.0.4.
    return tuple(int(part) for part in version.split("."))


def newest_stable(versions, major=None):
    stable = [v for v in versions if STABLE.match(v)]
    if major is not None:
        stable = [v for v in stable if numeric_key(v)[0] == major]
    return max(stable, key=numeric_key) if stable else None


def resolve(boot_version):
    boot_match = re.match(r"(\d+)", boot_version)
    boot_major = int(boot_match.group(1)) if boot_match else None

    result = {}
    failed = False
    for name, url in METADATA_URLS.items():
        entry = {"version": None}
        try:
            versions = fetch_versions(url)
        except Exception as error:  # network, HTTP, or XML failure
            entry["note"] = f"lookup failed: {error}"
            result[name] = entry
            failed = True
            continue

        major = None
        if name == "springmockk":
            major = SPRINGMOCKK_MAJOR_FOR_BOOT.get(boot_major)
            if major is None:
                entry["note"] = (
                    f"no known springmockk line for Boot {boot_version}; using the newest release, "
                    f"confirm compatibility at {SPRINGMOCKK_COMPAT_URL}"
                )

        entry["version"] = newest_stable(versions, major)
        if entry["version"] is None:
            entry["note"] = "no stable release found" + (f" in the {major}.x line" if major else "")
            failed = True
        result[name] = entry

    return result, failed


def main():
    if len(sys.argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    result, failed = resolve(sys.argv[1])
    print(json.dumps(result, indent=2))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
