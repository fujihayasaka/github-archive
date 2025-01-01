//go:build ignore
// +build ignore

package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"

	"github.com/github/launch/clients/freno"
)

func main() {
	addr := flag.String("addr", "http://freno.service.github.net:8111", "")
	app := flag.String("app", "github", "")
	dbtype := flag.String("dbtype", "mysql", "")
	cluster := flag.String("cluster", "launch", "")
	flag.Parse()

	fr, err := freno.NewClient(*addr)
	if err != nil {
		log.Fatal(err)
	}

	ctx := context.Background()

	res, err := fr.Check(ctx, *app, *dbtype, *cluster)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Fprintf(os.Stdout, `check for app %q in cluster %q of %q
can_write:       %v
replication_lag: %v
threshold:       %v
message:         %v
`, *app, *cluster, *dbtype,
		res.CanWrite,
		res.ReplicationLag,
		res.Threshold,
		res.Message,
	)
}
