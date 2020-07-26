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

## A Quick Overview of Nix/Guix

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

## Let's Build One

We'll need to decide on a handful of things as we proceed to build a Nix.

1. A configuration language. Nix uses a purpose-built programming language that is also called Nix. Guix uses Scheme.
2. Once we have a language we'll need to figure out how build inputs are compute from these language files.
3. And once we have build inputs we'll need to figure out how we're going to run our builds.

From there we'll have many more small details to sort out, but those three things should get us to a pretty good position.

## Outline

- intro
- the language
- derivations, what are they and how do we make one
- language imports and pulling in requirements
- building the derivation and build outputs


## The Configuration Language

Each of these package managers use purely functional configuration languages to describe the packages that they're building. Here is the Python requests package described in Guix and in Nix:

Guix with the Scheme programming language
```scheme
(define-public python-requests-2.7
  (package (inherit python-requests)
    (version "2.7.0")
    (source (origin
             (method url-fetch)
             (uri (pypi-uri "requests" version))
             (sha256
              (base32
               "0gdr9dxm24amxpbyqpbh3lbwxc2i42hnqv50sigx568qssv3v2ir"))))))
```

Nix with the Nix programming language
```nix
buildPythonPackage rec {
  pname = "requests";
  version = "2.23.0";

  src = fetchPypi {
    inherit pname version;
    sha256 = "1rhpg0jb08v0gd7f19jjiwlcdnxpmqi1fhvw7r4s9avddi4kvx5k";
  };

  nativeBuildInputs = [ pytest ];
  propagatedBuildInputs = [ urllib3 idna chardet certifi ];
}
```

I'd like to use [Starlark](https://docs.bazel.build/versions/master/skylark/language.html) as our build language. While Starlark is not purely functional I think it should have enough isolation to have the same effect. Starlark is not turing complete (no infinite loops) and globals are not mutable. Build files should execute deterministically and not be impacted by the execution of other code. Starlark is also a subset of python's syntax, which I think should aide user adoption and ease-of-use.

Using Starlark, the build configuration for the python requests library might look something like this:

```python
name = "requests"
version = "2.23.0"
build_python_package(
  name=name,
  version=version,
  src=fetch_pypi(name, version, "1rhpg0jb08v0gd7f19jjiwlcdnxpmqi1fhvw7r4s9avddi4kvx5k"),
  dependencies=[urllib3, idna, chardet, certifi]
)
```


## Derivations

Now that we have our build language we need to work on the core build component of our build system. Our build system will need to download files from the internet, compile code, run various scripts and tests and create build outputs (among other things). Nix represents these things with something called a "derivation".

When the build script is initially parsed a derivation is calculated for each build target. This derivation roughly contains:
1. A derivation name
2. References to other derivations that this derivation depends on
3. A build script

This effectively breaks the build into three steps:
1. Parse all language files and their dependencies
2. Compute derivations
3. Build the derivations

This separation decouples language parsing and build, which leads to some nice isolation characteristics. Let's walk through a basic example to explain how that works.

```python
derivation(
    name="busybox_download",
    builder="fetch_url",
    environment={
        "decompress": True,
        "url": "$test_url/busybox.tar.gz",
        "hash": "8de53037d8e57daf5030be7c1c944afa849cf3a194962328ddb5478dbbb72533",
    },
)
```
Here is a very basic derivation. The derivation has a **name** that we can use to reference it and an **environment** which are the environment variables available at build time. The **builder** command is usually an executable that we're going to use to build, but in this case it's a builtin builder called "fetch_url" that simply fetches (and optionally unarchives) urls.

