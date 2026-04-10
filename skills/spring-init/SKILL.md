---
name: spring-init
version: 0.3.0
description: >-
  Initialize a new Spring Boot project using Spring Initializr via the spring CLI.
  Use when the user says "new spring project", "spring init", "create spring boot app",
  "/spring-init", or wants to scaffold a new Spring Boot application. Also trigger when
  the user mentions Spring Boot setup, project scaffolding with Spring, or bootstrapping
  a new backend service with Spring.
---

# Spring Init

Scaffold a new Spring Boot project interactively using the Spring Initializr API
via the `spring` CLI.

## Prerequisites

### 1. Verify the Spring CLI

Run `command -v spring`.

- **If missing**, tell the user:
  "Spring CLI not found. Install via `sdk install springboot`." and stop.
- **If present**, continue. The CLI version should generally match the target
  Boot version. If generation fails later due to a stale CLI, suggest upgrading:
  `sdk install springboot <version>` (e.g. `sdk install springboot {LATEST_STABLE_BOOT.display}`).

### 2. Fetch live metadata from the Spring Initializr API

Run:
```bash
curl -s -H 'Accept: application/json' https://start.spring.io
```

Parse the JSON response and extract these data structures for use in all
subsequent steps:

| Key | JSON path | Description |
|-----|-----------|-------------|
| `BOOT_VERSIONS` | `bootVersion.values[]` | Array of `{id, name}` |
| `JAVA_VERSIONS` | `javaVersion.values[]` | Array of `{id, name}`, ordered highest-first |
| `TYPES` | `type.values[]` | Project types; filter to `tags.format == "project"` only |
| `LANGUAGES` | `language.values[]` | Array of `{id, name}` |
| `DEP_GROUPS` | `dependencies.values[]` | Groups, each with `name` and nested `values[]` of `{id, name, description, versionRange}` |

**Derived values:**

Each boot version has two representations — the `name` (human-readable, for
prompts) and the `id` (API identifier, for the `spring init -b` flag). These
can differ significantly: e.g. `name="4.1.0 (M4)"` vs `id="4.1.0.M4"`, or
`name="4.0.5"` vs `id="4.0.5.RELEASE"`. Always track both. Show the `name`
to the user; pass the `id` to `spring init -b`.

- **`LATEST_STABLE_BOOT`** — The first entry in `BOOT_VERSIONS` whose `name`
  contains no parenthetical qualifier (no "SNAPSHOT", "M", "RC"). Store both:
  - `display`: the `name` field (e.g. `"4.0.5"`)
  - `id`: the `id` field (e.g. `"4.0.5.RELEASE"`)
- **`LATEST_3X_STABLE`** — Same logic, but the first stable version whose `name`
  starts with `3.` (if any still exist in the list). Store both `display` and `id`.
- **`JAVA_HIGHEST`** — The first entry in `JAVA_VERSIONS` (already ordered
  highest-first by the API), e.g. `"26"`.

**Categorize boot versions** for Step 3:
- **Stable**: `name` has no parenthetical qualifier
- **Milestone/RC**: `name` contains `(M...)` or `(RC...)`
- **Snapshot**: `name` contains `(SNAPSHOT)`

**Version range parsing** for filtering dependencies in Steps 5–6:

Dependencies may have a `versionRange` field using Maven range notation, e.g.
`[3.5.0.RELEASE,4.2.0.M1)` or just `4.0.0.RELEASE` (meaning ≥ that version).

- `[` = inclusive lower bound, `(` = exclusive lower bound
- `]` = inclusive upper bound, `)` = exclusive upper bound
- A bare version means "this version and above"
- Compare version parts numerically; qualifier order: no qualifier = `RELEASE` > `RC` > `M` > `BUILD-SNAPSHOT`
- Empty or absent `versionRange` means compatible with all Boot versions

A dependency is compatible with the selected Boot version if the Boot version
falls within its range.

### 3. Fallback — tiered degradation

The JSON API and `spring init --list` both contact `start.spring.io`, so a
full network or service outage will break both. Use a tiered fallback:

