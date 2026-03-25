---
name: spring-init
version: 0.2.0
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

1. Verify the `spring` CLI is available by running `command -v spring`.
   If missing, tell the user: "Spring CLI not found. Install via `sdk install springboot`."
   and stop.
2. Fetch the live dependency catalog by running `spring init --list`. Parse the
   output table to extract dependency IDs, descriptions, and version constraints
   (the "Required version" column). Keep this data for use in Steps 5–6.
   If the command fails (network error), fall back to the static catalog in
   `references/dependencies.md`.

## Interactive Configuration

Walk the user through project setup using `AskUserQuestion` at each step.
Show defaults clearly so the user can accept them quickly.

### Step 1 — Quick start or customize?

Ask via `AskUserQuestion`:

```text
Spring Boot project setup.

Defaults: Gradle-Kotlin | Kotlin | Boot 4.0.4 | Java 25 | JAR | YAML config

Accept all defaults or customize?
```

Options: "Use defaults", "Customize settings"

- **Use defaults** → skip to Step 4 (group/artifact).
- **Customize** → continue to Step 2.

### Step 2 — Build tool and language (customize only)

Ask via `AskUserQuestion`:

```text
Select build tool and language:
```

Options:
1. Gradle - Kotlin + Kotlin *(recommended)*
2. Gradle - Kotlin + Java
3. Gradle - Groovy + Java
4. Gradle - Groovy + Groovy
5. Maven + Java
6. Maven + Kotlin

Map the selection to CLI flags:

| Choice prefix | `--type` | `--language` |
|---------------|----------|--------------|
| Gradle - Kotlin | `gradle-project-kotlin` | from selection |
| Gradle - Groovy | `gradle-project` | from selection |
| Maven | `maven-project` | from selection |

### Step 3 — Spring Boot version (customize only)

Ask via `AskUserQuestion`:

```text
Select Spring Boot version:
```

Options (stable versions first):
1. 4.0.4 *(latest stable)*
2. 3.5.12 *(latest 3.x stable)*
3. 4.1.0-M3 *(milestone)*
4. 4.0.5-SNAPSHOT
5. 4.1.0-SNAPSHOT

Default: 4.0.4. The user can also type a custom version.

### Step 4 — Project coordinates

Always ask this, even on the defaults path. Derive the artifact default from the
current folder name (`basename "$(pwd)"`).

Ask via `AskUserQuestion`:

```text
Project coordinates:

  Group:     com.giwankim
  Artifact:  <current-folder-name>
  Java:      25
  Packaging: JAR

Accept these or provide new values?
```

Options:
1. Accept defaults
2. Change group
3. Change artifact
4. Change Java version (17, 21, 25)
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

### Step 4d — Config file format

Always ask this, even on the defaults path.

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

Present numbered dependency groups. Read the group structure from
`references/dependencies.md` in this skill's directory.

Cross-reference each group's dependencies against the live catalog fetched in
Prerequisites. For the selected Boot version, hide dependencies whose version
constraint excludes it. If a dependency from `dependencies.md` doesn't appear
in the live catalog, omit it (removed upstream). If the live fetch failed,
show all dependencies with a note that some may be version-specific.

Ask via `AskUserQuestion`:

```text
Select dependency groups to browse (or type dependency IDs directly, e.g. web,data-jpa):

  1. Developer Tools      8. I/O                  15. Spring Cloud Routing
  2. Web                  9. Ops                  16. Spring Cloud Circuit Breaker
  3. Template Engines    10. Observability         17. Spring Cloud Messaging
  4. Security            11. Testing              18. VMware Tanzu
  5. SQL                 12. Spring Cloud          19. AI
  6. NoSQL               13. Spring Cloud Config   20. Microsoft Azure
  7. Messaging           14. Spring Cloud Discovery 21. Google Cloud

Type group numbers (e.g. 2,5,8), dependency IDs, or 'none':
```

Options: "none (skip dependencies)", "2,5 (Web + SQL)", "2,4,5 (Web + Security + SQL)"

Behavior:
- If the user types numbers → proceed to Step 6 for each selected group.
- If the user types dependency IDs directly (e.g. `web,data-jpa,postgresql`) → skip
  Step 6 and use those IDs directly.
