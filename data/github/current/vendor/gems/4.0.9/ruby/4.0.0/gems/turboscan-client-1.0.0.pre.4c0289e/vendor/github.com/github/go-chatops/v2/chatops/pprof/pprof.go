// Package pprof provides chatop profile functionality.
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
	"time"

	"github.com/github/go-chatops/v2"
)

// defaultCPUProfileSeconds is the default duration of a CPU profile when the
// caller does not specify the `--seconds` option. It matches the default used
// by net/http/pprof.
const defaultCPUProfileSeconds = 30
const maxCPUProfileSeconds = 60

// ProfileChatop provides a new pprof chatop that allow you to get the pprof profile
// snapshots of the following standard profiles:
//
//	"goroutine"
//	"threadcreate"
//	"heap"
//	"allocs"
//	"block"
//	"mutex"
//
// In addition to the standard profiles above, the special "cpu" profile is
// supported, which captures a CPU profile over a configurable duration via
// runtime/pprof.StartCPUProfile.
//
// As an example to get the allocs profile, assuming the chatop is
// registered to the `foo` namespace with the `pprof` method:
//
//	.foo pprof --profile allocs
//	  or
//	hubot foo pprof --profile allocs
//
// To get a CPU profile for the default 30 seconds:
//
//	.foo pprof --profile cpu
//
// Or specify a custom duration in seconds:
//
//	.foo pprof --profile cpu --seconds 10
//
// Results are displayed as an attachment and needs to be downloaded. By
// default the files are gzipped, base64 encoded. Here is one example how to
// decode it back so `go tool pprof` can understand it:
//
//	cat downloaded-file | base64 --decode > allocs.pb.gz
//
// The downloaded and decoded file can be then passed to directly to go tool:
//
//	go tool pprof allocs.pb.gz
//
// To get a human friendly text, pass the "--debug 1" option. Note that
// "--debug" is not supported for the "cpu" profile.
func ProfileChatop() *chatops.GenericChatop {
	return chatops.NewGenericChatop(
		"pprof",
		"pprof --profile <profile> [--debug N] [--gc] [--seconds N] - get pprof output for the given profile (see https://pkg.go.dev/runtime/pprof#Profile). Use --profile cpu [--seconds N] for a CPU profile.",
		"pprof",
		profileCmd,
	)
}

func profileCmd(ctx context.Context, req *chatops.CommandRequest) (*chatops.CommandResponse, error) {
	profile, ok := req.Params["profile"]
	if !ok {
		return nil, errors.New("no profile is specified")
	}

	if profile == "cpu" {
		return cpuProfileCmd(ctx, req)
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
		//nolint:revive // this GC call is intentional and part of the profile functionality
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

	resp := &chatops.CommandResponse{
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

// cpuProfileCmd captures a CPU profile for a configurable duration. The
// duration defaults to defaultCPUProfileSeconds and can be overridden via the
// `--seconds` option. The resulting profile is gzipped protobuf and is
// returned base64 encoded, matching the format used for the other profiles
// when `--debug` is 0.
func cpuProfileCmd(ctx context.Context, req *chatops.CommandRequest) (*chatops.CommandResponse, error) {
	if _, ok := req.Params["debug"]; ok {
		return nil, errors.New("the '--debug' option is not supported for the 'cpu' profile")
	}

	seconds := defaultCPUProfileSeconds
	if s, ok := req.Params["seconds"]; ok {
		var err error
		seconds, err = strconv.Atoi(s)
		if err != nil {
			return nil, fmt.Errorf("invalid value of '--seconds': %s is not an integer", s)
		}
		if seconds <= 0 {
			return nil, fmt.Errorf("invalid value of '--seconds': %d must be greater than 0", seconds)
		}
		if seconds > maxCPUProfileSeconds {
			return nil, fmt.Errorf("invalid value of '--seconds': %d must be less than or equal to %d", seconds, maxCPUProfileSeconds)
		}
	}

	var buf bytes.Buffer
	if err := pprof.StartCPUProfile(&buf); err != nil {
		return nil, fmt.Errorf("could not start CPU profile: %w", err)
	}

	timer := time.NewTimer(time.Duration(seconds) * time.Second)
	defer timer.Stop()
	select {
	case <-timer.C:
	case <-ctx.Done():
		pprof.StopCPUProfile()
		return nil, ctx.Err()
	}
	pprof.StopCPUProfile()

	return &chatops.CommandResponse{
		Attachment: true,
		Result:     base64.StdEncoding.EncodeToString(buf.Bytes()),
	}, nil
}

// knownProfiles returns the current profiles as human friendly string to be
// displayed in error messages.
func knownProfiles() string {
	profiles := pprof.Profiles()
	names := make([]string, 0, len(profiles)+1)
	for _, p := range profiles {
		names = append(names, p.Name())
	}
	names = append(names, "cpu")

	return "[" + strings.Join(names, ", ") + "]"
}
