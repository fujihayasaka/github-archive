package hydro

import (
	"fmt"

	"github.com/github/github-telemetry-go/log"
)

// LoggerAdapterForHydro
// This adapter exists to enable us to pass our github-telemetry-go log.Logger to
// the Hydro client's SetKafkaLogger() function. That function expects a Logger
// which implements the standard Logger interface, which github-telemetry-go's
// log.Logger does not implement.
type LoggerAdapterForHydro struct {
	Logger log.Logger
}

func (lafh *LoggerAdapterForHydro) Print(_ ...interface{}) {
	// Do nothing since we don't want to log Hydro messages to Splunk
}

func (lafh *LoggerAdapterForHydro) Println(_ ...interface{}) {
	// Do nothing since we don't want to log Hydro messages to Splunk
}

func (lafh *LoggerAdapterForHydro) Printf(_ string, _ ...interface{}) {
	// Do nothing since we don't want to _ Hydro messages to Splunk
}

func (lafh *LoggerAdapterForHydro) Panic(args ...interface{}) {
	msg := fmt.Sprint(args...)
	lafh.Logger.Fatal(msg)
}

func (lafh *LoggerAdapterForHydro) Panicf(msg string, args ...interface{}) {
	m := fmt.Sprintf(msg, args...)
	lafh.Logger.Fatal(m)
}
func (lafh *LoggerAdapterForHydro) Panicln(args ...interface{}) {
	msg := fmt.Sprintln(args...)
	lafh.Logger.Fatal(msg)
}

func (lafh *LoggerAdapterForHydro) Fatal(args ...interface{}) {
	msg := fmt.Sprint(args...)
	lafh.Logger.Fatal(msg)
}

func (lafh *LoggerAdapterForHydro) Fatalf(msg string, args ...interface{}) {
	m := fmt.Sprintf(msg, args...)
	lafh.Logger.Fatal(m)
}

func (lafh *LoggerAdapterForHydro) Fatalln(args ...interface{}) {
	msg := fmt.Sprintln(args...)
	lafh.Logger.Fatal(msg)
}