- If the user types "none" → skip Step 6, no dependencies.

### Step 6 — Pick dependencies within each group

For each group selected in Step 5, present the dependencies from that group using
`AskUserQuestion`. Use the description from the live catalog when available
(fresher than the static reference). Read group membership from `references/dependencies.md`.

Format each group as a numbered list showing the ID in parentheses:

```text
Select Web dependencies:

  1. Spring Web (web)
  2. Spring Reactive Web (webflux)
  3. HTTP Client (spring-restclient)
  ...

Type numbers to include (e.g. 1,3) or 'none':
```

Parse comma-separated numbers and dash ranges (e.g. `1-3,5`). Collect all selected
dependency IDs across all groups.

For the **AI** group, which is very large, sub-categorize by presenting sub-groups
first (LLM Providers, Embeddings, Vector Databases, Chat Memory, Document Readers, Other), then
drill into selected sub-groups.

### Step 7 — Confirmation

Show the full configuration summary and the exact `spring init` command.

Ask via `AskUserQuestion`:

```text
Ready to generate project:

  Build:        Gradle - Kotlin
  Language:     Kotlin
  Boot:         4.0.4
  Group:        com.giwankim
  Artifact:     <artifact>
  Java:         25
  Packaging:    JAR
  Layout:       Standalone | Subproject of root
  Config:       YAML (application.yaml)
  Dependencies: web, data-jpa, postgresql
  Target:       ./<artifact>

Command:
  spring init --type gradle-project-kotlin --language kotlin \
    -b 4.0.4 -g com.giwankim -a <artifact> -n <artifact> \
    -j 25 -p jar -d web,data-jpa,postgresql <artifact>

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
  -b <bootVersion> \
  -g <groupId> \
  -a <artifactId> \
  -n <artifactId> \
  -j <javaVersion> \
  -p <packaging> \
  -d <comma-separated-dep-ids> \
  <artifactId>
```

Important notes:
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
   and offer to re-select dependencies or Boot version.
2. **If subproject layout was chosen** (Gradle only), clean up and register the module:
   - Remove from `./<artifact>`: `gradlew`, `gradlew.bat`, `gradle/` directory,
     `settings.gradle.kts` (or `settings.gradle`), and `HELP.md`.
   - Append `include("<artifact>")` to the root `settings.gradle.kts` (or
     `settings.gradle`), unless it already contains that include.

3. **Convert config format if YAML was chosen.** For each `application.properties`
   file in `./<artifact>/src/main/resources/` and `./<artifact>/src/test/resources/`
   (if the file exists):
   - Read the file contents.
   - Parse `.properties` lines correctly: treat `=` or `:` as key-value separators,
     skip blank lines and comment lines (starting with `#` or `!`), and handle
     backslash line continuations if present.
   - Split parsed keys on `.` to produce nested YAML with 2-space indentation.
     Merge keys that share a common prefix. Quote values that YAML would
     misinterpret as non-string types (e.g. `true`, `false`, `yes`, `no`, `on`,
     `off`, `null`, or bare numbers) by wrapping them in single quotes.
     For example, `spring.application.name=demo` becomes:
     ```yaml
     spring:
       application:
         name: demo
     ```
   - Write the converted content to `application.yaml` in the same directory.
   - Delete the original `application.properties`.
4. List the generated project structure: `find <target> -type f | head -30`.
5. If Gradle-based and standalone layout, verify `./gradlew` exists and is executable
   in the target directory.
6. Report success with a summary of what was created.
7. Suggest next steps: `cd <artifact> && ./gradlew bootRun` (Gradle) or
   `cd <artifact> && ./mvnw spring-boot:run` (Maven). For subproject layout,
   suggest running from the root instead (e.g. `./gradlew :<artifact>:bootRun`).

## Edge Cases

- **Spring CLI not found**: Check `command -v spring`. If missing, suggest
  `sdk install springboot` and stop.
- **Existing project files in target**: Warn before proceeding. If user confirms,
  delete the target directory and regenerate fresh.
- **Network failure**: `spring init` calls `start.spring.io`. On failure, suggest
  checking internet connectivity.
- **Invalid dependency IDs**: If `spring init` fails with an invalid dependency error,
  show the error message and re-prompt for corrected dependency selection.
