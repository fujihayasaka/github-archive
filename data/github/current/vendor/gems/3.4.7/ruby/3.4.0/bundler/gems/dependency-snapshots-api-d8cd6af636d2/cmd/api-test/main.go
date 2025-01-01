package main

import (
	"errors"
	"flag"
	"log"
	"os"

	"github.com/github/dependency-snapshots-api/internal/command"
)

var allCommands = []command.Command{
	{Name: "diagnostic", Desc: "Interacts with the diagnostic service", Execute: diagnosticCommand},
}

func newServiceURLFlag(f *flag.FlagSet) *string {
	return f.String("url", "http://localhost:9597", "The url of the Twirp server")
}

func main() {
	if err := realMain(); err != nil {
		log.Fatalf("failed to run service: %v", err)
	}
}

func realMain() error {
	if len(os.Args) < 2 {
		return errors.New("usage: twirp-test <command> [additional options]\n" + command.ListCommands(allCommands))
	}

	return command.DispatchCommand(os.Args[1], allCommands)
}
