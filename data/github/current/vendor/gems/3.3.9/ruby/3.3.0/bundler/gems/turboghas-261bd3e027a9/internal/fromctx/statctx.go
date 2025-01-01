package fromctx

import (
	"github.com/github/go-stats"
	"github.com/simon-engledew/ctxkey"
)

var Statter = ctxkey.New[stats.Client](stats.NullStatter)
