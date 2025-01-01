package main

import (
	"flag"
	"os"
	"time"

	"github.com/github/launch/cli"
)

var seconds int64

func init() {
	flag.Int64Var(&seconds, "seconds", 1, "how many seconds should this sleep for")
}

/*
sleep implements the Sleep unix command in go launch is
run in production in a very compact docker container based
on scratch, which does not include any unix command line tools
this is needed in the Kubernetes preStop Hook, as described in
https://github.com/github/kube/blob/master/docs/handbook_files/next_steps.md#required-prestop-hook
the usage of sleep fixes a race condition in Kubernetes and GLB that
can cause unavailability during deployments
*/
func main() {
	cli.ParseFlags()
	time.Sleep(time.Second * time.Duration(seconds))
	os.Exit(0)
}
