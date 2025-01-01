package main

import (
	"context"
	"fmt"
	"os"

	errs "github.com/pkg/errors"

	"github.com/github/launch/cli"
	"github.com/github/launch/utils/appcontext"
)

func main() {
	cli.ParseFlags()
	metadata := cli.GetApplicationMetadata("migratorctl")

	ctx, err := appcontext.InitializeWithRequestID(context.Background(), metadata, "migratorctl")
	if err != nil {
		panic(errs.Wrap(err, "could not setup metadata %+v"))
	}

	rootCmd := getRootCommand(ctx)

	if err := rootCmd.Execute(); err != nil {
		fmt.Println("error executing command: ", err)
		os.Exit(1)
	}
}
