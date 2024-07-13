---
title: "Process Per Request Performance in NodeJS"
date: 2024-07-12T00:00:00
draft: false
toc: true
images: []
tags:
  - nodejs
  - js
  - performance
  - buno
  - go
  - deno
---

How fast can an HTTP server in NodeJS run if we spawn a process for every
request?

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
and it spends 30% of the time blocked on calls to `spawn`. Why is it slow? Can
we make it any faster?

Let's write up examples and run them in Node, Deno, Go, Rust, and Bun and see
how fast we can get them.

I am running all of these on a Hetzner CCX33 with 8 vCPUs and 32 GB of ram. I am
benchmarking with [bombardier](https://github.com/codesenberg/bombardier)
running on the same machine. The command I'll run to benchmark each server is
`bombardier -c 30 -n 10000 http://localhost:8001`. 10,000 total requests over 30
connections.

Each implementation will run an HTTP server, spawn `echo hi` for each request, and
respond with the stdout of the command. The Node/Bun/Deno server is at the beginning of this post. The Go source is [here](TKTKTKTKTK) and the Rust source is [here](TKTKTKTK).

Here are the results:

| Language/Runtime | Req/s | Command |
|- | -  | - |
| NodeJS | 651  | `node index.js` |
| Deno | 2,290  | `deno run --allow-all index.js`
| Bun | 2,208  | `bun run index.js`
| Go | 5,227  | `go run main.go`
| Rust (tokio) | 5,466  | `cargo run --release`

Ok, so Node is slow. Deno and Bun have figured out how to make this faster, and the compiled, thread-pool languages are much faster again.

Node's `spawn` performance does seem to be notably bad. [This thread](https://github.com/nodejs/node/issues/14917) was an interesting read, and while in my testing things have improved since the time of that post, Node still spends an awful lot of time blocking the main thread for each Spawn call.

But for now I am stuck with Node, so how can we make it faster.

## Node `cluster` Module

The simplest thing we can do spawn more processes and run an http server per-process using Node's `cluster` module. Like so:

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

Here are the results:

| Language/Runtime | Req/s  | Command |
|- | -  | - |
| NodeJS | 1,766  | `node index.js` |
| Deno | 2,133  | `deno run --allow-all index.js`
| Bun | n/a  | "node:cluster is not yet implemented in Bun"

Super weird. Deno is slower, Bun doesn't work, and NodeJS has improved a lot, but I would have expected it to get closer to Rust/Go.

Either way, we're abandoning this path for now. I need a single Node process so that I can manage some global state and forking the Node process will break my implementation. Still, good to know this is an avenue for some speed if it's ever applicable


## Many Processes Per Worker Thread

For my first attempt to improve this pattern I use the Node `worker_threads`
library to spawn a few thread. Then I'd use `Worker.postMessage` to send
information back and forth. Each thread would be responsible for spawning many
processes.

For some reason I couldn't get a speedup with this pattern. I am surely doing
something wrong. I even wrote a little library
[child-process-worker-pool](https://www.npmjs.com/package/child-process-worker-pool).
I didn't get around to implementing stdio, so we simply wait for the process to exit and write a fake response:

```js
import http from "node:http";
import { ProcessPool } from "child-process-worker-pool";

const pool = new ProcessPool();

http
  .createServer((req, res) => {
    const cp = pool.spawn("echo", ["hi"]);
    cp.on("exit", () => {
      res.write("hi");
      res.end();
    });
  })
  .listen(8001);
```

| Language/Runtime | Req/s  | Command |
|- | -  | - |
| NodeJS | 611  | `node index.js` |
| Deno | 1,297  | `deno run --allow-all index.js`

I think there are ways to improve this, but I was really worried about the potential performance issue of streaming stdio over `postMessage`. This implementation was getting very complicated, so I moved on to experiment elsewhere.

## Resettable Process Pool

What if we could keep the `echo` process around and ask it to reset itself? That way we avoid the spawn calls entirely? Maybe a process could get a signal and reset its state?

Well, we can't do that with the processes I'm dealing with, but maybe we can get close by maintaining a process pool and have each process reset itself by killing its running child process and spawning a new one. This is much simpler and we also get stdio for free because the child_process can inherit it. This is very similar to the `worker_threads` pattern, so maybe it will be slow as well? We'll see.


Let's define a worker:
```js
import { spawn } from "node:child_process";
let cp;

process.on("message", (message) => {
  if (message === "reset") {
    if (cp) cp.kill();
  } else if (message === "spawn") {
    cp = spawn("echo", ["hi"], { stdio: "inherit" });
    cp.on("spawn", () => process.send("spawn"));
    cp.on("exit", () => process.send("exit"));
  }
});
```

And we'll use [lighting-pool](https://www.npmjs.com/package/lightning-pool) as our process pool.

The full implementation is [here](TKTKTKT), but our server bit now looks like this:

```js
http
  .createServer(async (req, res) => {
    const swimmer = await pool.acquire();
    await swimmer.spawn();
    res.write(swimmer.child.stdout.read()?.toString() || "");
    res.end();
    pool.release(swimmer);
  })
  .listen(8001);
```

| Language/Runtime | Req/s  | Command |
|- | -  | - |
| NodeJS |  2,428 | `node index.js` |
| Deno | n/a  | No response  ¯\\_(ツ)_/¯ |
| Bun | 2,578  | `bun run index.js` |

Wow, ok. This pattern is great for Node. Small speedup on Bun, but big speedup on Node.

For my work, I must use Node, but what if the process pool is running Bun processes? Bun implements the node IPC protocol, so all we have to do is add a single line to fork arguments:

```js
fork("./worker.js", {
    execPath: "/home/maxm/.bun/bin/bun",
    stdio: "pipe",
});
```

| Language/Runtime | Req/s  | Command |
|- | -  | - |
| NodeJS + Bun | 3,281 | `node index.js` |

Amazing, a nice little bump with Bun and Node combined.