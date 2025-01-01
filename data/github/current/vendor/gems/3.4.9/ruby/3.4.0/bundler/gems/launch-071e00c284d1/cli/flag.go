package cli

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
)

var (
	// BuildVersion gets set to the current SHA while building (see script/build)
	BuildVersion = "unknown"

	// MuVersion gets set to mu's current SHA while building (see script/build)
	MuVersion = "unknown"

	// BinaryName is the base filename of the binary being run.
	BinaryName = filepath.Base(os.Args[0])

	// Arguments defines any non-flag arguments the CLI is expecting.
	// This is printed in the help text if present.
	// Usage of flags instead of arguments is strongly recommended.
	Arguments = ""
)

// DefaultUsage is the function which should be called when help text is printed.
// It's meant to override the default flag.Usage function.
var DefaultUsage = func() {
	UsageWithVersion()
	flag.PrintDefaults()
}

// UsageWithVersion prints only the first line of the usage help text.
// It includes the BuildVersion for version verification.
func UsageWithVersion() {
	_, err := fmt.Fprintf(os.Stderr, "Usage: %s %s\n", BinaryName, Arguments)
	if err != nil {
		panic(err)
	}
}

// ParseFlags sets the flag.Usage to cli.Usage, and parses the flags.
func ParseFlags() {
	flag.Usage = DefaultUsage
	showVersion := flag.Bool("version", false, "Show version and exit")
	flag.Parse()

	if *showVersion {
		ShowVersionAndExit()
	}
}

// ShowVersionAndExit prints the binary's name, its version, and then the program exits.
//
// Use this when a "-version" flag is provided.
func ShowVersionAndExit() {
	_, err := fmt.Printf("%s version %s\n", BinaryName, BuildVersion)
	if err != nil {
		panic(err)
	}
	os.Exit(0)
}
