---
title: "Running Go on Val Town"
date: 2024-05-11T21:21:13
draft: false
toc: true
images: []
tags:
  - val.town
  - go
  - wasm
---
This is going to be one of those long winding blog posts where I take you on a debugging adventure. I thought I could get a Go HTTP handler running on [Val Town](https://val.town) and I thought it would be easy.

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

Now, there are many tutorials online about how to get Golang (and Tinygo) WASM running in Deno. As far as I could find, these are all "Hello World" type things, or exporting and importing functions to just do some kind of work in Go. We want an HTTP request handler though so we're going to require a little more functionality.

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

Ok, so `fmt.Println` is working, which is nice, but we can't seem to make a DNS query for the host. It looks like [the Deno wasi lib doesn't support socket calls yet](https://github.com/denoland/deno_std/blob/b31795879301189559383d3e496c341d3f695201/wasi/snapshot_preview1.ts#L1696-L1722) (and is very clear about this in the readme) so no luck!

## syscall/js

Ok, so WASI won't work (and was maybe a little too low level for us anyway since we just need an http handler), so what about Go's old syscall/js? Intended for browsers and some [Deno tutorials use it](https://dev.to/taterbase/running-a-go-program-in-deno-via-wasm-2l08), so why not us?

Oh, we even know that in syscall/js the Go http standard library [has a `fetch` wrapper](https://github.com/golang/go/blob/07fc59199b9522bfe0d14f35c4391394efc336c9/src/net/http/roundtrip_js.go#L129) implemented to make http calls with `http.Get`, so maybe that will work!

We'll copy `wasm_exec.js` from Go:
```bash
cp "$(go env GOROOT)/misc/wasm/wasm_exec.js" .
```

For some reason I can't run this like I see others doing in tutorials with `import * as _ from "./wasm_exec.js"`. Deno seems to ignore the file entirely and then the `Go` class is not added to `globalThis`. So I modify it to have a contrived export value.

Write our Deno script:
```ts
import { go as g } from "./wasm_exec.js";
const _ = g;

const go = new window.Go();
const buf = await Deno.readFileSync("./main.wasm");
const inst = await WebAssembly.instantiate(buf, go.importObject);
await go.run(inst.instance);
```

We'll use the same Go script as before, but this time we'll compile with `GOOS=js`:
```bash
GOOS=js GOARCH=wasm  go build -o main.wasm ./main.go
```

Let's run it:
```bash
$ ./compile.sh && deno run --allow-net --allow-read ./index.ts
&{200 OK 200  0 0 map[Access-Control-Allow-Origin:[*] Age:[0] Alt-Svc:[h3=":443"; ma=86400] Cache-Control:[max-age=600] Cf-Cache-Status:[DYNAMIC] Cf-Ray:[882c9c85b89607ef-IAD] Content-Type:[text/html; charset=utf-8] Date:[Sun, 12 May 2024 18:53:24 GMT] Expires:[Sun, 12 May 2024 18:32:34 GMT] Last-Modified:[Thu, 25 May 2023 01:50:43 GMT] Nel:[{"success_fraction":0,"report_to":"cf-nel","max_age":604800}] Report-To:[{"endpoints":[{"url":"https:\/\/a.nel.cloudflare.com\/report\/v4?s=yTUiXIq4KveSdxOvi%2F2HhATI8MVyL%2BFESX6poW5BRilzSEVB%2Fvn3gMkDNuCvpCRmefSvVK8i%2FOAmWqqpu%2Bzo9MhqCQ4mjQNwnaFzvokAxXqCoJAVJ6CUrxTLjBlt"}],"group":"cf-nel","max_age":604800}] Server:[cloudflare] Vary:[Accept-Encoding] Via:[1.1 varnish] X-Cache:[HIT] X-Cache-Hits:[0] X-Fastly-Request-Id:[54b300bdfa470e7a6ed26bae3c77efbbe5d54855] X-Github-Request-Id:[E256:4683B:1C05177:2274825:664108EA] X-Proxy-Cache:[MISS] X-Served-By:[cache-iad-kiad7000035-IAD] X-Timer:[S1715540005.768604,VS0,VE9]] 0x14422c0 -1 [] false false map[] 0x1470000 <nil>} <nil>
```

Nice! Progress! The `fetch` wrapper works and we can make a request. Ok, fingers crossed, let's try an http server:

```go
func main() {
	if err := http.ListenAndServe(":8080", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, "Hello, World!")
	})); err != nil {
		panic(err)
	}
}
```

Let's run it:
```bash
$ deno run --allow-net --allow-read ./index.ts
error: Top-level await promise never resolved
await go.run(inst.instance);
^
    at <anonymous> (file:///Users/maxm/go/src/github.com/maxmcd/go-town/go-js/index.ts:5:1)
```

Weird. We don't see a panic of another error, the script just breaks. After some digging I could not figure it out. Although going in this direction was a bit contrived, we know from googling that running a server is not supported.

At this point we're likely going to have to write the server logic ourselves. We have a `fetch` wrapper, but nothing to take a server request and ferry it over to the Go side. We'll have to build that. If this already exists please tell me, I could not find any kind of library that would handle sending `Request` or `Response` back and forth between Go+WASM and js/ts.

From here I think we have two options:

1. Continue with Go's syscall/js functionality. Write a library that makes javascript calls with syscall/js to handle requests for our server.
2. Switch to Tinygo, get much smaller WASM binaries, leave the `fetch` wrapper behind :(, but do the work in a WASI context that we know will be supported into the future.

So I did both of those things!

## Continuing with syscall/js

## Tinygo and WASI
