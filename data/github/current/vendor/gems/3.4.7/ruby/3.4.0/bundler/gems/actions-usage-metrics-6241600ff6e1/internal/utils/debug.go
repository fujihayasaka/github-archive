package utils

import (
	"os"
	"time"

	"github.com/github/github-telemetry-go/log"
)

func WaitForDebugger() {
	if _, err := os.Stat("/dbg/go/bin/dlv"); os.IsNotExist(err) {
		return
	}

	// wait for debugger
	log.Info("waiting for debugger to attach...")
	attached := 0
	for attached == 0 {
		time.Sleep(1 * time.Second)
	}
}
