---
title: "Running Go on Val Town"
date: 2021-11-14T21:21:13
draft: true
toc: true
images: []
tags:
  - val.town
  - go
  - wasm
---

# Running Go on Val Town

This is going to be one of those long winging blog posts where I take you on a debugging adventure. I thought I could get a Go HTTP handler running on [Val Town](https://val.town) and I thought it would be easy. It was not easy. Ok, in the end it wasn't too bad, but it was quite the winding journey.

About a month ago I started working at Val Town. Before that I had spent many years writing Go and had always thought it would be quite poetic to get a Go HTTP handler running on Val Town. The real dream is to get the Go compiler and Language Server running in browser so that you could really have the dynamic feel of Val Town, but for now we're going to settle for "Writing some Go code, compiling it, and having it handle an http request in Val Town".

Last night, I thought it would be easy, and set out to find out:

## Setting the stage

Val Town runs Deno, so our goal for the moment is getting something running in Deno. We want to end up with something like this

```ts
import goWasmHandler from "https://dreamland/maxmcd/nice/mod.ts"

Deno.serve({port: 8080}, (req: Request): Promise<Response> => {
    return goWasmHandler(req)
})
```

Now, there are many tutorials online about how to get Golang (and Tinygo) WASM running in Deno. As far as I could find, these are all "Hello World" type things, or exporting and importing functions to just do some kind of work in Go. We want an HTTP request handler though so we're going to require a little more functionality than is typical.

## WASI

Go added WASI support. Deno has a WASI library. That should work right?

We write our Go program with reckless optimism. Let's see if we can make an http request.

```go
package main

import (
	"fmt"
	"net/http"
)

func main() {
	fmt.Println(http.Get("https://www.maxmcd.com/"))
}
```

Compile it:
```bash
GOOS=wasip1 GOARCH=wasm  go build -o main.wasm ./main.go
```

Write a Deno script to run it:
```ts
import Context from "https://deno.land/std@0.206.0/wasi/snapshot_preview1.ts";

const context = new Context({
  args: Deno.args,
  env: {},
});
const binary = await Deno.readFile("main.wasm");
const module = await WebAssembly.compile(binary);
const instance = await WebAssembly.instantiate(module, {
  wasi_snapshot_preview1: context.exports,
});

context.start(instance);
```

Run the script!
```
$ deno run --allow-net --allow-read ./index.ts
<nil> Get "https://www.maxmcd.com/": dial tcp: lookup www.google.com on [::1]:53: dial udp [::1]:53: Connection refused
```

Ah no :(

Ok, so `fmt.Println` is working, which is nice, but we can't seem to make a DNS request for the host. It looks like [this lib doesn't support socket calls yet](https://github.com/denoland/deno_std/blob/b31795879301189559383d3e496c341d3f695201/wasi/snapshot_preview1.ts#L1696-L1722) (and is very clear about this in the readme) so no luck!

## syscall/js

Ok, so WASI won't work (and was maybe a little too low level for us anyway since we just need an http handler), so what about Go's old syscall/js? Intended for browsers and some [Deno tutorials us it](https://dev.to/taterbase/running-a-go-program-in-deno-via-wasm-2l08), so why not us?

Oh, we even know that in syscall/js the Go http standard library has a `fetch` wrapper implemented to make http calls with `http.Get`, so maybe that will work!
