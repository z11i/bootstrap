# Bootstrap

Run in Terminal on an Apple Silicon Mac:

```bash
/bin/bash -c "$(/usr/bin/curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/z11i/bootstrap/main/bootstrap.sh)"
```

Accept the Command Line Tools prompt if shown. When prompted, open
[github.com/login/device](https://github.com/login/device) on your phone and
enter the displayed code. Follow the remaining setup prompts.

To resume after the checkout exists:

```bash
cd ~/.dotfiles
./setup
~/.nix-profile/bin/gh auth setup-git --hostname github.com
```
