package pprof

import (
	"bytes"
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"runtime"
	"runtime/pprof"
	"strconv"
	"strings"

	"github.com/github/go-crpc/v2"
)

// ProfileChatop provides a new pprof chatop that allow you to get the pprof profile
// snapshots of the following standard profiles:
//
//   "goroutine"
//   "threadcreate"
//   "heap"
//   "allocs"
//   "block"
//   "mutex"
//
// As an example to get the the allocs profile, assuming the chatop is
// registered to the `foo` namespace with the `pprof` method:
//
//   .foo pprof --profile allocs
//     or
//   hubot foo pprof --profile allocs
//
// Results are displayed as an attachment and needs to be downloaded. By
// default the files are gzipped, base64 encoded. Here is one example how to
// decode it back so `go tool pprof` can understand it:
//
//   cat downloaded-file | base64 --decode > allocs.pb.gz
//
// The downloaded and decoded file can be then passed to directly to go tool:
//
//   go tool pprof allocs.pb.gz
//
// To get a human friendly text, pass the "--debug 1" option.
func ProfileChatop() *crpc.GenericChatop {
	return crpc.NewGenericChatop(
		"pprof",
		"pprof --profile <profile> [--debug N] [--gc] - get pprof output for the given profile (see https://pkg.go.dev/runtime/pprof#Profile)",
		"pprof",
		profileCmd,
	)
}

func profileCmd(ctx context.Context, req *crpc.CommandRequest) (*crpc.CommandResponse, error) {
	profile, ok := req.Params["profile"]
	if !ok {
		return nil, errors.New("no profile is specified")
	}

	p := pprof.Lookup(profile)
	if p == nil {
		return nil, fmt.Errorf("unknown profile: %s. Current allowed profiled: %s",
			profile, knownProfiles())
	}

	// this is copied from the /net/http/pprof endpoints and the `heap`
	// profile has an option to run garbage collector if the `gc` value is
	// passed
	if _, ok := req.Params["gc"]; ok && profile == "heap" {
		runtime.GC()
	}

	debug := 0 // by default use gzipped protobuf
	var err error
	if d, ok := req.Params["debug"]; ok {
		debug, err = strconv.Atoi(d)
		if err != nil {
			return nil, fmt.Errorf("invalid value of '--debug': %s is not an integer", d)
		}
	}

	var buf bytes.Buffer
	if err := p.WriteTo(&buf, debug); err != nil {
		return nil, err
	}

	resp := &crpc.CommandResponse{
		Attachment: true,
	}

	// pprof writes data in text format if debug is not zero. Return it
	// back that way for easy readiness, but if debug is set to zero, it writes it in gzipped
	// protobuf format, so return a base64 encoded string to Slack doesn't
	// mess-up with the content.
	// https://github.com/golang/go/blob/a1550d3ca3a6a90b8bbb610950d1b30649411243/src/runtime/pprof/pprof.go#L428
	resp.Result = buf.String()
	if debug == 0 { // gzipped protobuf
		resp.Result = base64.StdEncoding.EncodeToString(buf.Bytes())
	}

	return resp, nil
}

// knownProfiles returns the current profiles as human friendly string to be
// displayed in error messages
func knownProfiles() string {
	var b strings.Builder
	b.WriteString("[")
	for i, p := range pprof.Profiles() {
		b.WriteString(p.Name())
		if i != len(pprof.Profiles())-1 {
			b.WriteString(", ")
		}
	}
	b.WriteString("]")

	return b.String()
}
