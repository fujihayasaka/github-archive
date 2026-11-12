# go-ctxutil

go-ctxutil includes `context.Context` specific utilities:

## `ctxutil.DetachedCancel`

Use this to make a sub-context survive beyond the lifetime of a parent context. In this example usage, a request gets preprocessed before being accepted and sent for further asynchronous work. The preprocessing happens synchronously and respects the 10 seconds deadline. However, the async work should not be limited by the 10s deadline, nor should it be cancelled when the HTTP request ends. Therefore, we use `ctxutil.DetachedCancel(ctx)`:

```go

import (
 // other imports
 ctxutil "github.com/github/go-ctxutil"
)

func (srv *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
 ctx, cancel := context.WithTimeout(r.Context(), 10 * time.Second)
 defer cancel()

 args, err := readArgs(r)
 if err != nil {
  srv.reportErr(ctx, w, r, err)
  return
 }

 err := srv.preprocessRequest(ctx, args);
 if err != nil {
  srv.reportErr(ctx, w, r, err)
  return
 }

 detachedCtx := ctxutil.DetachedCancel(ctx)
 go srv.asyncWork(detachedCtx, args)

 w.WriteCode(http.StatusAccepted)
}
```

## `ctxutil.DelayedCancel`

DelayedCancel is similar to DetachedCancel except that canceling the parent context will trigger a delayed
cancellation of the returned context.

This is useful when you have a service that needs a bit of time to finish up after its context is canceled. In
the example below, when ctx is canceled no more data will be sent to the processor, but the processors won't be
stopped for five seconds after the cancel.

```go
import (
 // other imports
 ctxutil "github.com/github/go-ctxutil"
)

func processData(ctx context.Context) {
 delayedCtx, cancel := ctxutil.DelayedCancel(ctx, 5 * time.Second)
 defer cancel()
 pp := startProcessorPool(delayedCtx)
 for ctx.Err() == nil {
  data := fetchData(ctx)
  if data != nil {
   pp.processData(data)
  }
 }
 <- delayedCtx.Done()
}

```

## `sigctx.WithSignal`

This helper function wraps your context and cancels when one of the specified signals are received. The function lives in its own package since it links to other packages such as `os` and `os/signal`. Example usage:

```go
package main

import (
 "context"
 "fmt"
 "os"
 "os/signal"
 "syscall"

 "github.com/github/go-ctxutil/sigctx"
)

func main() {
 ctx := sigctx.WithSignal(context.Background(), syscall.SIGINT)

 go fmt.Println("run my server")

 // this is blocking until the ctx is cancelled.
 // press ctrl-c to trigger a SIGINT
 <-ctx.Done()

 fmt.Println("context cancelled. Gracefully shutdown your server, do cleanups, etc..")
}
```

## Contributing

This repository is owned by [@dev-frameworks](https://github.com/github/dev-frameworks/), and we welcome contributions! To learn more about developing and making updates to this repo, please see [the contributing guide](./CONTRIBUTING.md).
