# psysh

A lightweight plugin and theme manager for bash.  
Named after **ψ** — the wave function. Until a command returns, its state is unknown.

---

## Philosophy

Most shell setups are either bare `.bashrc` files held together with comments, or
framework monsters that fork a dozen processes before you type your first command.

psysh sits between those two things. It gives you a structured way to manage plugins
and themes without adding any startup overhead. When bash starts, psysh loads only
what you told it to load — directly from disk, no indirection.

The manager itself (`psy`) only runs when you call it. It never touches your shell
startup path beyond two lines in `.bashrc`.

---

## How it works

Three completely separate phases:

```
install.sh        → runs once, ever
    ↓
~/.bashrc         → two lines, never changes again
    ↓
every shell start → source psh.sh (load functions) → psysh_init (source enabled files)
    ↓
psy commands      → only when you call them
```

**Startup cost:** function definitions + reading two plain text files.  
Zero network. Zero forks. Zero filesystem writes.

---

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/awesomemad/psysh/main/install.sh | bash
```

That's it. It will:

- Create `~/.psysh/` directory structure
- Install the core runtime
- Ask for your GitHub username and optionally a token
- Write two lines to `~/.bashrc`

Then restart your shell or:

```bash
source ~/.bashrc
```

Verify everything landed:

```bash
psy doctor
```

---

## GitHub token

You only need a token for `psy upload` or if your registry is private.  
Public registry fetch and search work without any token.

If you need one:

- Type: **fine-grained PAT** (not classic)
- Repository access: your registry repo only
- Permissions:
  - `Contents` → Read and Write
  - `Metadata` → Read (required by default)

---

## Directory structure

```
~/.psysh/
    psh.sh              core runtime (loaded at startup)
    plugins/            *.sh plugin files
    themes/             *.sh theme files
    enabled_plugins     plain text list — one plugin name per line
    enabled_theme       plain text — single active theme name
    cache/
    logs/
```

`enabled_plugins` and `enabled_theme` are the only state psysh keeps.  
No database, no lockfile, no JSON. Just names.

---

## Commands

```
psy list                    show all installed plugins and themes with status
psy enable  <name>          enable a plugin or theme
psy disable <name>          disable a plugin or theme
psy info    <name>          show metadata for an installed component
psy create  <plugin|theme> <name>   scaffold a new component
psy fetch   <name>          download a single plugin or theme from the registry
psy search  <term>          search the registry without cloning it
psy upload  <name>          push a local component to the registry
psy reload                  re-source psh.sh and re-run psysh_init
psy doctor                  show environment diagnostics
```

---

## Dependencies

Dependencies are declared in the component metadata header and resolved automatically
when you run `psy enable`.

**Light deps** (fewer than 4, all under 137 logical lines) — auto-enabled silently:

```
  → pulled in dependency: matyx
enabled theme: philosopher
→ run 'psy reload' to apply
```

**Heavy deps** (4 or more, or any single dep over 137 logical lines) — you are asked first:

```
  Dependencies required:
    colors               142 logical lines
    utils                98 logical lines
    fonts                201 logical lines
    icons                88 logical lines

  Enable all of the above? [y/N]
```

**Missing deps** (not on disk) — hard stop with instructions:

```
psy: missing dependencies (not on disk):
    psy fetch colors
    psy fetch utils
```

The line count shown is **logical lines** — blank lines, comments, structural keywords
(`fi`, `done`, `esac`, `{`, `}` etc.) are excluded. A 300 line file that is mostly
comments counts as 30.

Thresholds are overridable:

```bash
export PSYSH_DEP_LINE_LIMIT=200
export PSYSH_DEP_COUNT_LIMIT=5
```

---

## Writing a plugin

```bash
psy create plugin myplugin
```

This scaffolds `~/.psysh/plugins/myplugin.sh` with the metadata headers pre-filled:

```bash
# psysh-name: myplugin
# psysh-type: plugin
# psysh-version: 0.1.0
# psysh-author: yourname
# psysh-description:
# psysh-dependencies:
# psysh-tags:
```

Fill in the headers, write your functions below them, done.

The headers are the contract. `psy info`, `psy list`, `psy enable`, and `psy upload`
all read from them. No separate manifest file, no external config. The file describes
itself.

**Dependencies** go in `psysh-dependencies` as a comma-separated list of component names:

```bash
# psysh-dependencies: matyx, colors
```

psysh will resolve and load them in the correct order — dependencies always before
the component that needs them. This is enforced both at `psy enable` time and at
`psysh_init` time on every shell start.

---

## Writing a theme

Same as a plugin but `psysh-type: theme`. Only one theme can be active at a time.
`psy enable` on a new theme replaces the current one.

A theme typically sets `PS1` or `PROMPT_COMMAND`. It can depend on plugins
(for color variables, git info helpers, etc.) using the same `psysh-dependencies` header.

---

## Environment variables

```bash
PSYSH_HOME              default: ~/.psysh
PSYSH_GITHUB_USER       your GitHub username
PSYSH_GITHUB_REPO       registry repo name     default: psysh-registry
PSYSH_GITHUB_BRANCH     registry branch        default: main
PSYSH_GITHUB_TOKEN      fine-grained PAT       optional
PSYSH_DEP_LINE_LIMIT    logical line threshold  default: 137
PSYSH_DEP_COUNT_LIMIT   dep count threshold     default: 4
```

Set any of these before running `install.sh` to skip the interactive prompts,
or export them in your `.bashrc` to override the installed defaults.

---

## The ψ symbol

The prompt indicator is ψ on success and ∅ on failure.

ψ is the wave function — until the command returns, the state is unknown.  
∅ is the empty set — not failure, just a path that produced nothing.

---

## License

Do whatever you want with it.
