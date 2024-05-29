---
title: "Running Go on Val Town"
date: 2024-05-29T06:21:13
draft: false
toc: true
images: [https://imagedelivery.net/iHX6Ovru0O7AjmyT5yZRoA/dce5f555-86e1-4f98-8471-f0641a34e200/public]
tags:
  - val.town
  - go
  - deno
  - wasm
---

![image.png](https://imagedelivery.net/iHX6Ovru0O7AjmyT5yZRoA/dce5f555-86e1-4f98-8471-f0641a34e200/public)

Let's go on a winding debugging adventure together. I thought I could get a Go HTTP handler running on [Val Town](https://val.town) and I thought it would be easy. Val Town is a social website to write and deploy Typescipt. Val Town doesn't support Go, but it supports WASM. Can we make it all work!?

> If you want to skip all this and just run Go on Val Town you can [follow the instructions here](https://www.val.town/v/maxm/compileAndUploadTinygoWasm). There's also a [basic "Hello World"](https://www.val.town/v/maxm/tinygoWasmHelloWorld) example, and another that's [much more fun and complex](https://www.val.town/v/maxm/tinygoHttpExample).

About two months ago I started working at Val Town. Before that I had spent many years writing Go and had always thought it would be quite poetic to get a Go HTTP handler running on Val Town. The real dream is to get the Go compiler and Language Server running in browser so that you could really have the dynamic feel of Val Town, but for now we're going to settle for "Writing some Go code, compile it, and having it handle an http request in Val Town".

I thought it would be easy, and set out to find out:

## Setting the stage

Val Town runs [Deno](https://deno.com/), so our goal for the moment is getting something running in Deno. We want to end up with something like this

```ts
import goWasmHandler from "https://dreamland/maxmcd/nice/mod.ts"

Deno.serve({port: 8080}, (req: Request): Promise<Response> => {
    return goWasmHandler(req)
})
```

Now, there are a few tutorials online about how to get Golang (or [Tinygo](https://tinygo.org/)) WASM running in Deno. [As far](https://dev.to/taterbase/running-a-go-program-in-deno-via-wasm-2l08) as I [could find]((https://github.com/philippgille/go-wasm)), these are mostly "Hello World" type things, or exporting and importing functions to just do some kind of work in Go. We want an HTTP request handler though so we're going to require a little more functionality.

## WASI

Go [added WASI support](https://go.dev/blog/wasi). Deno has [a WASI library](https://deno.land/std@0.206.0/wasi/snapshot_preview1.ts). That should work right?

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

Ok, so WASI won't work (and was maybe a little too low level for us anyway since we just need an http handler), so what about Go's old [syscall/js](https://pkg.go.dev/syscall/js) WASM bindings? Intended for browsers and some [Deno tutorials use it](https://dev.to/taterbase/running-a-go-program-in-deno-via-wasm-2l08), so why not us?

Oh, we even know that in syscall/js the Go http standard library [has a `fetch` wrapper](https://github.com/golang/go/blob/07fc59199b9522bfe0d14f35c4391394efc336c9/src/net/http/roundtrip_js.go#L129) implemented to make http calls with `http.Get`, so maybe that will work!

We'll copy `wasm_exec.js` from Go:
```bash
cp "$(go env GOROOT)/misc/wasm/wasm_exec.js" .
```

For some reason I can't run this like I see others doing in tutorials with `import * as _ from "./wasm_exec.js"`. Deno seems to ignore the file entirely and then the `Go` class is not added to `globalThis`. So I [modified it](https://github.com/maxmcd/go-town/blob/main/go-js/wasm_exec.js#L7) to have a contrived export value.

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

Weird. We don't see a panic or another error, the script just breaks. After some digging I could not figure it out. Although going in this direction was a bit contrived, we know from googling that running a server is not supported. Let's move on.

At this point we're likely going to have to write the server logic ourselves. We have a `fetch` wrapper, but nothing to take a server request and ferry it over to the Go side. We'll have to build that. If this already exists please tell me, I could not find any kind of library that would handle sending `Request` or `Response` back and forth between Go+WASM and js/ts.

From here I think we have two options:

1. Continue with Go's syscall/js functionality. Write a library that makes javascript calls with syscall/js to handle requests for our server.
2. Switch to Tinygo, get much smaller WASM binaries, lose so Go language featuers, leave the `fetch` wrapper behind :(, but do the work in a WASI context that we know will be supported into the future.

For now, I went with option #2. That maybe seem a little unexpected, but now that we're going to implement the http stuff ourselves it feels easier to work with Tinygo and WASI than the syscall/js lib. Sometime in the near future I imagine I'll come crawling back to sycall/js for more robust functionality.

## Tinygo and WASI

Let's see if we can get a basic Tinygo WASM binary running in Deno.

Here's our Go source:
```go
package main

//export add
func add(a, b int) int {
	return a + b
}

// main is required for the `wasi` target, even if it isn't used.
func main() {}
```

And we're back using the WASI Deno lib again:

```tsx
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

console.log(instance.exports.add(4, 7));
console.log(instance.exports.add(43, 21));
```

Let's compile our WASM binary and then run it:
```bash
$ tinygo build -o main.wasm -target=wasi .
$ wasm-strip ./main.wasm
$ deno run --allow-read ./index.ts
11
64
```

Nice, we can add numbers and everything works.

Now the hard part. When a request comes in we want to serialize the request and pass it over to Go code, then deserialize it and turn it into an `*http.Request`. In our Go HTTP handler we want the user to write to an `http.ResponseWriter` and have that be passed back over to the JS side so that we can turn it into a `Response` object. For simplicity we'll skip things like streaming requests and responses and just send the full request over and wait for the full response.

One of the trickier parts of this for me is getting the bytes sent between each environment. When sending bytes over to Go/WASM we'll need to:

1. Allocate space in the shared WASM memory and write the bytes.
2. Send the memory location over to the Go code.
3. Read the bytes from memory and turn them into a Go byte array.

On the way back we'll do the reverse:

1. Take our Go byte array and get the memory location of the underlying bytes.
2. Send the location over to Javascript.
3. Read bytes from the shared WASM memory and be careful that the bytes are not garbage collected before we read them!

I have implemented this pattern a few times and it is never easy going, so this time I found this [helpful go/js library](https://github.com/bots-garden/wasi-tinygo-js) that implements helper functions to send strings and bytes between Nodejs and Tinygo.

With that in place I'll have a `callHandlerWithJson` function that I can can call with a WebAssembly instance:

```ts
function callHandlerWithJson(instance: WebAssembly.Instance, payload: any)
```

On the Go side, I can call this function to register a handler that will accept the JSON bytes. We'll read the bytes, process the request and then return the JSON bytes of our response.
```go
setHandler(function func(param []byte) ([]byte, error))
```

## Draw the rest of the owl

We're nearing our conclusion. Using the building blocks outlined above we can do everything we need. Let's depart from story mode and I'll show you how it all works.

First, define your HTTP handler in Go. To do that you'll use a Go library I made called [`go-town`](https://github.com/maxmcd/go-town/).

```go
package main

import (
	"fmt"
	"net/http"

	gotown "github.com/maxmcd/go-town"
)

func main() {
	gotown.ListenAndServe(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "Hello from Deno and Tinygo 🤝")
	}))
}
```

Compile it:

```bash
tinygo build -o main.wasm -target=wasi
wasm-strip ./main.wasm
```

Now let's run it in Deno. I made a library in Val Town that takes a WASM binary and returns an HTTP handler:

```ts
import { wasmHandler } from "https://esm.town/v/maxm/tinygoHttp";

const handler = await wasmHandler(await Deno.readFile("main.wasm"));
Deno.serve({ port: 8080 }, async (req) => {
  return handler(req);
});
```

Now we run it:
```bash
deno run --allow-env --allow-read --allow-net ./index.ts

# in a separate terminal
$ curl localhost:8080
Hello from Deno and Tinygo 🤝
```

Nice!

Here's the full sequence of events:

1. When a request comes in we turn the `Request` object into JSON and [send it over to the WebAssembly binary](https://www.val.town/v/maxm/tinygoHttp?v=22#L94-99).
2. We [turn the JSON into an `*http.Request`](https://github.com/maxmcd/go-town/blob/4b9de71a8d427c2e19d0d56f025184b31f9f25b7/gotown.go#L101-L105) and pass it to our `gotown.ListenAndServe` handler.
3. We use our `http.ResponseWriter` to [collect the response](https://github.com/maxmcd/go-town/blob/4b9de71a8d427c2e19d0d56f025184b31f9f25b7/gotown.go#L82-L96) and then [return it back to JS land](https://github.com/maxmcd/go-town/blob/4b9de71a8d427c2e19d0d56f025184b31f9f25b7/gotown.go#L106-L110).
4. Finally, we [turn the JSON into a `Response` object](https://www.val.town/v/maxm/tinygoHttp?v=22#L103-107) and return it.

There we go. We did it.

## But what about Val town?

Now that we have everything working we can wrap things up to work in Val Town in the most clever of ways.

We're going to run things in Val Town with the help of three different Vals.

1. First, we'll make a script in Val Town that we can run with `deno run`: https://www.val.town/v/maxm/compileAndUploadTinygoWasm. This is a bit of an atypical use, but we'll write our script as a Val and then copy the module url (https://esm.town/v/maxm/compileAndUploadTinygoWasm) to run it from Deno. You can run many differnent Vals in Deno this way and it opens up some cool use cases.

2. Second, we'll create an [HTTP Val](https://www.val.town/v/maxm/wasmBlobHost) to use as a [general purpose WASM binary host](https://maxm-wasmblobhost.web.val.run/). Val Town doesn't allow you to upload files for Vals, but we can make our own and store the WASM binaries in [blob storage](https://www.val.town/v/std/blob).

3. Third, we'll continue to use the script Val from the previous section as a library to handle all the WASM<>JS communication: https://www.val.town/v/maxm/tinygoHttp


Here's all those pieces working together:

We'll start with a slightly modified version of our Go HTTP service.
```go
package main

import (
	"fmt"
	"net/http"

	gotown "github.com/maxmcd/go-town"
)

func main() {
	gotown.ListenAndServe(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "Hello from Val Town and Tinygo 🤝")
	}))
}
```

And now we run our script to compile and upload it:

```text
$ deno run --allow-net --allow-run --allow-read \
    "https://esm.town/v/maxm/compileAndUploadTinygoWasm?v=58"
Compliation complete
Running wasm-strip main.wasm

Copy the following into a Val Town HTTP Val:

import { wasmHandler } from "https://esm.town/v/maxm/tinygoHttp";
const resp = await fetch("https://maxm-wasmblobhost.web.val.run/e5vpzt253pv5jxqfmygo7nytl5uvyn5c.wasm");
const handler = await wasmHandler(new Uint8Array(await resp.arrayBuffer()));
export default async function(req: Request): Promise<Response> {
  return handler(req);
}
```

You can see the WASM binary uploaded here: https://maxm-wasmblobhost.web.val.run/

I pasted the resulting code into an HTTP Val. You can see everything working here: https://www.val.town/v/maxm/aquamarinePiranha

<iframe width="100%" height="400px" src="https://www.val.town/embed/maxm/aquamarinePiranha" title="Val Town" frameborder="0" allow="web-share" allowfullscreen></iframe>

## Conclusion

This is all a bit of silliness. Quite inefficient. Not super useful. But, it was quite a bit of fun to play around with all this stuff. I hope one day I can make a little Go playground where you can write Go with a language server and compile and run HTTP handlers from the browser. That would be cool, and fun (still not very useful), and this is a step in that direction :)
