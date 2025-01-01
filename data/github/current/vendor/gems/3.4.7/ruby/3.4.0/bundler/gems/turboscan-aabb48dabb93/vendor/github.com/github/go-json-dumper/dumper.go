package jsondumper

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
)

const exitInternalError = 128
const exitFailuresPresent = 1
const exitFailuresAbsent = 0

type DumpJankyOpts struct {
	teeWriter io.Writer
}

type DumpJankyOpt func(*DumpJankyOpts)

func WithTeeWriter(teeWriter io.Writer) DumpJankyOpt {
	return func(opts *DumpJankyOpts) {
		opts.teeWriter = teeWriter
	}
}

// DumpJankyJSONFromFile reads the input file and dumps the Janky JSON output to the writer.
// Returns an exit code and an error if one is needed.
func DumpJankyJSONFromFile(out io.Writer, filename string, opts ...DumpJankyOpt) (int, error) {
	f, err := os.Open(filename)
	if err != nil {
		return exitInternalError, err
	}
	defer f.Close()
	return DumpJankyJSON(out, f, opts...)
}

// DumpJankyJSON reads the Go test JSON output from the input stream
// and dumps the Janky JSON output to the writer.
func DumpJankyJSON(out io.Writer, in io.Reader, opts ...DumpJankyOpt) (int, error) {
	dumpOpts := &DumpJankyOpts{}
	for _, opt := range opts {
		opt(dumpOpts)
	}

	failures, err := parseGoTestJSON(in, dumpOpts.teeWriter)
	if err != nil {
		return exitInternalError, err
	}
	if len(failures) == 0 {
		return exitFailuresAbsent, nil
	}
	encoder := json.NewEncoder(out)
	encoder.SetIndent("", "  ")
	for _, test := range failures {
		if _, err := fmt.Fprintln(out, "===FAILURE==="); err != nil {
			return exitInternalError, err
		}
		if err := encoder.Encode(test); err != nil {
			return exitInternalError, err
		}
		if _, err := fmt.Fprintln(out, "===END FAILURE==="); err != nil {
			return exitInternalError, err
		}
	}
	return exitFailuresPresent, nil
}
