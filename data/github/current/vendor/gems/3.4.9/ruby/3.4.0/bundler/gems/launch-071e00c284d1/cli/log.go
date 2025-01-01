package cli

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
)

// SetupLogging sets the log prefix and output.
func SetupLogging() {
	log.SetPrefix(fmt.Sprintf("[%s] ", filepath.Base(os.Args[0])))
	log.SetOutput(os.Stderr)
}
