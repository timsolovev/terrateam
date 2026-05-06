## Installation

This project uses [opam](https://opam.ocaml.org/) and [dune](https://dune.build/). If these
instructions go stale, [docker/terrat/Dockerfile](./docker/terrat/Dockerfile) is the canonical
reference — its `build-base` stage runs the same setup and is exercised by CI on every push.

Create a local opam switch from the repository's root:

```shell
opam switch create -y 5.3.0 --no-depexts
eval $(opam env)
```

Add the local `opam/` directory as an opam repository (it carries terrateam-specific packages
that aren't in the default opam-repository):

```shell
opam repository add tt-opam-acsl opam
```

Pin a couple of packages that need a specific version before the rest of the install can
solve cleanly:

```shell
opam pin add -y cmdliner 1.3.0
opam pin add -y containers 3.12
```

Install dune and menhir, then everything pinned in `code/opam.pins`:

```shell
opam install -j$(nproc --all) -y --no-depexts dune menhir
xargs -a code/opam.pins opam install -j$(nproc --all) -y --no-depexts
```

For an IDE-friendly setup, also install the LSP server and formatter:

```shell
opam install -y ocaml-lsp-server ocamlformat
```

You can now build:

```shell
cd code
make terrat        # builds terrat-oss/ee/ttm/code-indexer + iris UI assets
make test-terrat   # runs the test suite
```

Targets are also reachable directly via dune from the repository root:

```shell
dune build code/src/terrat_oss/terrat_oss.exe
dune runtest code/tests/
```

`dune-workspace` pins `(profile release)` as the default; pass `--profile dev`
or set `DUNE_PROFILE=dev` for a debug build.

Dune writes its merlin configuration as part of `dune build`, so VS Code / OCaml LSP work
out of the box once the switch is active (`eval $(opam env)`).
