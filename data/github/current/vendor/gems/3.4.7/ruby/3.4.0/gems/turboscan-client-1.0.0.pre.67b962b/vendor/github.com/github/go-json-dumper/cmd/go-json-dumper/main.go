package main

import (
	"flag"
	"io"
	"log"
	"os"

	jsondumper "github.com/github/go-json-dumper"
)

func main() {
	tee := flag.Bool("tee", false, "")
	flag.Parse()
	var exitCode int
	var err error
	var teeWriter io.Writer
	if *tee {
		teeWriter = os.Stdout
	}

	if flag.NArg() >= 1 {
		for _, input := range flag.Args() {
			exitCode, err = jsondumper.DumpJankyJSONFromFile(
				os.Stdout,
				input,
				jsondumper.WithTeeWriter(teeWriter),
			)
			if err != nil {
				log.Fatalf("unable to dump %q: %+v", input, err)
			}
		}
	} else {

		exitCode, err = jsondumper.DumpJankyJSON(
			os.Stdout,
			os.Stdin,
			jsondumper.WithTeeWriter(teeWriter),
		)
		if err != nil {
			log.Fatalf("unable to dump stdin: %+v", err)
		}
	}

	os.Exit(exitCode)
}
