// See https://github.com/dnaeon/go-vcr/
//
// The logic for the recorder could probably be re-implemented.
// I decided to fork this implementation as it is very close to what
// we need.
//
// The key differences are:
// - The Cassette struct from go-vcr is not compatible with the ruby VCR
//   format. It contains more fields than we want but also uses url vs uri.
// - The Cassette struct is not just used for serialization, but also contains
//   logic that should really live in the Recorder (filters, replayed, matcher).
// - When replaying the cassette, latency information is default on.
//
// We modify the recorder to use our VCR struct (this should also give us more
// freedom to customize the format in the future), and move all the interesting
// logic from the Cassette to the Recorder.
//

// Copyright (c) 2015-2016 Marin Atanasov Nikolov <dnaeon@gmail.com>
// Copyright (c) 2016 David Jack <davars@gmail.com>
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions
// are met:
// 1. Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer
//    in this position and unchanged.
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE AUTHOR(S) ``AS IS'' AND ANY EXPRESS OR
// IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
// OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
// IN NO EVENT SHALL THE AUTHOR(S) BE LIABLE FOR ANY DIRECT, INDIRECT,
// INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
// NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
// THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

package recorder

import (
	"bytes"
	"encoding/base64"
	"errors"
	"io"
	"io/ioutil"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	_ "github.com/dnaeon/go-vcr/v2/recorder" // Import to make dependency/licensing information explicit.
	"github.com/github/turbocassette/vcr"
	"gopkg.in/yaml.v3"
)

// Mode represents recording/playback mode
type Mode int

// Recorder states
const (
	ModeRecording Mode = iota
	ModeReplaying
	ModeDisabled
	// Replay record from cassette or record a new one when a request is not
	// present in cassette instead of throwing ErrInteractionNotFound
	ModeReplayingOrRecording
)

var (
	// ErrInteractionNotFound indicates that a requested
	// interaction was not found in the cassette file
	ErrInteractionNotFound = errors.New("Requested interaction not found")

	ErrCassetteNotFound = errors.New("Cassette not found")
)

// Recorder represents a type used to record and replay
// client and server interactions
type Recorder struct {
	// Operating mode of the recorder
	mode Mode

	// Mutex to lock accessing cassette
	Mu sync.RWMutex

	// Cassette used by the recorder
	cassette *vcr.Cassette

	// CassetteFPath is the file path of the cassette
	cassetteFPath string

	// realTransport is the underlying http.RoundTripper to make real requests
	realTransport http.RoundTripper
}

// SetTransport can be used to configure the behavior of the 'real' client used in record-mode
func (r *Recorder) SetTransport(t http.RoundTripper) {
	r.realTransport = t
}

// GetInteraction retrieves a recorded request/response interaction
func (r *Recorder) GetInteraction(req *http.Request) (*vcr.Interaction, error) {
	r.Mu.Lock()
	defer r.Mu.Unlock()
	for _, i := range r.cassette.Interactions {
		if strings.EqualFold(req.Method, i.Request.Method) && strings.EqualFold(req.URL.String(), i.Request.URI) {
			return i, nil
		}
	}

	return nil, ErrInteractionNotFound
}

// AddInteraction appends a new interaction to the cassette
func (r *Recorder) AddInteraction(i *vcr.Interaction) {
	r.Mu.Lock()
	r.cassette.Interactions = append(r.cassette.Interactions, i)
	r.Mu.Unlock()
}

