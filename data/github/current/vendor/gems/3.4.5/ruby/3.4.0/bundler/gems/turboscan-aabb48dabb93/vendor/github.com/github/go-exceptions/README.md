> With the recent reorg, `Frameworks-Containers` team has been dissolved. Starting from 5th June 2023, we are part of Ecosystem-Events team. We continue to own and provide support for the charter owned by the `Frameworks-Containers` team, but we are not working on any new feature developments.

# exceptions

The exceptions package provides exception reporting to our internal exception
service via different exporters. It's written to be composable and not to
depend on any third party package to keep simple and efficient. Please read the
readme for more information.

- [exceptions ](#exceptions-)
	- [Install](#install)
	- [Example](#example)
	- [The Design of this library](#the-design-of-this-library)
	- [Usage](#usage)
		- [Report exception to the HTTP service](#report-exception-to-the-http-service)
		- [How to use go-exceptions in your Go service in an idiomatic way?](#how-to-use-go-exceptions-in-your-go-service-in-an-idiomatic-way)
		- [Using multiple Exporters](#using-multiple-exporters)
		- [Adding stacktrace information with pkg/errors](#adding-stacktrace-information-with-pkgerrors)
		- [Adding backtrace information with pkg/errors](#adding-backtrace-information-with-pkgerrors)
		- [Using custom rollups](#using-custom-rollups)
		- [Adding a http.Handler middleware to your service](#adding-a-httphandler-middleware-to-your-service)
		- [Writing to Standard Output](#writing-to-standard-output)
		- [Writing to a File](#writing-to-a-file)
		- [Writing to in memory buffer](#writing-to-in-memory-buffer)
		- [Sending exceptions to Sentry](#sending-exceptions-to-sentry)
	- [Contributing](#contributing)

## Install

``` go
go get github.com/github/go-exceptions
```

## Example

Here is a simple example that you can run in your terminal:

```go
package main

import (
	"context"
	"errors"
	"log"
	"os"

	"github.com/github/go-exceptions"
	"github.com/github/go-exceptions/exporters/writer"
)

func main() {
	// create an exporter that prints to standard output
	exporter := writer.NewExporter(os.Stdout)

	// create the reporter that reports the exceptions
	reporter, err := exceptions.NewReporter(
		exceptions.WithExporter(exporter),
		exceptions.WithApplication("my-app"),
		exceptions.WithCatalogService("my-cat-service"),
		exceptions.WithValues(map[string]string{
			"deployed_to": os.Getenv("MY_ENV"),
			"release":     os.Getenv("GIT_SHA"),
		}),
	)
	if err != nil {
		log.Fatalln(err)
	}

	err = reporter.Report(context.Background(), errors.New("this is an error"), map[string]string{"foo": "bar"})
	if err != nil {
		log.Fatalln(err)
	}
}
```

This outputs the following to standard output:

```json
{"app":"my-app","catalog_service":"my-cat-service","created_at":"2006-01-02T15:04:05Z","foo":"bar","host":"Fatihs-MacBook-Pro.local","message":"this is an error","rollup":"6797731743b6ba00fa7c6a50e15d5f11"}
```

## The Design of this library

The go-exceptions package is written to be composable and not to rely ony any
third party packages unless needed. This main package does not import any third
party libraries, expect the `github.com/github/exception-filters/go/rules`
package that contains the rules to redact sensitive information. This keeps the library lean and doesn't pollute your dependency graph if you don't use any of the important packages.

These are the key information to know:

* `github.com/github/go-exceptions.Reporter`: This is the user facing client to report exceptions. Use this in your application to report exceptions and errors.
* `github.com/github/go-exceptions.Exporter`: This is the low-level interface
  that defines how to export the exception data (JSON). There are multiple
  exporters, some of them are:
  * `github.com/github/go-exceptions/exporters/http`: reports the exception to the configured HTTP service
  * `github.com/github/go-exceptions/exporters/mock`: mock exporter to be used in your test
  * `github.com/github/go-exceptions/exporters/writer`: `io.Writer` compatible exporter that allows to log to any medium that satisfies the `io.Writer` interface, such as files, standard output (console), in-memory buffers, etc.

The Reporter and Exporters allow you to use the `go-exceptions` in a various
environments in an easy way. Please see the Usage section for ready-to-use
examples.

## Usage

### Report exception to the HTTP service

If you're looking for explicit instructions on how to wire up Sentry, please see the [Sending exceptions to Sentry](#sending-exceptions-to-sentry) section! For instructions on wiring up any generic HTTP exporter, read below!

This is the most common approach. You can pass a custom `*http.Client` (via the
`http.WithClient()` function). The URL is set to the value read
by `FAILBOT_HAYSTACK_URL` and can be overridden with the `http.WithURL()` function. Note that the URL needs the `username` and `password` in basic authentication form.

```go
package main

import (
	"context"
	"errors"
	"log"

	"github.com/github/go-exceptions"
	"github.com/github/go-exceptions/exporters/http"
)

func main() {
	exporter, err := http.NewExporter(
		// if not provided, reads from "FAILBOT_HAYSTACK_URL"
		http.WithURL("http://matt:matt@127.0.0.1:8800/api/needles"),
	)
	if err != nil {
		log.Fatalln(err)
	}

	// create the reporter that reports the exceptions
	reporter, err := exceptions.NewReporter(
		exceptions.WithExporter(exporter),
		exceptions.WithApplication("my-app"),
	)
	if err != nil {
		log.Fatalln(err)
	}

	err = reporter.Report(context.Background(), errors.New("this is an error"), map[string]string{"foo": "bar"})
	if err != nil {
		log.Fatalln(err)
	}
}
```

#### Circuit breaking
* If you don't pass a circuit breaker to the exporter, a circuit breaker with default options will be used. The default is: [sony/gobreaker](https://github.com/sony/gobreaker).
* If you want to configure the circuit breaker, call `http.NewCircuitBreaker(...opts)` passing the provided configuration methods for timeout, interval, max requests, etc. and pass it to the exporter constructor method
* To enable circuit breaking metrics make sure to pass `http.WithStatter(statsDClient)` when creating the exporter. 


```go
// configure the circuit breaker
cb, err := http.NewCircuitBreaker(
	http.WithTimeout(1 * time.Second),
	...
)
if err != nil {
	log.Fatal(err)
}
exporter, err :=  http.NewExporter(
	http.WithURL("http://matt:matt@127.0.0.1:8080/api/needles"),
	http.WithStatter(statsDClient),
	http.WithCircuitBreaker(cb),
)

...
```
##### Circuit Breaking Metrics
* `circuit_breaker.state_change {from: open|closed, to: closed|open}`
* `failbotg.needles.dropped {intentional: true, reason: circuit_breaker_open}`

### How to use go-exceptions in your Go service in an idiomatic way?

The most important part is to make sure to use multiple
`go-exceptions.Exporter` interfaces in your service.  For example you could
have an environment variable that checks the running host and changes the
`exporter` based on how you run it:

```go
// by default print to stdout, useful for development testing
var exporter exceptions.Exporter
exporter = writer.NewExporter(os.Stdout)

// create a HTTP exporter for production
if os.Getenv("APP_ENV") == "prod" {
	var err error
	exporter, err = http.NewExporter(
		http.WithURL("http://to/some/service"),
	)
	if err != nil {
		log.Fatalln(err)
	}
}

// create the reporter that reports the exceptions
reporter, err := exceptions.NewReporter(
	exceptions.WithExporter(exporter),
	exceptions.WithApplication("my-app"),
)
if err != nil {
	log.Fatalln(err)
}
```

This will allow you to dynamically change the export based on the environment.

### Using multiple Exporters

The exception package allows you to output to multiple exporters with the
`exceptions.MultiExporter()` function. Below is an example that exports via
HTTP and also outputs to standard output:

```go
package main

import (
	"context"
	"errors"
	"log"
	"os"

	"github.com/github/go-exceptions"
	"github.com/github/go-exceptions/exporters/http"
	"github.com/github/go-exceptions/exporters/writer"
)

func main() {
	httpExporter, err := http.NewExporter(
		// if not provided, reads from "FAILBOT_HAYSTACK_URL"
		http.WithURL("http://to/some/service"),
	)
	if err != nil {
		log.Fatalln(err)
	}

	stdoutExporter := writer.NewExporter(os.Stdout)

	// MultiExporter returns an Exporter that satisfies "exceptions.Exporter".
	// This means you can pass it directly to "exceptions.WithExporter". Note
	// that If a listed exporter returns an error, that overall export operation
	// stops and returns the error; it does not continue down the list.
	exporters := exceptions.MultiExporter(
		stdoutExporter,
		httpExporter,
	)

	// create the reporter that reports the exceptions
	reporter, err := exceptions.NewReporter(
		exceptions.WithExporter(exporters),
		exceptions.WithApplication("my-app"),
	)
	if err != nil {
		log.Fatalln(err)
	}

	// this will report both to the HTTP service and output the report to standard output
	err = reporter.Report(context.Background(), errors.New("this is an error"), map[string]string{"foo": "bar"})
	if err != nil {
		log.Fatalln(err)
	}
}
```

### Adding stacktrace information with pkg/errors

go-exceptions is a composable package that does not rely on any third-party packages.
If you would like to get the structured `stacktrace` functionality that Sentry supports,
you must define and set a stacktrace function with the `exceptions.WithStacktraceFunc()`
function.

An example that uses the `pkg/errors` library is included as a separate package in the
example below. If you use `pkg/errors` it should work well for you but you can also
define your own:

```go
package main

import (
	"context"
	"log"
	"os"

	"github.com/github/go-exceptions"
	"github.com/github/go-exceptions/exporters/writer"
	"github.com/github/go-exceptions/stacktracers/pkgerrors"
)

func main() {
	exporter := writer.NewExporter(os.Stdout)

	// create the reporter that reports the exceptions
	reporter, err := exceptions.NewReporter(
		exceptions.WithExporter(exporter),
		exceptions.WithStacktraceFunc(pkgerrors.NewStackTracer()),
		exceptions.WithApplication("my-app"),
	)
	if err != nil {
		log.Fatalln(err)
	}

	err = reporter.Report(context.Background(), errors.New("this is an error"), map[string]string{"foo": "bar"})
	if err != nil {
		log.Fatalln(err)
	}
}
```

### Adding backtrace information with pkg/errors

DEPRECATED: Use stacktrace instead of backtrace, for more structured data in Sentry.
We will remove this backtrace functionality in future versions of this library

Below is an example that sets a backtrace function using the
https://github.com/pkg/errors package:

```go
package main

import (
	"context"
	"fmt"
	"log"
	"os"

	"github.com/github/go-exceptions"
	"github.com/github/go-exceptions/exporters/writer"
	"github.com/pkg/errors"
)

func main() {
	exporter := writer.NewExporter(os.Stdout)

	type stackTracer interface {
		StackTrace() errors.StackTrace
	}

	backtraceFn := func(err error) (string, string) {
		st, ok := err.(stackTracer)
		if !ok {
			return "", ""
		}

		top := st.StackTrace()[0] // get top frame
		rollup := fmt.Sprintf("%+s:%d:%n", top, top, top)
		backtrace := fmt.Sprintf("%+v", st.StackTrace())

		return backtrace, rollup
	}

	// create the reporter that reports the exceptions
	reporter, err := exceptions.NewReporter(
		exceptions.WithExporter(exporter),
		exceptions.WithBacktraceFunc(backtraceFn),
		exceptions.WithApplication("my-app"),
	)
	if err != nil {
		log.Fatalln(err)
	}

	err = reporter.Report(context.Background(), errors.New("this is an error"), map[string]string{"foo": "bar"})
	if err != nil {
		log.Fatalln(err)
	}
}
```

### Using custom rollups

You can customize an exception's rollups independent of the stack trace or
error message using the `WithRollupInfoFunc` option:

```go
package main

import (
  "fmt"
  "net/http"
  "os"

  "github.com/github/go-exceptions"
  "github.com/github/go-exceptions/exporters/writer"
)

func main() {
  reporter, err := exceptions.NewReporter(
    // use exceptions.RollupInfo to create our rollups
    exceptions.WithRollupInfoFunc(exceptions.RollupInfo),

    exceptions.WithExporter(writer.NewExporter(os.Stderr)),
    exceptions.WithApplication("my-app"),
  )
  if err != nil {
    panic(err)
  }

  dependency := new(SomeExternalDependency)

  err = http.ListenAndServe("/", http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
    err := dependency.Run(req.URL.Query()["thing"])
    if err != nil {

      // wrap the error with rollup info that exceptions.RollupInfo can use to create the rollup
      err = exceptions.WithRollupInfo(err, "error from SomeExternalDependency.Run")

      _ = reporter.Report(req.Context(), err, nil)
      http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
      return
    }
    w.WriteHeader(http.StatusAccepted)
  }))
}

type SomeExternalDependency struct{}

func (d *SomeExternalDependency) Run(things []string) error {
  return fmt.Errorf("error handling %v", things)
}
```

### Adding a http.Handler middleware to your service

The `Reporter` type implements the `http.Handler` interface, and can
act as a wrapper that recovers from a panic in the handler goroutine
and reports it as an exception.
(Be aware that `Reporter.ServeHTTP` will not recover from a panic in
any other goroutine, and the Go runtime [has no
mechanism](https://github.com/golang/go/issues/32333#issuecomment-498827695)
for installing a crash handler for all goroutines.)

Here is an example of one way to wrap your existing HTTP handler:

```go
package main

import (
	"io"
	"log"
	"net/http"
	"os"

	"github.com/github/go-exceptions"
	"github.com/github/go-exceptions/exporters/writer"
)

func main() {
	exporter := writer.NewExporter(os.Stdout)

	// this handler will panic before it's able to write "Hello, world!"
	helloHandler := func(w http.ResponseWriter, req *http.Request) {
		panic("oh nooo!")
		io.WriteString(w, "Hello, world!\n")
	}

	// create the reporter that reports the exceptions to stdout and wraps the
	// hellohandler handler
	reporter, err := exceptions.NewReporter(
		exceptions.WithExporter(exporter),
		exceptions.WithApplication("my-app"),
		exceptions.WithHandlerFunc(helloHandler),
	)
	if err != nil {
		log.Fatalln(err)
	}

	// reporter satisfies http.Handler and can be passed to any function that
	// accepts http.Handler
	http.Handle("/", reporter)

	log.Println("server started at port 8800")
	log.Fatal(http.ListenAndServe(":8800", nil))
}
```

Save&run the code and make a request against it:

``` curl
$ curl localhost:8800
exception handler has recovered from panic
```

This will recover from the panic and the output of the server will be:

```
2019/12/09 10:45:08 server started at port 8800
{"app":"my-app","host":"Fatihs-MacBook-Pro.local","message":"panic: oh nooo!","method":"GET","rollup":"fb5f7408efbd8ab5f04ad3a5ae0633ac","url":"/"}
```

As you see, it reported the panic with additional information. Don't forget to add a `backtrace` function if you want to add the back trace of an exception as well.

### Writing to Standard Output

Below is an example that outputs to Standard output

```go
package main

import (
	"context"
	"errors"
	"log"
	"os"

	"github.com/github/go-exceptions"
	"github.com/github/go-exceptions/exporters/writer"
)

func main() {
	// create an exporter that prints to standard output
	exporter := writer.NewExporter(os.Stdout)

	// create the reporter that reports the exceptions
	reporter, err := exceptions.NewReporter(
		exceptions.WithExporter(exporter),
		exceptions.WithApplication("my-app"),
	)
	if err != nil {
		log.Fatalln(err)
	}

	err = reporter.Report(context.Background(), errors.New("this is an error"), map[string]string{"foo": "bar"})
	if err != nil {
		log.Fatalln(err)
	}
}
```

This will output:

```json
{"app":"my-app","created_at":"2006-01-02T15:04:05Z","foo":"bar","host":"Fatihs-MacBook-Pro.local","message":"this is an error","rollup":"6797731743b6ba00fa7c6a50e15d5f11"}
```

### Writing to a File

Below is an example that writes to a file via the `writer` exporter:

```go
package main

import (
	"context"
	"errors"
	"fmt"
	"io/ioutil"
	"log"
	"os"

	"github.com/github/go-exceptions"
	"github.com/github/go-exceptions/exporters/writer"
)

func main() {
	file, err := os.Create("/tmp/exceptions")
	if err != nil {
		log.Fatalln(err)
	}
	defer file.Close()

	exporter := writer.NewExporter(file)

	// create the reporter that reports the exceptions
	reporter, err := exceptions.NewReporter(
		exceptions.WithExporter(exporter),
		exceptions.WithApplication("my-app"),
	)
	if err != nil {
		log.Fatalln(err)
	}

	err = reporter.Report(context.Background(), errors.New("this is an error"), map[string]string{"foo": "bar"})
	if err != nil {
		log.Fatalln(err)
	}

	content, err := ioutil.ReadFile("/tmp/exceptions")
	if err != nil {
		log.Fatalln(err)
	}

	fmt.Printf("File contents: %s", content)
}
```

### Writing to in memory buffer

Below is an example that outputs the reports to the `buf` internal buffer:

```go
package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"log"

	"github.com/github/go-exceptions"
	"github.com/github/go-exceptions/exporters/writer"
)

func main() {
	var buf bytes.Buffer
	exporter := writer.NewExporter(&buf)

	// create the reporter that reports the exceptions
	reporter, err := exceptions.NewReporter(
		exceptions.WithExporter(exporter),
		exceptions.WithApplication("my-app"),
	)
	if err != nil {
		log.Fatalln(err)
	}

	err = reporter.Report(context.Background(), errors.New("this is an error"), map[string]string{"foo": "bar"})
	if err != nil {
		log.Fatalln(err)
	}

	// print output of the in memory buffer
	fmt.Println(buf.String())
}
```

### Sending exceptions to Sentry

First, if you want to see a finished example, you can always head over to the [go-sample-service](https://github.com/github/go-sample-service).

There's a few setup steps in order to make sure you're set up to report exceptions to Sentry.

- Follow the [Sentry on-boarding guide in thehub](https://thehub.github.com/engineering/development-and-ops/observability/exception-tracking/)
- If you haven't already, you'll need to [set up your application for vault use](https://thehub.github.com/security/security-operations/vault/). The Sentry onboarding guide also contains instructions on how to get the credentials you will set into the `FAILBOT_HAYSTACK_URL` environment variable. 
- The current implementation of `go-exceptions` requires `FAILBOT_HAYSTACK_URL` to be set as an environment variable.
	- Format your given Sentry credentials like `https://username:password@failbotg.service.iad.github.net/api/needles`
		- The [httpexporter](/exporters/http/http.go#L57) expects them this way
	- Place them in your vault with `FAILBOT_HAYSTACK_URL` as the key
	- To set a secret in vault, [see here](https://githubber.com/article/technology/internal/configuration-variables-for-applications)
- `go-exceptions` should automatically pick up the secret from your environment variable once your application is configured with Vault
- The first time your service emits an exception, failbotg will create a project in Sentry automatically
	- You should be able to see the metric that marks your project's creation on [this dashboard](https://app.datadoghq.com/dashboard/q3p-2dd-s5n/failbotg?from_ts=1585677953996&fullscreen_section=overview&fullscreen_widget=2521847272768426&live=true&tile_size=m&to_ts=1585681553996&fullscreen_start_ts=1585678168535&fullscreen_end_ts=1585681768535&fullscreen_paused=false)
- Log into Sentry through Okta and see the issues created in your project!

## Contributing

 To learn more about developing and making updates to this repo, please checkout [the contributing guide](https://github.com/github/frameworks-containers/tree/main/docs/go-libs-common-docs/CONTRIBUTING.md).
