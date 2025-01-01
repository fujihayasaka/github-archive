package stats

import (
	"errors"
	"io"
	"time"

	"github.com/github/go-stats"
)

type clientMock interface { //nolint:deadcode,unused // used in tests
	stats.Client
}

// NewClient returns a new stats.Client with potentially a discardable sink.
//
// There must be only a single instance of the statter client to make sure that
// the buffering logic of the client works correctly. This is not enforced.
//
// For more info you can check "A note on buffering" on
// https://github.com/github/go-stats#a-note-on-buffering
func NewClient(addr, prefix, env string) (stats.Client, error) {
	var sink io.Writer
	switch addr {
	case "":
		return nil, errors.New("sink can't be empty")
	case "IGNORE":
		sink = io.Discard
	default:
		sink = stats.UDPSink(addr)
	}
	return stats.NewClient(sink, time.Second, prefix).WithTags(stats.Tags{"deploy_env": env}), nil
}