// Proxies client requests to their original destination
func (r *Recorder) requestHandler(req *http.Request) (*vcr.Interaction, error) {
	// Return interaction from cassette if in replay mode or replay/record mode
	if r.mode == ModeReplaying || r.mode == ModeReplayingOrRecording {
		if err := req.Context().Err(); err != nil {
			return nil, err
		}

		if interaction, err := r.GetInteraction(req); r.mode == ModeReplaying {
			return interaction, err
		} else if r.mode == ModeReplayingOrRecording && err == nil {
			return interaction, err
		}
	}

	reqBody := &bytes.Buffer{}
	if req.Body != nil && req.Body != http.NoBody {
		// Record the request body so we can add it to the cassette
		req.Body = io.NopCloser(io.TeeReader(req.Body, reqBody))
	}

	// Perform client request to it's original
	// destination and record interactions
	resp, err := r.realTransport.RoundTrip(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	encodings := map[string]vcr.Encoding{"application/protobuf": vcr.Base64Encoding}

	vcrReqBody := vcr.NewBody(reqBody.String(), encodings[req.Header.Get("Content-Type")])
	vcrRespBody := vcr.NewBody(string(respBody), encodings[resp.Header.Get("Content-Type")])

	// Add interaction to cassette
	interaction := &vcr.Interaction{
		Request: &vcr.Request{
			Body:    vcrReqBody,
			Headers: req.Header,
			URI:     req.URL.String(),
			Method:  req.Method,
		},
		Response: &vcr.Response{
			Body:    vcrRespBody,
			Headers: resp.Header,
			Status: &vcr.Status{
				Message: &resp.Status,
				Code:    resp.StatusCode,
			},
		},
		RecordedAt: time.Now().String(),
	}
	r.AddInteraction(interaction)

	return interaction, nil
}

// New creates a new recorder
func New(cassetteName string) (*Recorder, error) {
	// Default mode is "replay" if file exists
	return NewAsMode(cassetteName, ModeReplaying, nil)
}

// NewAsMode creates a new recorder in the specified mode
func NewAsMode(cassetteName string, mode Mode, realTransport http.RoundTripper) (*Recorder, error) {
	var r = &Recorder{
		mode:          mode,
		realTransport: realTransport,
		cassetteFPath: cassetteName,
	}

	if r.realTransport == nil {
		r.realTransport = http.DefaultTransport
	}

	// Disabled mode has no cassette
	if mode == ModeDisabled {
		return r, nil
	}

	// Check if the cassette exists
	if _, err := os.Stat(cassetteName); os.IsNotExist(err) {
		// Replaying mode should fail if no cassette exists
		if mode == ModeReplaying {
			return nil, ErrCassetteNotFound
		}

		// Otherwise we are in a recording mode, create new cassette and enter in recording mode
		r.cassette = &vcr.Cassette{}
		r.mode = ModeRecording

		return r, nil
	}

	// Load cassette from file and enter replay mode or replay/record mode
	if err := r.LoadCassette(); err != nil {
		return nil, err
	}

	return r, nil
}

// Stop is used to stop the recorder and save any recorded interactions
func (r *Recorder) Stop() error {
	if r.mode == ModeRecording || r.mode == ModeReplayingOrRecording {
		if err := r.SaveCassette(); err != nil {
			return err
		}
	}

	return nil
}

// RoundTrip implements the http.RoundTripper interface
func (r *Recorder) RoundTrip(req *http.Request) (*http.Response, error) {
	if r.mode == ModeDisabled {
		return r.realTransport.RoundTrip(req)
	}

	// Pass Recorder to handler
	interaction, err := r.requestHandler(req)

	if err != nil {
		return nil, err
	}

	select {
	case <-req.Context().Done():
		return nil, req.Context().Err()
	default:
		var buf *bytes.Buffer
		// Decode Base64
		if interaction.Response.Body.Encoding == "base64" {
			d, err := base64.StdEncoding.DecodeString(interaction.Response.Body.String)
			if err != nil {
				return nil, err
			}
			buf = bytes.NewBuffer(d)
		} else {
			buf = bytes.NewBuffer([]byte(interaction.Response.Body.String))
		}

		contentLength := int64(buf.Len())
		// For HTTP HEAD requests, the ContentLength should be set to the size
		// of the body that would have been sent for a GET.
		// https://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.13
		if req.Method == "HEAD" {
			if hdr := interaction.Response.Headers.Get("Content-Length"); hdr != "" {
				cl, err := strconv.ParseInt(hdr, 10, 64)
				if err == nil {
					contentLength = cl
				}
			}
		}
		resp := &http.Response{
			StatusCode:    interaction.Response.Status.Code,
			Proto:         "HTTP/1.0",
			ProtoMajor:    1,
			ProtoMinor:    0,
			Request:       req,
			Header:        interaction.Response.Headers,
			Close:         true,
			ContentLength: contentLength,
			Body:          io.NopCloser(buf),
		}
		if interaction.Response.Status.Message != nil {
			resp.Status = *interaction.Response.Status.Message
		}
		return resp, nil
	}
}

// CancelRequest implements the github.com/coreos/etcd/client.CancelableTransport interface
func (r *Recorder) CancelRequest(req *http.Request) {
	type cancelableTransport interface {
		CancelRequest(req *http.Request)
	}
	if ct, ok := r.realTransport.(cancelableTransport); ok {
		ct.CancelRequest(req)
	}
}

// Mode returns recorder state
func (r *Recorder) Mode() Mode {
	return r.mode
}

// Load reads a cassette file from disk
func (r *Recorder) LoadCassette() error {
	r.Mu.Lock()
	defer r.Mu.Unlock()

	data, err := ioutil.ReadFile(r.cassetteFPath)
	if err != nil {
		return err
	}
	r.cassette = &vcr.Cassette{}
	err = yaml.Unmarshal(data, r.cassette)

	return err
}

// Save writes the cassette data on disk for future re-use
func (r *Recorder) SaveCassette() (err error) {
	r.Mu.RLock()
	defer r.Mu.RUnlock()
	c := r.cassette

	// Save cassette file only if there were any interactions made
	if len(c.Interactions) == 0 {
		return nil
	}

	c.RecordedWith = "Turbocassette"

	// Create directory for cassette if missing
	cassetteDir := filepath.Dir(r.cassetteFPath)
	if _, err = os.Stat(cassetteDir); os.IsNotExist(err) {
		if err = os.MkdirAll(cassetteDir, 0755); err != nil {
			return err
		}
	}

	// Marshal to YAML and save interactions
	data, err := yaml.Marshal(c)
	if err != nil {
		return err
	}

	f, err := os.Create(r.cassetteFPath)
	if err != nil {
		return err
	}

	defer func() {
		closeErr := f.Close()
		if err == nil {
			err = closeErr
		}
	}()

	// Honor the YAML structure specification
	// http://www.yaml.org/spec/1.2/spec.html#id2760395
	_, err = f.Write([]byte("---\n"))
	if err != nil {
		return err
	}

	_, err = f.Write(data)
	if err != nil {
		return err
	}

	return nil
}
