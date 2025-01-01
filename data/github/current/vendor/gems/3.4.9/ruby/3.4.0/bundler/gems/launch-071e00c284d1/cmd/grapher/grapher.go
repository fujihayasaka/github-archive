package main

import (
	"fmt"

	"github.com/github/go-config/v2"

	"github.com/github/launch/cli"
	"github.com/github/launch/pkg/abreaker"
)

// See `docs/circuit-breakers.md` for usage
func main() {
	cfg := abreaker.Config{}
	err := config.Load(&cfg)
	if err != nil {
		panic(err)
	}
	cli.ParseFlags()
	d, err := GenerateCircuitBreakerTuningDashboard(cfg)
	if err != nil {
		panic(err)
	}
	fmt.Print(d)
}
