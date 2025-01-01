package fromctx

import (
	"github.com/github/turboghas/internal/flipper"
	"github.com/simon-engledew/ctxkey"
)

var Flipper = ctxkey.New[flipper.Flipper](flipper.NullFlipper)