This is our first very basic derivation. The first thing we'll need to do is parse this starlark file and serialize our derivation. We'll [use a starlark function to define derivation](https://github.com/maxmcd/bramble/blob/e2a60085224f4f382aa2b2328001ba21ed75a90c/pkg/bramble/starlark.go#L145-L167). Once we parse it we [compute a hash for the filename](https://github.com/maxmcd/bramble/blob/e2a60085224f4f382aa2b2328001ba21ed75a90c/pkg/bramble/derivation.go#L109) and can view the resulting json:

```json
{
  "Name": "busybox_download",
  "Outputs": nil,
  "Builder": "fetch_url",
  "Platform": "",
  "Args": null,
  "Environment": {
    "decompress": "true",
    "hash": "8de53037d8e57daf5030be7c1c944afa849cf3a194962328ddb5478dbbb72533",
    "url": "$test_url/busybox.tar.gz"
  },
  "Sources": null,
  "InputDerivations": null
}
```

We [copy Nix here](https://github.com/maxmcd/bramble/blob/e2a60085224f4f382aa2b2328001ba21ed75a90c/pkg/bramble/hash.go#L32-L40) when computing the hash. We take the first 160 bits of a sha256 of the file contents and cast them to lowercase bas32. Hashing is an important step. By hashing this input we can check to see if we've built this derivation before.

At this point we [check for an existing derivation](https://github.com/maxmcd/bramble/blob/e2a60085224f4f382aa2b2328001ba21ed75a90c/pkg/bramble/client.go#L79) and if it doesn't exist we continue to building. In this case we'll simply [download the url](https://github.com/maxmcd/bramble/blob/e2a60085224f4f382aa2b2328001ba21ed75a90c/pkg/bramble/derivation.go#L216-L238) and unarchive it.

When we unarchive it we'll place the result along with our derivation in the nix store. We do this by first hashing the contents of the output file and then writing them to a directory with that name. In this case that ends up being `n6udgqwjyojfck7g5kckllmfebbuojqf-busybox_download`.

The next step is very important, we must take the output of the derivation and add it back to the derivation file, like so:
```json
  "Outputs": {
    "out": {
      "Path": "n6udgqwjyojfck7g5kckllmfebbuojqf-busybox_download",
      "Dependencies": null
    }
  },
```

We don't include this section when we hash the file, but we make sure to add it after we're done building. This allows future runs to find the corresponding build output when looking for the contents of this derivation.

To review:

1. We execute our starlark file and serialize our derivation into JSON
2. We hash this json and check to see if we've calculated this derivation before
3. If we haven't, we build the file and place its contents in a hashed folder
4. We write the output location to the derivation but exclude it from the hash calculation.

Phew, that's it, we've built out first derivation.

## Alternatives To A Derivation

It's worth pausing to discuss alternatives. Derivations break the build step into stages, and ensure that every build is serialized into a very simple json file. There are alternatives, we could just hash the starlark code and build directly, or we could just hash all of the input files and tag the result with that hash. Either of these should work pretty well. To me, the benefits of sticking with derivations are as follows:

1. Derivations are just json, we could calculate them in any language
2. No reliance on language version and implementation, if we make breaking changes to our starlark implementation we don't need to recompute all of our derivations

So I stuck with derivations for this tool, but I wonder what other patterns might work.

## The Seed/Stdenv

Now that we have our very basic derivation lets move onto the seed. This is a purely functional build system. We can't rely on the version of bash that's on your computer, or your libc or gcc. Everything we use to build must originate with the build system or we risk being able to build consistently on various systems.

As you might be able to imagine there's a bootstrapping problem here. If I need to build everything how do I build the first thing? Guix has a ["seed"](https://guix.gnu.org/blog/2020/guix-further-reduces-bootstrap-seed-to-25/) for this and Nix has a ["stdenv"](https://github.com/NixOS/nixpkgs/tree/master/pkgs/stdenv). At its core, these both get around the bootstrapping problem by downloading static binaries that have been compiled perviously. There are [interesting](https://bootstrappable.org/) [efforts](https://guix.gnu.org/blog/2020/guix-further-reduces-bootstrap-seed-to-25/) underway to reduce this seed to the smallest possible code to allow for more trivial auditing and to avoid the [trusting trust](http://users.ece.cmu.edu/~ganger/712.fall02/papers/p761-thompson.pdf) problem.

For our seed I simply borrowed Andrew Chambers [seed](https://github.com/andrewchambers/hpkgs-seeds/blob/master/linux-x86_64-seed.tar.gz) for [hermes](https://github.com/andrewchambers/hermes). Hermes is a simpler take on Nix and it uses Musl for its libc, making it a little more approachable for this project.

I won't discuss the seed much more (although I think it's a very interesting topic for a future post), the derivation for our seed is [here](https://github.com/maxmcd/bramble/blob/e2a60085224f4f382aa2b2328001ba21ed75a90c/seed.bramble).

## A More Complex Example

Now that we have a derivation, basic building and a seed we can move on to building a more complex program.

First, we'll implement relative imports:
```python
load("../seed", "seed")
```
There's a lot to improve in [this implementation](https://github.com/maxmcd/bramble/blob/e2a60085224f4f382aa2b2328001ba21ed75a90c/pkg/bramble/starlark.go#L169-L176) (and I'm hoping that eventually imports can be added for [remote packages](https://github.com/maxmcd/bramble/blob/e2a60085224f4f382aa2b2328001ba21ed75a90c/notes/initial-notes.md#imports-and-dependencies)), but this will work for now to tie a few derivations together.

Let's continue to borrow from Nix and attempt to recreate their example for a [working derivation](https://nixos.org/nixos/nix-pills/working-derivation.html). We'll try and compile the following C program, and explain the fascinating inner workings as we do.

Here's our program:
```c
void main() {
  puts("Simple!");
}
```

And here's the derivation to build it:
```python
load("../seed", "seed")
derivation(
    name="simple",
    environment={"seed": seed},
    builder="%s/bin/sh" % seed,
    args=["./simple_builder.sh"],
    sources=["./simple.c", "simple_builder.sh"],
)
```
We've added the **sources** attribute, which will track files that we'd like to include in the build. This time around we get to use a real build script. We use an instance of the Bourne Shell that's in our seed and a build script.
