# Kotlin Defaults

Opinionated additions applied to every project whose language is Kotlin.
Java and Groovy projects get none of this.

## Contents

1. What gets added
2. Resolving versions
3. Writing `.editorconfig`
4. Editing the build file
5. Formatting with ktlint
6. Subproject layout
7. Verification

## 1. What gets added

| Default | Coordinate | Gradle | Maven |
|---------|------------|--------|-------|
| ktlint-gradle | plugin `org.jlleitschuh.gradle.ktlint` | yes | no — it is a Gradle plugin |
| kotlin-logging | `io.github.oshai:kotlin-logging-jvm` (implementation) | yes | yes |
| springmockk | `com.ninja-squad:springmockk` (test) | yes | yes |
| `.editorconfig` | copy of `assets/editorconfig` | yes | yes |

For Maven, tell the user ktlint was skipped because ktlint-gradle only works
with Gradle builds, so the missing plugin does not look like an oversight.

None of these are managed by the Spring Boot BOM, so each needs an explicit
version. kotlin-logging needs no extra SLF4J dependency, because Boot's
starters already bring SLF4J and Logback. Leave Mockito in place: springmockk
works alongside it, and the generated test starters stay untouched.

## 2. Resolving versions

Use the newest stable release at generation time, not a version remembered
from training data. These libraries release often, and a version that is
outdated or never existed is exactly what this lookup prevents. Run it once the
Boot version is final, just before Step 7, with the normalized boot `id`:

```bash
python3 <skill-dir>/scripts/resolve_kotlin_extras.py <bootVersion-id>
```

It prints JSON such as:

```json
{
  "ktlint-gradle": {"version": "14.2.0"},
  "kotlin-logging": {"version": "8.0.4"},
  "springmockk": {"version": "5.0.1"}
}
```

What the script handles, so you do not have to:

- **Stable only.** A version counts only if it is digits and dots.
  kotlin-logging publishes `8.0.00-beta-01`, and ktlint-gradle publishes
  `13.0.0-rc.1`. Neither should end up in a new project.
- **Numeric ordering.** kotlin-logging released `8.0.03` before `8.0.4`, so
  versions are compared as integers, not as text.
- **springmockk follows the Spring generation.** 5.x needs Spring Framework 7
  (Boot 4.x), and 4.x is the Boot 3.x line. A Boot major the script does not
  recognize gets the newest release plus a `note`. Show that note to the user.

If an entry comes back with `"version": null`, leave that one default out and
tell the user why (the `note` says). Do not fill in a guessed version: the
build would fail to resolve it. If `python3` is unavailable, read
`<release>` from the same `maven-metadata.xml` URLs with `curl`. Apply the
stable-only and springmockk-line rules above by hand.

## 3. Writing `.editorconfig`

Copy `assets/editorconfig` byte-for-byte. Do not retype it, and do not
"normalize" values such as `ktlint_code_style = INTELLIJ_IDEA`. This is the
user's chosen configuration, and ktlint accepts it as written.

Write it **before** running ktlint. The file switches ktlint from its
`ktlint_official` default to the IntelliJ IDEA style and disables two rules.
Formatting first would apply the wrong style, and some of those changes would
not be undone afterwards.

Where it goes:

- **Standalone:** `./<artifact>/.editorconfig`. The `root = true` line stops
  ktlint and IDEs from also picking up an `.editorconfig` in a parent directory.
- **Subproject:** the Gradle root (`./.editorconfig`), so it covers every
  Kotlin module. If the root already has an `.editorconfig`, leave it alone and
  mention that the existing one governs the new module. Do not add a second
  one inside the module: its `root = true` would cut the module off from the
  repository's settings.

## 4. Editing the build file

Add each enabled default. Match the file's existing indentation (Initializr
uses tabs). ktlint reformats `.kts` files later, but `build.gradle` and
`pom.xml` stay exactly as you leave them.

