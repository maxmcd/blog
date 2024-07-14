---
title: "Can We Improve Process Per Request Performance in Node"
date: 2024-07-12T00:00:00
draft: false
toc: true
images: []
tags:
  - node
  - js
  - performance
  - bun
  - go
  - deno
---

<style>
    table code {
        /* font-size: 14px; */
        background-color: initial;
    }
    table td, table th {
        padding: 0.5rem;
    }
</style>

How fast can an HTTP server in Node run if we spawn a process for every request?

```js
import { spawn } from "node:child_process";
import http from "node:http";
http
.createServer((req, res) => spawn("echo", ["hi"]).stdout.pipe(res))
.listen(8001);
```

You should avoid spawning a new process for every HTTP request if at all
possible. Creating a new process or thread is expensive and could easily become
your core bottleneck. At [Val Town](https://val.town) there are many request
types where we spawn a new process to handle the request. While we're working to
reduce this, it is likely that we'll always have some requests that spawn a
process, and we'd like them to be fast.

When under load, a single one of Val Town's Node servers cannot exceed 40 req/s
and it spends 30% of the time blocked on calls to `spawn`. Why is it so slow?
Can we make it any faster?

Let's write up some baseline examples and run them in Node, Deno, Bun, Go, and
Rust and see how fast we can get them.

I am running all of these on a Hetzner CCX33 with 8 vCPUs and 32 GB of ram. I am
benchmarking with [bombardier](https://github.com/codesenberg/bombardier)
running on the same machine. The command I'll run to benchmark each server is
`bombardier -c 30 -n 10000 http://localhost:8001`. 10,000 total requests over 30
connections. I prewarm each server before running the benchmark.

Each implementation will run an HTTP server, spawn `echo hi` for each request,
and respond with the stdout of the command. The Node/Bun/Deno server source is
at the beginning of this post. The Go source is
[here](https://github.com/maxmcd/process-per-request/blob/fb2f5f9518d62f058f7e587580c302b56f7a5781/go/main.go)
and the Rust source is
[here](https://github.com/maxmcd/process-per-request/blob/0a6442f656fe7bc8f6c61ef2c5fdef65c6afa0f1/rust/src/main.rs).

Here are the results:

| Language/Runtime | Req/s | Command                            |
| ---------------- | ----- | ---------------------------------- |
| Node             | 651   | `node baseline.js`                 |
| Deno             | 2,290 | `deno run --allow-all baseline.js` |
| Bun              | 2,208 | `bun run baseline.js`              |
| Go               | 5,227 | `go run go/main.go`                |
| Rust (tokio)     | 5,466 | `cd rust && cargo run --release`   |

Ok, so Node is slow. Deno and Bun have figured out how to make this faster, and
the compiled, thread-pool languages are much faster again.

Node's `spawn` performance does seem to be notably bad. [This
thread](https://github.com/node/node/issues/14917) was an interesting read,
and while in my testing things have improved since the time of that post, Node
still spends an awful lot of time blocking the main thread for each Spawn call.

Switching to Bun or Deno would improve this a lot. That is great to know, but
let's try and improve things with Node.

## Node `cluster` Module

The simplest thing we can do spawn more processes and run an http server
per-process using Node's `cluster` module. Like so:

```js
import { spawn } from "node:child_process";
import http from "node:http";
import cluster from "node:cluster";
import { availableParallelism } from "node:os";

if (cluster.isPrimary) {
  for (let i = 0; i < availableParallelism(); i++) cluster.fork();
} else {
  http
    .createServer((req, res) => spawn("echo", ["hi"]).stdout.pipe(res))
    .listen(8001);
}
```

Node shares the network socket between processes here, so all of our processes
can listen on `:8001` and they'll be routed requests round-robin.

The main issue with this approach for me is that each HTTP server is isolated in
it's own process. This can complicate things if you manage any kind of in-memory
caching or global state that needs to be shared between these processes. I'd
ideally find a way to keep the single thread execution model of javascript and
still make spawns fast.

Here are the results:

| Language/Runtime | Req/s | Command                                      |
| ---------------- | ----- | -------------------------------------------- |
| Node             | 1,766 | `node cluster.js`                            |
| Deno             | 2,133 | `deno run --allow-all cluster.js`            |
| Bun              | n/a   | "node:cluster is not yet implemented in Bun" |

Super weird. Deno is slower, Bun doesn't work just yet, and Node has improved
a lot, but I would have expected it to be even faster.

Nice to know there is some speedup here. We'll move on from it for now.

## Move The Spawn Calls To Worker Threads

If the `spawn` calls are blocking the main thread, let's move them to worker
threads.

Here's our `worker-threads/worker.js` code. We listen for messages with a
command and an id. We run it and post the result back. We're using `execFile`
here for convenience, but it is just an abstraction on top of `spawn`.

```js
import { execFile } from "node:child_process";
import { parentPort } from "node:worker_threads";

parentPort.on("message", (message) => {
  const [id, cmd, ...args] = message;

  execFile(cmd, args, (_error, stdout, _stderr) => {
    parentPort.postMessage([id, stdout]);
  });
});
```

And here's our `worker-threads/index.js`. We create 8 worker threads. When we
want to handle a request we send a message to a thread to make the spawn call
and send back the output. Once we get the response back, we respond to the http
request.

```js
import assert from "node:assert";
import http from "node:http";
import { EventEmitter } from "node:events";
import { Worker } from "node:worker_threads";

const newWorker = () => {
  const worker = new Worker("./worker-threads/worker.js");
  const ee = new EventEmitter();
  // Emit messages from the worker to the EventEmitter by id.
  worker.on("message", ([id, msg]) => ee.emit(id, msg));
  return { worker, ee };
};

// Spawn 8 worker threads.
const workers = Array.from({ length: 8 }, newWorker);
const randomWorker = () => workers[Math.floor(Math.random() * workers.length)];

const spawnInWorker = async () => {
  const worker = randomWorker();
  const id = Math.random();
  // Send and wait for our response.
  worker.worker.postMessage([id, "echo", "hi"]);
  return new Promise((resolve) => {
    worker.ee.once(id, (msg) => {
      resolve(msg);
    });
  });
};

http
  .createServer(async (_, res) => {
    let resp = await spawnInWorker();
    assert.equal(resp, "hi\n"); // no cheating!
    res.end(resp);
  })
  .listen(8001);
```

Results!:

| Language/Runtime | Req/s | Command                                        |
| ---------------- | ----- | ---------------------------------------------- |
| Node             | 426   | `node worker-threads/index.js`                 |
| Deno             | 3,601 | `deno run --allow-all worker-threads/index.js` |
| Bun              | 2,898 | `bun run worker-threads/index.js`              |

Node is slower! Ok, so presumably we are not bypassing Node's bottleneck by
using threads. So we're doing the same work with the added overhead of
coordinating with the worker threads. Bummer.

Deno loves this, and Bun likes it a little more. Generally, it's nice to see
that Bun and Deno don't see much of an improvement here and they're already
doing a good job of keeping the sycall overhead off of the execution thread.

Onward.

## Move Spawn Calls to Child Processes

If threads are not going to work, let's use child processes to do the work.

This is quite easy. We simply swap out the worker threads for processes spawned
by `child_process.fork` and change how we send and receive messages.

```diff
$ git diff --unified=1 --no-index ./worker-threads/ ./child-process/
diff --git a/./worker-threads/index.js b/./child-process/index.js
index 52a93fe..0ed206e 100644
--- a/./worker-threads/index.js
+++ b/./child-process/index.js
@@ -3,6 +3,6 @@ import http from "node:http";
 import { EventEmitter } from "node:events";
-import { Worker } from "node:worker_threads";
+import { fork } from "node:child_process";

 const newWorker = () => {
-  const worker = new Worker("./worker-threads/worker.js");
+  const worker = fork("./child-process/worker.js");
   const ee = new EventEmitter();
@@ -21,3 +21,3 @@ const spawnInWorker = async () => {
   // Send and wait for our response.
-  worker.worker.postMessage([id, "echo", "hi"]);
+  worker.worker.send([id, "echo", "hi"]);
   return new Promise((resolve) => {
diff --git a/./worker-threads/worker.js b/./child-process/worker.js
index 5f025ca..9b3fcf5 100644
--- a/./worker-threads/worker.js
+++ b/./child-process/worker.js
@@ -1,5 +1,4 @@
 import { execFile } from "node:child_process";
-import { parentPort } from "node:worker_threads";

-parentPort.on("message", (message) => {
+process.on("message", (message) => {
   const [id, cmd, ...args] = message;
@@ -7,3 +6,3 @@ parentPort.on("message", (message) => {
   execFile(cmd, args, (_error, stdout, _stderr) => {
-    parentPort.postMessage([id, stdout]);
+    process.send([id, stdout]);
   });
```

Nice. And the results:

| Language/Runtime | Req/s | Command                                       |
| ---------------- | ----- | --------------------------------------------- |
| Node             | 2,209 | `node child-process/index.js`                 |
| Deno             | 3,800 | `deno run --allow-all child-process/index.js` |
| Bun              | 3,871 | `bun run worker-threads/index.js`             |


Nice, good speedups all around. I am very curious what the bottleneck is that is
preventing Deno and Bun from getting to Rust/Go speeds. Please let me know if
you have suggestions for how to dig into that!

One fun thing here is that we can mix Node and Bun. Bun implements the Node IPC
protocol, so we can configure Node to spawn Bun child processes. Let's try that.

Update the `fork` arguments to use the `bun` binary instead of Node.
```js
const worker = fork("./child-process/worker.js", {
  execPath: "/home/maxm/.bun/bin/bun",
});
```

| Language/Runtime | Req/s | Command                       |
| ---------------- | ----- | ----------------------------- |
| Node + Bun       | 3,853 | `node child-process/index.js` |

Hah, cool. I get to use Node on the main thread and leverage Bun's performance.


## Process Per Process

One issue with this child process pattern is that it become difficult to
interact with stdio streams. We'd need to send the stdout bytes over
`process.send` and I worry that could get expensive quickly. It's fine with just
`hi\n`, but with high log volume it would be a bummer to pay the serialization
cost.

To get around this, we can switch to a model where we have a process pool, and
run one `spawn` per process at a time. When the `spawn` is complete we reset the
process and put it back into the pool for future use.

Let's try that:

```js
const pool = new Pool(factory, { max: 8, min: 8 });

http
  .createServer(async (_, res) => {
    const swimmer = await pool.acquire();
    swimmer.cp.send(["echo", "hi"]);
    await new Promise((resolve) => swimmer.ee.once("exit", resolve));
    swimmer.stdio.stdout.pipe(res);
    pool.release(swimmer);
  })
  .listen(8001);
```

I've removed most of the implementation for brevity, you can [check it out
here](https://github.com/maxmcd/process-per-request/tree/0a6442f656fe7bc8f6c61ef2c5fdef65c6afa0f1/process-per-process).
Similar model from before, but at any given time there is only one spawn running
per-process. Let's see how it does.


| Language/Runtime | Req/s | Command                                       |
| ---------------- | ----- | --------------------------------------------- |
| Node             | 2,552 | `node process-per-process/index.js`           |
| Deno             | 4,052 | `deno run --allow-all child-process/index.js` |
| Bun              | 3,847 | `bun run worker-threads/index.js`             |
| Node + Bun       | 4,042 | `node process-per-process/index.js`           |

Roughly the same or faster than before!

Ok, I think with this path it would be easy enough to put together a library
that leverages this pattern to get higher spawn performance on Node. Lovely.


## Final Thoughts

We're sadly at the limits of my knowledge/experimentation, but I wonder what
could unlock more performance. With all the new `spawn` calls and worker threads
I bet the CPU memory cache thrashing is a mess, and I wonder if there's a way to
organize things to play a little more nicely with the computer.

Using Node and Bun together is a fun pattern and it's nice to see it lead to
such a speedup.

Let me know if there's anything else I should experiment with here! See you next
time :)