**Level 2 — `spring init --list`** (if `curl` fails due to a parse error,
missing `curl` binary, or a transient issue where the CLI may still work):

1. Run `spring init --list` and parse all three output sections:
   - **Parameters** table → extract `bootVersion` and `javaVersion` defaults
   - **Project types** table → extract available types and the default (marked `*`)
   - **Dependencies** table → extract IDs, descriptions, AND the "Required
     version" column (e.g. `>=3.5.0 and <4.1.0-M1`, `>=4.0.0`). Map these
     constraints to the same filtering logic described in the version range
     parsing section above so that Steps 5–6 can still filter incompatible
     dependencies.
2. Use `references/dependencies.md` for dependency group structure (the CLI
   output is a flat list without groups).
3. In Steps 3 and 4, present only the default boot/java versions and accept
   free-text input (the CLI does not enumerate available versions).
4. Note to the user that some options may be limited.

**Level 3 — fully offline** (if both `curl` and `spring init --list` fail):

1. Use `references/dependencies.md` for dependency groups. Show all
   dependencies without version filtering, with a note that some may be
   incompatible with the chosen Boot version.
2. Do not assume any boot version or java version defaults — ask the user to
   provide them manually.
3. Tell the user to check their network connection to `start.spring.io`.

## Interactive Configuration

Walk the user through project setup using `AskUserQuestion` at each step.
Show defaults clearly so the user can accept them quickly.

### Step 1 — Quick start or customize?

Construct the prompt dynamically from the fetched metadata. The defaults line
must show:
- Build: `Gradle-Kotlin` (opinionated preference)
- Language: `Kotlin` (opinionated preference)
- Boot: `{LATEST_STABLE_BOOT.display}` (from API)
- Java: `{JAVA_HIGHEST}` (from API)
- Packaging: `JAR` (opinionated preference)
- Config: `YAML` (opinionated preference)

Ask via `AskUserQuestion`:

```text
Spring Boot project setup.

Defaults: Gradle-Kotlin | Kotlin | Boot {LATEST_STABLE_BOOT.display} | Java {JAVA_HIGHEST} | JAR | YAML config

Accept all defaults or customize?
```

Options: "Use defaults", "Customize settings"

- **Use defaults** → skip to Step 4 (group/artifact).
- **Customize** → continue to Step 2.

### Step 2 — Build tool and language (customize only)

Derive the options from the API's `TYPES` (project types with
`tags.format == "project"`) and `LANGUAGES`.

Generate all sensible pairings from the API data. Mark `Gradle - Kotlin + Kotlin`
as `*(recommended)*`. Only include combinations where the language is idiomatic
for the build tool (e.g. Groovy language pairs with Gradle-Groovy, not
Gradle-Kotlin). Always derive from the live API — do not assume a fixed set.

Ask via `AskUserQuestion`:

```text
Select build tool and language:
```

Present the dynamically generated options list.

Map the selection to CLI flags:

| Choice prefix | `--type` | `--language` |
|---------------|----------|--------------|
| Gradle - Kotlin | `gradle-project-kotlin` | from selection |
| Gradle - Groovy | `gradle-project` | from selection |
| Maven | `maven-project` | from selection |

### Step 3 — Spring Boot version (customize only)

List versions from `BOOT_VERSIONS`, sorted: stable first, then milestones/RCs,
then snapshots. Annotate the latest stable and latest 3.x stable (if present).

Ask via `AskUserQuestion`:

```text
Select Spring Boot version:
```

Options (dynamically numbered from `BOOT_VERSIONS`):
```text
  1. {stable1} *(latest stable)*
  2. {stable2} *(latest 3.x stable)*    ← only if a 3.x stable exists
  3. {milestone1} *(milestone)*
  4. {snapshot1} *(snapshot)*
  ...
```

Default: `{LATEST_STABLE_BOOT.display}`. The user can also type a custom version string.

### Step 4 — Project coordinates

