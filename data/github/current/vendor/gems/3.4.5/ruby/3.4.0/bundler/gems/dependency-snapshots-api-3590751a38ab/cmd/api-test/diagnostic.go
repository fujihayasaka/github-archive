package main

import (
	"context"
	"flag"
	"fmt"
	"net/http"
	"os"

	"github.com/github/dependency-snapshots-api/internal/command"
	"github.com/github/dependency-snapshots-api/pkg/proto"
)

func diagnosticCommand(c *command.Command) error {
	flagSet := flag.NewFlagSet("diagnostic", flag.ExitOnError)
	serviceURLFlag := newServiceURLFlag(flagSet)

	if len(os.Args) < 3 {
		return command.NewUsageError("usage: api-test diagnostic <ping/boom> [additional options]\n", flagSet)
	}

	cmd := os.Args[2]
	err := flagSet.Parse(os.Args[3:])
	if err != nil {
		return err
	}

	service := proto.NewDiagnosticServiceProtobufClient(*serviceURLFlag, &http.Client{})

	if cmd == "Ping" {
		request := &proto.PingRequest{}
		fmt.Printf("Calling Twirp server at %s with ping...\n", *serviceURLFlag)
		response, err := service.Ping(context.Background(), request)
		if err != nil {
			return err
		}
		fmt.Printf("Received response from server: %s\n", response)
	} else if cmd == "Boom" {
		request := &proto.BoomRequest{}
		fmt.Printf("Calling Twirp server at %s with boom...\n", *serviceURLFlag)
		response, err := service.Boom(context.Background(), request)
		if err != nil {
			return err
		}
		fmt.Printf("Received response from server: %s\n", response)
	}

	return nil
}
