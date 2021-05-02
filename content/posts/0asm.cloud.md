---
title: "0asm.cloud"
date: 2021-04-02T01:29:25Z
draft: false
toc: true
images:
tags:
  - wasm
---

Lately I've been thinking a lot about what a webassembly (WASM) cloud platform might look like. The regular cast of characters in a typical cloud environment: Servers, hypervisors, networks, load balancers, databases, containers, CDNs, container orchestration, filesystems. These things are sometimes mind-numbingly complicated, and interact in all sorts of interesting ways that would surely take many lifetimes to fully understand.

So let's brush everything off the table. Years of progress and utility and just dump it to the floor. We've got a brand new runtime with a minimal spec and its own quirks. Can we imagine something simple on top of this foundation that provides some of the utility of today with simpler primitives?

The following is an opinionated walk through a few options for this kind of platform, but it's not intended to constrain or perscribe the options here. Hopefully it's interesting food for thought.

<small>

_Every webassmbly binary starts with the magic byte string `0x00 0x61 0x73 0x6D` or `\0asm` which is where the "0asm" in 0asm.cloud comes from._

</small>

## The Basics

Let's say you go and read a webassembly tutorial, follow the steps, get excited about this new thing, and then at the end you're left with some running code and a `.wasm` binary. How do we go about running this thing on a server?

Out of the box, this is a bit hard. How do I start the binary running? How do I know when it's trying to print something? How do I provide environment variables and arguments? Webassembly allows you to define whatever function calls you want in your webassembly binary. We've got to agree on what those functions might look like to avoid creating lots of complexity out of the gate as various users of our platform reimplement these things in various ways.

[WASI](https://wasi.dev/) is a standard set of system calls intended to solve this problem. So let's pick that. That means we'll expect people to follow a webassembly tutorial that is WASI specific and their binary will expect the runtime environment to support the WASI system calls.

In our hypothetical cloud service we'll add a /create endpoint for uploading our WASI binary.

```bash
$ curl -X POST --data-binary @my-application.wasm \
    https://api.0asm.cloud/create?name=first_app
```

And another endpoint to run the binary, maybe it streams the log output:

```bash
$ curl -X POST https://api.0asm.cloud/run?name=first_app
Hello from inside 0asm.wasm
```

Now we have a cloud provider! It can't do much, I mean it can barely do anything, what are some other things it might do, what else might we want to add?

Think about these features, or think through your own. Do we want to add them? How would we do so?:

1. WASI takes args and env variables? How are those set, we do we configure them?
2. Our binary will have access to the filesystem, what files should live there, do they persist, are they shared at all?
3. Networking? WASI doesn't support network sockets yet, until it does, how do we talk to the internet and other webassembly friends?
4. Scale up/down, replicate? Do our wasm programs run like cloud functions one at a time? Do we have the concept of a long running process?
5. Persistence. What datastores are available? What kind of data persistence patterns might be useful here?
6. Logs/observability/metrics/debugging?

## The Filesystem

The Unix addage "everything is a file" seems like it might have utility here. The filesystem is one of the few mature interfaces we have access to here. WASI webassembly binaries can read and write and navigate to files all day.

## The Network

Living without sockets?

HTTP on the filesystem?

Remote system calls to other wasm apps

## The Runtime

Pausing and restarting. Long running tasks with queued requests.

## "Apps"

Other people upload their wasm binaries and you can use them too