Always ask this, even on the defaults path. Derive the artifact default from the
current folder name (`basename "$(pwd -P)"`).

Use `{JAVA_HIGHEST}` from the API as the Java version default. Show all
available Java versions from `JAVA_VERSIONS` in the "Change Java version"
option.

Ask via `AskUserQuestion`:

```text
Project coordinates:

  Group:     com.giwankim
  Artifact:  {current-folder-name}
  Java:      {JAVA_HIGHEST}
  Packaging: JAR

Accept these or provide new values?
```

Options:
1. Accept defaults
2. Change group
3. Change artifact
4. Change Java version ({JAVA_VERSIONS joined by ", "})
5. Change packaging (WAR)
6. Change multiple

If the user selects "Change multiple" or types free-form text, parse key=value pairs
like `group=com.example, artifact=myapp, java=17`.

Before using the artifact name in any filesystem operation, validate it:
- Must match `^[A-Za-z0-9._-]+$` (alphanumeric, dots, underscores, dashes only)
- Must not be empty, `.`, or `..`
- Must not contain `/` or `\`

If invalid, re-prompt the user for a corrected artifact name.

### Step 4b — Check for existing project in target directory

After the artifact name is determined, check if `./<artifact>` already exists and
contains `build.gradle.kts`, `build.gradle`, `pom.xml`, or a `src/` directory.

If existing project files are found, ask via `AskUserQuestion`:

```text
Existing project files detected in ./<artifact>:
  - build.gradle.kts
  - src/

Continue, choose a different artifact name, or cancel?
```

Options: "Continue (delete and regenerate)", "Change artifact name", "Cancel"

- **Continue** → run `rm -rf -- "./<artifact>"` first, then generate fresh (no `--force` needed).
- **Change artifact name** → re-prompt for a new artifact name and re-check.
- **Cancel** → stop.

### Step 4c — Project layout

Always check this, even on the defaults path (defaults use Gradle-Kotlin, so
the subproject option applies whenever a Gradle root is present).

Check whether the generated project uses Gradle (type starts with `gradle-`).
Then check the current directory for an existing Gradle root by looking for
`settings.gradle.kts` or `settings.gradle` in `.` (the working directory, not
`./<artifact>`).

**If the generated project uses Gradle AND a Gradle root is detected**, ask via
`AskUserQuestion`:

```text
Existing Gradle root project detected (<settings-file>).

Create as:
```

Options: "Standalone project in ./<artifact>", "Subproject of root"

- **Standalone** → current behavior, generate into `./<artifact>` as a complete project.
- **Subproject** → generate into `./<artifact>`, then clean up and register as a
  Gradle module (see Post-Generation).

**Otherwise**, default to standalone and skip this question.

> **Note:** Maven subprojects are not supported. Maven multi-module requires the
> root POM to use `<packaging>pom</packaging>` (aggregator), which is incompatible
> with a runnable Boot application. Initializr-generated modules also inherit from
> `spring-boot-starter-parent`, and Maven allows only one `<parent>`, making
> automatic wiring infeasible without restructuring the root project.

### Step 4d — Config file format (customize path only)

Skip this step on the defaults path — YAML is already the default from Step 1.
Only ask this when the user chose "Customize settings" in Step 1.

Ask via `AskUserQuestion`:

```text
Application config format:

  Default: YAML (application.yaml)

Keep YAML or switch to Properties?
```

Options: "YAML (default)", "Properties"

- **YAML** → after generation, convert `application.properties` content to YAML syntax
  and write `application.yaml`, then remove the original `.properties` file (see Post-Generation).
- **Properties** → keep the generated file as-is.

### Step 5 — Dependency groups

Build the dependency group list dynamically from `DEP_GROUPS` (the API's
`dependencies.values[]` array). Each group has a `name` and nested `values[]`
of dependencies.

Before displaying, filter out any groups where all dependencies are incompatible
with the selected Boot version (check each dependency's `versionRange`).

Number groups sequentially and format in columns (3 columns, left-padded
numbers) to keep the prompt compact.

Ask via `AskUserQuestion`:

```text
Select dependency groups to browse (or type dependency IDs directly, e.g. web,data-jpa):

  1. {group1_name}      {N+1}. {groupN+1_name}      ...
  2. {group2_name}      {N+2}. {groupN+2_name}      ...
  ...

