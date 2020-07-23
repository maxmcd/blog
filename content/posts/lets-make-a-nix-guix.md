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
