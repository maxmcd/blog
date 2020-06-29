---
title: "Strategies for Binary Relocation In Functional Build Systems"
date: 2020-06-29T01:29:25Z
draft: false
toc: true
images:
tags:
  - build
  - bazel
  - nix
  - guix
---

I'm currently writing a toy Nix/Guix called [Bramble](github.com/maxmcd/bramble) to learn more about the inner workings of both systems. One of the features that I wanted to include in my version was "binary relocation".

Both Nix and Guix have hardcoded store paths that are baked into all the outputs that they produce. If we take a look at part of a [simple nix Derivation](https://gist.github.com/maxmcd/d98710a0e26daaff37c565da599f5d76) you'll see that these paths are hardcoded directly in the file. This is an important component of Nix. Instead of searching for the default shared libraries on a system nix-built binaries are patched to only include the specific libraries they depend on. This helps ensure correctness but also means that the binary must know exactly where to look for the shared lib. Hardcoding a library path to a fixed known location like `/nix/store/zqi5prhap0qh6r4nkghnibbmkgn7sczf-libogg-1.3.4/lib/` is an elegant way to get this done.

So what is binary relocation? If Nix supported binary relocation it would support moving Nix artifacts to a new location, somewhere that is not `/nix/store`. Generally, nix doesn't support this. You can take advantage of [workarounds](https://github.com/NixOS/nix/issues/1971#issuecomment-372542326) to fake it, but when nix is running it must think that `/nix/store` is the place to check for things.

So why do we want binary relocation? My simple answer is that I want Bramble to not require root access. If we want a user to be able to put their store in `/home/human/store` we'll need some way to rewrite that path for different users. Outside of that it would also provide future flexibility in the face of issues [like this one](https://github.com/NixOS/nix/issues/2925).

I'll outline the solutions to this problem that I've been able to find, and then summarize what I'm using for my system.

## Just use relative paths

I was originally very optimistic about this idea. All build outputs would expect to run from within the bramble store and if they needed a library they would point to the relative path of the library they need. Patching the [rpath](https://en.wikipedia.org/wiki/Rpath) of a binary with the $ORIGIN environment variable allows us to use this this strategy within executables.

Seemed like all I needed to do from here was be careful with my build scripts and ensure there were tools to help others easily write relative paths into their builds.

In practice I found this very difficult to do. This is apparently what Bazel does and there is some [interesting discussion about this problem](https://discourse.nixos.org/t/can-origin-be-used-to-make-nix-prebuilt-binaries-relocatable/2853/5).

Bazel is very opinionated and comes pre-baked with tools to build various languages. If I was writing a tool like that then this might very well be the best way to go. However, Bramble is intended to be like Nix, where end users are expected to write build scripts, and I couldn't figure out a easy way to execute on this without complicating even the simplest builds.


## Just re-patch everything

The [spack](https://github.com/spack/spack) build tool support binary relocation: https://spack.readthedocs.io/en/latest/binary_caches.html#relocation

You can read through the implementation [here](https://github.com/spack/spack/blob/f5467957bca49ca612cfc32710ed2ca8a943583d/lib/spack/spack/relocate.py). Spack just goes through and uses `pathelf` and `install_name_tool` to rewrite the applicable paths. This is interesting, and might work, but for the moment seems like it would miss various other paths within scripts or configuration. Spack mentions this:

> However, many packages compile paths into binary artifacts directly. In such cases, the build instructions of this package would need to be adjusted for better re-locatability.

This might be worth exploring at a later date, maybe testing against various packages as they're build. For the moment it seems like a non-starter because of the difficulties of trivially replacing paths that are not in binaries.

## Pad the path

One interesting observation here https://github.com/NixOS/nix/issues/1971 what that `/nix/store/` and `/tmp/foo///` are both valid paths of the same length. If you could guarantee that your path was always shorter than a certain length you could just pad the location with slashes. Or, if the path is longer, you could store everything in a short path symlink the the longer path to that path.

This is roughly the solution I ended up going with. Instead of using something like `/nix/store` I would assume the user can install their store within their home directory. The path would then be something like `/home/maxm/.bramble/store` or `/Users/maxm/.bramble/store/` for macOS. Now, instead of using "store" we rename that folder so that the length of the path is always the same. Here are some examples:

```bash
/home/maxm/.bramble/soooooooooooooooooooooooooooo/
/Users/maxm/.bramble/sooooooooooooooooooooooooooo/

# Linux/OpenBSD usernames can't be longer than 32 characters
/home/00000000001111111111000000000011/.bramble/s/
# Darwin/macOS has a limit of 20
/Users/00000000001111111111/.bramble/sooooooooooo/
```

This way, the path length is always the same, so it's easy for us to find it within build outputs and patch it to be something else. Changing a users username or changing the store location will now mean all build outputs need to be patched, but there is at least a clear path to do so.

## Summary

I'm going to try out this path padding thing. Part of the reason I wrote up this post is because this feels like a ridiculous direction to go down. What do you think? Are there ways to get binary relocation that I'm missing? Should I spend more time on relative paths and re-patching? Are there pieces here I'm not thinking about?