Type group numbers (e.g. 2,5,8), dependency IDs, or 'none':
```

For the quick-pick option suggestions, find the group numbers for "Web", "SQL",
and "Security" from the dynamic list and construct examples accordingly:

Options: "none (skip dependencies)", "{web},{sql} (Web + SQL)", "{web},{security},{sql} (Web + Security + SQL)"

Behavior:
- If the user types numbers → proceed to Step 6 for each selected group.
- If the user types dependency IDs directly (e.g. `web,data-jpa,postgresql`) → skip
  Step 6 and use those IDs directly.
- If the user types "none" → skip Step 6, no dependencies.

### Step 6 — Pick dependencies within each group

For each group selected in Step 5, present the dependencies from that group's
`values[]` array in the API response. Use the `name`, `id`, and `description`
from the API.

For the selected Boot version, filter out dependencies whose `versionRange`
excludes it.

Format each group as a numbered list showing the ID in parentheses:

```text
Select {group_name} dependencies:

  1. {dep1_name} ({dep1_id})
  2. {dep2_name} ({dep2_id})
  ...

Type numbers to include (e.g. 1,3) or 'none':
```

Parse comma-separated numbers and dash ranges (e.g. `1-3,5`). Collect all selected
dependency IDs across all groups.

For the **AI** group, which can contain 50+ dependencies, sub-categorize by
ID prefix pattern to keep the list navigable:
- **LLM Providers**: IDs matching `spring-ai-{provider}` that are not vectordb,
  embedding, chat-memory, document-reader, mcp, elevenlabs, stabilityai, or postgresml
- **Embeddings**: IDs containing `embedding`, `transformers`, or `postgresml`
- **Vector Databases**: IDs containing `vectordb`
- **Chat Memory**: IDs containing `chat-memory`
- **Document Readers**: IDs containing `document-reader`
- **Other**: everything else (mcp, elevenlabs, stabilityai, etc.)

Present sub-groups first, then drill into selected sub-groups. Hide sub-groups
with zero compatible dependencies.

If the heuristic produces confusing groupings, fall back to
`references/dependencies.md` for the AI sub-categorization.

### Step 7 — Confirmation

Show the full configuration summary using the actual values collected from all
prior steps, and the exact `spring init` command.

Ask via `AskUserQuestion`:

```text
Ready to generate project:

  Build:        {selected_type_display_name}
  Language:     {selected_language}
  Boot:         {selected_boot_version}
  Group:        {selected_group}
  Artifact:     {selected_artifact}
  Java:         {selected_java_version}
  Packaging:    {selected_packaging}
  Layout:       {Standalone | Subproject of root}
  Config:       {YAML (application.yaml) | Properties}
  Dependencies: {comma-separated dep IDs, or "none"}
  Target:       ./{selected_artifact}

Command:
  spring init --type {type} --language {language} \
    -b {bootVersion_id} -g {groupId} -a {artifactId} -n {artifactId} \
    -j {javaVersion} -p {packaging} -d {deps} {artifactId}

Proceed?
```

Options: "Generate project", "Go back and change settings", "Cancel"

- **Generate** → execute the command.
- **Go back** → restart from Step 1.
- **Cancel** → stop.

## Command Construction

Build the `spring init` command from the collected configuration:

```bash
spring init \
  --type <type> \
  --language <language> \
  -b <bootVersion-id> \
  -g <groupId> \
  -a <artifactId> \
  -n <artifactId> \
  -j <javaVersion> \
  -p <packaging> \
  -d <comma-separated-dep-ids> \
  <artifactId>
