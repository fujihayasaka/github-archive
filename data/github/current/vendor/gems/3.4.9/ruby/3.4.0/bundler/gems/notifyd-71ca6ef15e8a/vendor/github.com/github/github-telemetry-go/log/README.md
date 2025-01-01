# Logging

This module's logging API resembles that of [github/go-log](https://github.com/github/go-log) and [github/go-kvp](https://github.com/github/go-kvp), which should make migrating from those libraries straightforward.

This module re-exports helper functions from the [github-semantic-conventions repo](https://github.com/github/github-semantic-conventions/tree/main/go).

## Basic Usage

Creating a logger is done like this:

```go
import (
 "github.com/github/github-telemetry-go/log"
 "github.com/github/github-telemetry-go/telemetry"
)

func main() {
 telem, err := telemetry.NewFromEnv()
 if err != nil {
  fmt.Printf("Failed configuring telemetry: %v", err)
  os.Exit(1)
 }

 defer func() {
  if err := telem.Shutdown(ctx); err != nil {
   fmt.Printf("failed to shutdown telemetry: %v", err)
   os.Exit(1)
  }
 }()

 logger := telem.Logger.WithFields(
   kvp.String("host.arch", "amd64"),
   kvp.String("cloud.platform", "aws_ec2"),
 )
 logger.Info("service has started")
}
```

### Global Logger

If you would like to have global access to the logger (in your current package), assign it to a global variable:

```go
var logger log.Logger

func main() {
 telem, err := telemetry.NewFromEnv()
 if err != nil {
  fmt.Printf("Failed configuring telemetry: %v", err)
  os.Exit(1)
 }
 logger = telem.Logger.Named("your-service-logger") // you can use any of the logger creation methods
 // ...
}
```
