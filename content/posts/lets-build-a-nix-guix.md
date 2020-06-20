---
title: "Let's make a Nix/Guix"
date: 2020-06-19T01:29:25Z
draft: false
toc: false
images:
tags:
  - build
  - starlark
  - go
---

# What are Nix and Guix

Nix (and the more recent Guix) are package managers that: 

> [utilize] a purely functional deployment model where software is installed into unique directories generated through cryptographic hashes

Both package managers use a purely functional programming language to describe how to build dependencies, build the depedency in a sandbox, and assign the output a cryptographic hash. When other dependencies need to rely on that dependency they don't say "I need ruby-2.7.1" they say "I need [INSERT RUBY NIX STORE PATH HERE]".  


Let's see this idea in practice. On a normal system you might install X which relis on ruby-2.7. You run `install X` and the package manager will download ruby-2.7 and your depdency. The dependency works and everyone is happy. Next you want to download Y. You download Y and run it. It fails to run with the following error:

```
something cryptic in ruby land
```

You realize that this software can't run with ruby 2.7 yet. You open up an issue on the projects github page, hope for a resolution one day and move on to using RVM or Docker to solve your problem. 


Nix has a solution to this issue. You run `nix-env -iA nixpkgs.X` and `nix-env -iA nixpkgs.Y` and it downloads the following dependencies:

```
sadfsadf-X
asdfsafa-Y
asfasdff-ruby-2.5
asffsasd-ruby-2.7
```

Two versions of ruby right on your system. When you run X it uses 2.7 and when you run Y it uses 2.5. Essentially you solve the issue of [dependency hell](https://en.wikipedia.org/wiki/Dependency_hell) at the cost of some additional disk space. 

As you can imagine, this strategy is used throughout Nix. When you use nix to build software, you point at the hashes of the dependencies you need to build and your build output is assigned its own hash. Builds are sandboxed and you must point to every dependency you need to execute the build. This means we can start building on the assumptions of this system. "This is exactly the software I need to build, this is exactly the software I need to run, and exactly these versions with this hash". It starts to mean that if it "works on your computer" it probably works on my computer as well and we stroll towards the wonderful land of [reporduceable builds](https://en.wikipedia.org/wiki/Reproducible_builds). [LEAVE NOTE ABOUT NIX NOT BEING REPRODUCEABLE] [MAYBE THIS SENTENCE IS BAD] 

## Let's build one



Each of these package managers use purely functonal configuration languages to For each of use let's go  with starlark for the config language. Starlark is a subset of python and
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