```

Important notes:
- Use the boot version's `id` field for `-b` (e.g. `4.0.5.RELEASE`, `4.1.0.M4`),
  not the display `name`. The API requires the full qualifier.
- Use `--type` (not `--build`) to distinguish Gradle-Kotlin from Gradle-Groovy.
- Omit `-d` entirely if no dependencies were selected.
- Passing a directory name as the target auto-extracts the archive (no `-x` needed).
- Set `-n` (project name) to the same value as `-a` (artifact).

## Post-Generation

After executing the `spring init` command:

1. **Verify the target directory exists.** If `./<artifact>` was not created,
   the command silently failed (`spring init` exits 0 even on server-side errors).
   Capture the full command output, tell the user the generation failed, suggest
   the most likely cause (dependency incompatible with the chosen Boot version),
   and offer to re-select dependencies or Boot version. If the failure seems
   related to a stale Spring CLI, suggest upgrading:
   `sdk install springboot {LATEST_STABLE_BOOT.display}`.

2. **CRITICAL — Convert `application.properties` to `application.yaml`.**
   DO NOT SKIP THIS STEP. This is the most commonly missed step in this skill.
   If the user chose YAML config (the default), convert before doing anything else:
   - Read `./<artifact>/src/main/resources/application.properties`
   - Convert properties to nested YAML (split keys on `.`, 2-space indent).
     For a freshly generated project, the file typically contains just
     `spring.application.name=<artifact>`:
     ```
     spring.application.name=demo  →  spring:
                                         application:
                                           name: demo
     ```
     For files with multiple entries, merge keys sharing a common prefix.
     Parse correctly: treat `=` or `:` as key-value separators, skip blank
     lines and comment lines (`#` or `!`), and quote values that YAML would
     misinterpret (`true`, `false`, `yes`, `no`, `on`, `off`, `null`, or
     bare numbers) by wrapping them in single quotes.
   - Write the result to `application.yaml` in the same directory.
   - Delete `application.properties`.
   - Do the same for `./<artifact>/src/test/resources/application.properties` if it exists.
   If the user explicitly chose Properties in Step 4d, skip this step.

3. **If subproject layout was chosen** (Gradle only), clean up and register the module:
   - Remove from `./<artifact>`: `gradlew`, `gradlew.bat`, `gradle/` directory,
     `settings.gradle.kts` (or `settings.gradle`), `HELP.md`, `.gitignore`, and
     `.gitattributes`.
   - Append `include("<artifact>")` to the root `settings.gradle.kts` (or
     `settings.gradle`), unless it already contains that include.
4. List the generated project structure: `find <target> -type f | head -30`.
5. **Verify project integrity:**
   - If Gradle-based and standalone layout, verify `./gradlew` exists and is
     executable in the target directory.
   - If YAML config was chosen, verify that `application.yaml` exists in
     `<artifact>/src/main/resources/` and that `application.properties` does NOT
     exist. If the conversion was missed, do it now before reporting success.
6. Report success with a summary of what was created.
7. Suggest next steps: `cd <artifact> && ./gradlew bootRun` (Gradle) or
   `cd <artifact> && ./mvnw spring-boot:run` (Maven). For subproject layout,
   suggest running from the root instead (e.g. `./gradlew :<artifact>:bootRun`).

## Edge Cases

- **Spring CLI not found**: Check `command -v spring`. If missing, suggest
  `sdk install springboot` and stop.
- **Stale Spring CLI**: If generation fails or produces unexpected results,
  suggest upgrading: `sdk install springboot <version>` where `<version>` is the
  `{LATEST_STABLE_BOOT.display}` from the API.
- **Existing project files in target**: Warn before proceeding. If user confirms,
  delete the target directory and regenerate fresh.
- **Network failure**: The `curl` to `start.spring.io` or `spring init` itself may
  fail. Follow the tiered fallback in Prerequisites step 3. If both `curl` and
  `spring init --list` fail, the service is likely down — use the fully offline
  path and suggest checking connectivity.
- **Invalid dependency IDs**: If `spring init` fails with an invalid dependency error,
  show the error message and re-prompt for corrected dependency selection.
