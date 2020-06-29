---
title: "Let's make a Nix/Guix"
date: 2020-06-19T01:29:25Z
draft: false
toc: true
images:
tags:
  - build
  - starlark
  - go
  - nix
  - guix
  - hermes
---

[Nix](https://nixos.org/) (and the more recently created [GNU Guix](https://guix.gnu.org/)) are functional package managers. I've used NixOS for some time now and have thoroughly enjoyed using it. I was inspired by Andrew Chamber's recently launched [hermes](https://acha.ninja/blog/introducing_hermes/) to try implementing a simple version of Nix using Go and [Starlark](https://docs.bazel.build/versions/master/skylark/language.html).

## A quick overview of Nix/Guix

Nix and Guix are package managers that "utilize a purely functional deployment model where software is installed into unique directories generated through cryptographic hashes."[^1]

Let's dig into that description with a quick example. We'll pretend we're trying to install two libraries "Blue" and "Green" that require ruby to run. On a normal system you might first install Blue which relies on ruby-2.6.5. You run `install Blue` and the package manager downloads ruby-2.6.5 for you along with your dependency. The dependency works and everyone is happy.

Next you go to download Green and it fails with the following error:
```
Resolving dependencies...
green requires ruby version >= 2.0, < 2.6, which is
incompatible with the current version, ruby 2.6.5
```
You realize that this software can't run with ruby 2.6.5 yet. You file a bug with the project, hope for a resolution one day and move on to thinking about downgrading ruby or using RVM to solve your problem.

Nix has a solution to this issue. You run `nix-env -iA nixpkgs.blue` and `nix-env -iA nixpkgs.green` and it downloads the following assets (folders with hashes in their names):

```
12a7h4w68f96j56kzwxxpxbc4zq7n76p-ruby-2.6.5
bqrxcg5a9hv5gb6527vmsay871fi22qv-blue-1.7.8
mxaxvp33wg9sim8qh2kkw041v492bvxj-green-0.9.10
94544v143cpp17s7kl6g9y39x2a09k51-ruby-2.5.7
```

Two versions of ruby right on your system. When you run Blue it knows to use the ruby in folder 12a7h4w68f96j56kzwxxpxbc4zq7n76p-ruby-2.6.5 and when you run Green it uses 94544v143cpp17s7kl6g9y39x2a09k51-ruby-2.5.7. Essentially you solve the issue of [dependency hell](https://en.wikipedia.org/wiki/Dependency_hell) at the cost of some additional disk space.

Expanding from this basic idea, you can think about how this strategy is used throughout Nix. Every piece of software built with Nix outputs a hashed folder (or [folders](https://nixos.org/nixos/nix-pills/our-first-derivation.html#idm140737320470112)). When a piece of software is run it uses the specific folders it relies on. If you want to build a new piece of software you point to certain hashed folders to build the dependency and other hashed folders to use as runtime dependencies.

This allows users of Nix to ask some pretty wild things of its system:

1. Delete all the dependencies I'm not using
2. Roll back my entire system to a previous set of dependencies
3. Delete all the build dependencies I just downloaded but keep the dependencies my applications need

Additionally, because inputs, outputs and the running environment are known, it's easy to build things in advance, cache them, and just let the user download the resulting build files. This is what happens when you run `nix-env -iA nixpkgs.ruby`, the Nix build script likely builds ruby from source with dozens of build-time dependencies, but as an end user I just need the build result.

## Let's build one

Each of these package managers use purely functional configuration languages to For each of use let's go  with starlark for the config language. Starlark is a subset of python and
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

[^1]: https://en.wikipedia.org/wiki/Nix_package_manager
