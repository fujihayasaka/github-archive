// Package fromctx provides context helpers for storing and retrieving a logger.
package fromctx

import (
	"github.com/github/github-telemetry-go/log"
	"github.com/simon-engledew/ctxkey"
)

var Logger = ctxkey.New[log.Logger](log.NewNullLogger())
