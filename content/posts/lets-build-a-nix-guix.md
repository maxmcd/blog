---
title: "Let's make a Nix/Guix"
date: 2020-06-19T01:29:25Z
draft: true
toc: false
images:
tags:
  - build
  - starlark
  - go
---


Let's create on ourself.

For each of use let's go with starlark for the config language. Starlark is a subset of python and
should hopefully be easy for others to learn.

We'll need to figure out how to build the seed. The first executable that will start building other libraries. We'll need a libc
and a compiler. glibc and clang

TODO look at seeds for guix/nix/others

Let's pick x and y.

Now let's make our first build, we're going to have to decide a few things right off the bat.

What does the scripting api look like
What does the input hashing look like
How do we make network calls and verify hashes

Explain nix derivations, hermes input hashing
(apologize for not knowing about guix)

We should sandbox but we can skip it for now


https://nixos.org/nix/manual/#ssec-derivation

> If the build was successful, Nix scans each output path for references to input paths by looking for the hash parts of the input paths. Since these are potential runtime dependencies, Nix registers them as dependencies of the output paths.


Build the thing, scan all the output paths for sources, mark them in gc.

Build a language from the seed

Build a program for the language
