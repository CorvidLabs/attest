# Demo

The animated demo in the README and on the site is generated from these two files,
so anyone can reproduce it from scratch:

- `setup.sh` builds a throwaway git repo (`/tmp/demo-attest` by default) with one
  commit, a `release.json` policy (signature + passing tests required), and ensures
  a signing key exists.
- `demo.tape` is a [VHS](https://github.com/charmbracelet/vhs) script that records
  `attest sign` -> `attest log` -> `attest verify` as a GIF.

## Regenerate

```sh
brew install corvidlabs/tap/attest charmbracelet/tap/vhs
./demo/setup.sh
vhs demo/demo.tape
mv demo.gif site/public/demo.gif
```

The GIF is served from `site/public/demo.gif` (the site and the README both point at it).
