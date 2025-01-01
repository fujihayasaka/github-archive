package services

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"

	"github.com/github/launch/observability"
)

// Service is the public interface for backgrounded services that don't require a graceful shutdown
type Service interface {
	Run(context.Context) error
}

// GracefulService is the public interface for any long-lived client or worker processes that should perform a
// graceful shutdown (with a timeout window provided by the context.Context)
type GracefulService interface {
	Service
	Shutdown(context.Context) error
}

func RunServices(ctx context.Context, obs *observability.Observability, services ...Service) error {
	var hardStop sync.WaitGroup

	serviceCtx, shutdownAll := context.WithCancel(ctx)

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)

	obs.Debug(ctx, "graceful shutdown: signal handler set")
	timeout := 65 * time.Second

	hardStop.Add(1)
	go func() {
		// Shutdown the non-graceful services by cancelling the serviceCtx
		defer func() {
			shutdownAll()
			hardStop.Done()
		}()

		// Received stop signal (SIGINT/SIGTERM)
		<-stop
		obs.Debug(ctx, "graceful shutdown: triggered by signal")

		var gracefulStop sync.WaitGroup
		for _, service := range services {
			if graceful, ok := service.(GracefulService); ok {
				gracefulStop.Add(1)
				go func() {
					component := fmt.Sprintf("%T", graceful)
					componentKvp := kvp.String("component", component)
					obs.Debug(ctx, "graceful shutdown: triggered on component", componentKvp)

					ctx, cancel := context.WithTimeout(context.Background(), timeout)
					defer func() {
						cancel()
						gracefulStop.Done()
					}()

					if err := graceful.Shutdown(ctx); err != nil {
						obs.Error(ctx, "graceful shutdown: component-level shutdown error", kvp.Err(err), componentKvp)
					}
				}()
			}
		}
		gracefulStop.Wait()
	}()

	once := &sync.Once{}
	for _, srv := range services {
		hardStop.Add(1)

		go func(srv Service) {
			defer hardStop.Done()

			component := fmt.Sprintf("%T", srv)
			componentKvp := kvp.String("component", component)
			obs.Debug(ctx, "RunServices: component up and running", componentKvp)

			err := srv.Run(serviceCtx)
			triggerGlobalShutdown(once)

			if err != nil {
				// don't log context cancellations to Sentry since they are our graceful shutdown signal!
				if err == context.Canceled {
					// constants.LastError.Set("shutdown: global context cancelled") // triggers k8s liveness prob 5xx
					obs.Debug(ctx, "shutdown: global context cancelled", componentKvp)
				} else {
					// constants.LastError.Set(err.Error()) // triggers k8s liveness probe 5xx

					pairs := []kvp.Field{
						kvp.String("exception.message", "unrecoverable runtime error"),
						kvp.Err(err),
						componentKvp,
					}
					obs.Error(ctx, "shutdown: unsuccessful", pairs...)
					obs.Report(ctx, errors.Wrap(err, "unable to shutdown"), pairs...)
				}
			}
		}(srv)
	}
	hardStop.Wait()
	return nil
}

// trigger GracefulService(s) to begin shutdown sequence, ending with ctx cancellation for Run()'ing Services
func triggerGlobalShutdown(once *sync.Once) {
	once.Do(func() {
		syscall.Kill(syscall.Getpid(), syscall.SIGINT) //nolint:errcheck,gosec
	})
}
