# sh

Small setup scripts for fresh Debian/Ubuntu servers, meant to be run through `curl`.

## zsh.sh

Installs zsh, makes it the login shell, and installs [`zshrc`](zshrc) as `~/.zshrc`.

```sh
curl -fsSL https://www.tbxark.com/sh/zsh.sh | sudo bash
```

- Installs zsh with `apt-get` when it is missing.
- Adds zsh to `/etc/shells` and switches the login shell of the target user
  (defaults to `$SUDO_USER`, falling back to `root`).
- Syntax-checks the new rc file with `zsh -n` before installing it, and backs up
  an existing `~/.zshrc` to `~/.zshrc.bak.<timestamp>`.
- Creates `~/.zshrc.local`, which `~/.zshrc` sources last and which the script
  never overwrites — put machine specific settings there.

Useful flags: `-y` (no prompt), `-n` (dry run), `-t <user>`, `-S` (do not change
the login shell), `-R` (keep the existing `~/.zshrc`), `-U <url>` / `-f <path>`
(use a different rc file). Run with `-h` for the full list.

## ssh.sh

Installs your GitHub public keys and disables password login.

```sh
curl -fsSL https://www.tbxark.com/sh/ssh.sh | sudo bash -s -- <github-user>
```

Keep your current SSH session open until you have verified key-based login from
a second terminal. Run with `-h` for the full list of options.

## zshrc

The rc file installed by `zsh.sh`: sane history and completion defaults,
emacs keybindings, history search on the arrow keys, a minimal prompt, and
`PATH` entries for go, cargo, bun, deno, pnpm, rye, snap and `~/.local/bin`
(each added only when the directory exists).
