---
title: "Bramble: A Purely Functional Build System and Package Manager"
date: 2021-11-14T21:21:13
draft: false
toc: true
images:
tags:
  - nix
  - starlark
  - go
---
![](https://github.com/maxmcd/bramble/raw/main/notes/animated.svg)

About a year and a half ago I decided to start working on a build system inspired by Nix called [Bramble](https://github.com/maxmcd/bramble). Andrew Chambers had launched [hermes](https://github.com/andrewchambers/hermes) and I was messing around with [starlark-go](https://github.com/google/starlark-go) a bit and it seemed like writing a Nix-inspired functional build system with Starlark would be a nice way to better understand how they work.

Bramble is no longer a test project, and has matured into something that I think has a few interesting ideas worth sharing.

## What is it in a few sentences?

Bramble is a work-in-progress functional build system inspired by Nix. It intends to be a user-friendly, robust, and reliable way to build software. It is reproducible, rootless, daemonless, proactively-sandboxed, project-based, and extremely cacheable (more on all that [here](https://github.com/maxmcd/bramble#readme)).

Unlike traditional package managers Bramble does not intend to maintain a core set of packages. Similarly to Go, Bramble packages are just version control repositories. More `npm i` than `apt-get`.

The project is still very rough around the edges. If you try using it it will likely break in some marvelous and unexpected ways.

## How do I use it?

[Installation instructions](https://github.com/maxmcd/bramble#installation) and a [hello world](https://github.com/maxmcd/bramble#hello-world) are available in the project readme.

Most Bramble functionality will not work unless Bramble is run from within a project. A project has a `bramble.toml` where the package name and version are configured along with any dependencies. A `bramble.lock` is used to track various metadata for reproducibility.

Here is Bramble's bramble.toml:

```toml
[package]
name = "github.com/maxmcd/bramble"
version = "0.0.2"

[dependencies]
"github.com/maxmcd/busybox" = "0.0.2"
```

Once you have a project you'll add files that end with `.bramble`, and fill them with a language that looks like Python, but [it's not](https://github.com/google/starlark-go/blob/master/doc/spec.md).

Here's some example code:
```python
load("github.com/maxmcd/bramble/tests/simple/simple")
load(seed="github.com/maxmcd/bramble/lib/nix-seed")

def print_simple():
    return run(simple.simple(), "simple", hidden_paths=["/"])

def bash():
    return run(seed.stdenv(), "bash", read_only_paths=["./"])
```

If I configured the dependencies and added that code to a file called `example.bramble` I could do the following:

```
$ bramble run ./example:bash
bramble path directory doesn't exist, creating
✔ busybox-x86_64.tar.gz - 394.546982ms
✔ busybox - 85.373221ms
✔ url_fetcher.tar.gz - 506.919852ms
✔ url_fetcher - 45.844013ms
✔ busybox-x86_64.tar.gz - 352.000704ms
✔ patch_dl - 416.00372ms
✔ patchelf - 28.538933ms
✔ patchelf-0.13.tar.bz2 - 722.859392ms
✔ bootstrap-tools.tar.xz - 3.499340974s
✔ stdenv - 1.602750216s

$ ls
bramble.toml bramble.lock  example.bramble

$ touch foo
touch: cannot touch 'foo': Read-only file system
```

Here Bramble is building the necessary dependencies to run `bash`. Once that's done `bash` is run but with a read-only view of the project filesystem. The `bash` process is also sandboxed from the rest of the filesystem by default, and can only read files within the project.

Once a project is set up you can also run a remote package and it will be added to the project as a dependency. Running `bramble run github.com/maxmcd/busybox:busybox ash` in a new project fetches the `github.com/maxmcd/busybox` from a remote cache, adds it as a dependency to `bramble.toml` and runs the `ash` executable in a sandbox.

## How is it different from Nix?

- Starlark is used as a config language instead of the Nix language.
- Project-based, no central package tree.
- No central daemon or root privileges needed to run.
- Very limited build inputs. No env-var, arguments, or other inputs allowed for build configuration. Almost all configuration must be done in-code.
- No network access in builds outside of the built-in fetchers. Networked builds will be supported, but they'll need to write incremental state to `bramble.lock` so that subsequent builds don't need network access.
- `/nix/store` is hardcoded in many Nix derivations, Bramble allows build outputs to be patched so that they can be relocated to stores at different locations. Computed hashes are also "store path agnostic" and hashes will match on different systems even if the store location is different.
- Derivations are required to be reproducible. This assumption reduces the complexity of the build logic, but also means Bramble can be harder to work with.
- Nix is mature software, Bramble is not.

## What's next?

A few things:

- Lots of bugs to fix. The spec needs to be completed and all the related functionality implemented.
- I'm hoping to build better documentation and testable documentation similar to Rust's. You can preview the documentation support a little bit today with the [`bramble ls`](https://github.com/maxmcd/bramble#bramble-ls) command.
- First-class support for building Docker/OCI containers from build outputs. Also remote build support for a variety of systems.
- macOS support.
- Dependency/package management is roughly implemented, but will need more work to make it usable.
- Lots more, hopefully.

That's it, very interested in your thoughts.