**Gradle Kotlin DSL (`build.gradle.kts`)**: add the plugin as the last line
of `plugins { }`, put kotlin-logging after the last `implementation(...)`
line, and put springmockk after the last `testImplementation(...)` line:

```kotlin
plugins {
	// ...generated plugins...
	id("org.jlleitschuh.gradle.ktlint") version "<ktlint>"
}

dependencies {
	// ...generated implementation(...) lines...
	implementation("io.github.oshai:kotlin-logging-jvm:<kotlin-logging>")
	// ...generated testImplementation(...) lines...
	testImplementation("com.ninja-squad:springmockk:<springmockk>")
}
```

**Gradle Groovy DSL (`build.gradle`)**: same placement, Groovy syntax:

```groovy
id 'org.jlleitschuh.gradle.ktlint' version '<ktlint>'
implementation 'io.github.oshai:kotlin-logging-jvm:<kotlin-logging>'
testImplementation 'com.ninja-squad:springmockk:<springmockk>'
```

**Maven (`pom.xml`)**: inside the top-level `<dependencies>` (not the one
nested in the `kotlin-maven-plugin` configuration), add kotlin-logging after
the last compile-scope dependency and springmockk after the last test-scope
one:

```xml
<dependency>
	<groupId>io.github.oshai</groupId>
	<artifactId>kotlin-logging-jvm</artifactId>
	<version><kotlin-logging></version>
</dependency>
<dependency>
	<groupId>com.ninja-squad</groupId>
	<artifactId>springmockk</artifactId>
	<version><springmockk></version>
	<scope>test</scope>
</dependency>
```

## 5. Formatting with ktlint

Gradle builds with the ktlint plugin only. Initializr writes Kotlin sources
and `build.gradle.kts` with tabs, plus blank lines that ktlint rejects. The
plugin wires `ktlintCheck` into `check`, so without this step the user's first
`./gradlew build` fails on code they never wrote. Let the tool that owns the
rules fix the files rather than rewriting them by hand. Its rules change
between releases, and hand edits drift.

From inside `./<artifact>`, after `.editorconfig` and the build edits are in
place:

```bash
./gradlew ktlintFormat --console=plain -q
./gradlew ktlintCheck --console=plain -q
```

Run them as two separate commands so the check runs against the formatted
files. JVM warnings about `sun.misc.Unsafe` are noise from the embedded Kotlin
compiler. Judge success by the exit code.

This needs network access the first time, for the Gradle distribution and
ktlint artifacts. ktlint does not compile anything, so the Java toolchain the
project targets does not need to be installed. If either command fails,
show the user the output. Tell them the project was generated but still needs
`./gradlew ktlintFormat` before `./gradlew build` will pass. Do not undo the
other defaults over a formatting failure.

## 6. Subproject layout

Run the formatting **before** the subproject cleanup step. While
`./<artifact>` still has its own `gradlew` and `settings.gradle.kts`, it
builds on its own, whether or not the root has a wrapper. Afterwards, the
cleanup must also delete the `.gradle/` and `build/` directories that the
Gradle run left in the module. The module's `.gitignore` covered them, but
the cleanup deletes that file too.

If the root build already declares `org.jlleitschuh.gradle.ktlint`
(check the root `build.gradle(.kts)` and `gradle/libs.versions.toml`), add
the plugin to the module **without** a version: `id("org.jlleitschuh.gradle.ktlint")`.
Gradle rejects a versioned request for a plugin already on the build
classpath. The standalone format run cannot resolve an unversioned plugin.
In that case, skip it and suggest `./gradlew :<artifact>:ktlintFormat` from
the root instead.

## 7. Verification

- The build file contains each enabled coordinate at exactly the version the
  resolver printed, matching what the Step 7 summary showed.
- `.editorconfig` exists where Section 3 says, and is identical to
  `assets/editorconfig` (`cmp` it).
- Gradle: `ktlintCheck` exited 0. Otherwise the user was told to run
  `ktlintFormat`.
- Subproject: the module has no `gradlew`, `.gradle/`, or `build/`.
