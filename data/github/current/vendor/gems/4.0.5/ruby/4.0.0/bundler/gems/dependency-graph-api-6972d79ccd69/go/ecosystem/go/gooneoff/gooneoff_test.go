// This is an integration test of the "go" one-off adapter.  It runs
// gooneoff, providing it with fake versions of the proxy.golang.org
// (source) and Fjord (sink). The test runs gooneoff as a child process
// and treats it as a black box. It is fully deterministic and does
// not depend on the clock.
package main_test

import (
	"context"
	"encoding/json"
	"flag"
	"io"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"os/exec"
	"testing"
	"time"

	"github.com/github/dependency-graph-api/ecosystem/go/internal/ingest"
	"github.com/google/go-cmp/cmp"
)

var buildFlag = flag.Bool("build", true, "build the executable to test; false under Docker")

func TestMain(m *testing.M) {
	flag.Parse()

	// Run 'go build' in this directory to produce gooneoff executable.
	// This is used when testing with 'go test' directly,
	// and assumes access to source and toolchain.
	// Under Docker, the test executable is pre-built.
	if *buildFlag {
		cmd := exec.Command("go", "build")
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err != nil {
			log.Fatal(err)
		}
	}

	serve("localhost:12345", proxyServer)
	serve("localhost:12346", fjordServer)

	os.Exit(m.Run())
}

func serve(addr string, fn http.HandlerFunc) {
	go func() {
		if err := http.ListenAndServe(addr, fn); err != nil {
			log.Fatal(err)
		}
	}()
}

func Test(t *testing.T) {
	// Run the gooneoff process against the fake services.
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	cmd := exec.CommandContext(
		ctx,
		"./gooneoff",
		"-proxy_url=http://localhost:12345",
		"-fjord_url=http://localhost:12346",
		"github.com/a/one")
	cmd.Stdout = os.Stderr
	cmd.Stderr = os.Stderr
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}

	// Wait until we receive events or timeout.
	var gotEvents []ingest.Event
	select {
	case ev := <-events:
		gotEvents = append(gotEvents, ev)
	case <-ctx.Done():
		t.Error("timeout")
	}
	cmd.Process.Kill()
	cmd.Wait()

	// Check accumulated values.

	// TODO(adonovan): factor with gopma_test (and perhaps even with
	// production code, though we need one test of the actual values).
	event := func(pkgname, version, source string, deps ...ingest.Dependency) ingest.Event {
		value, err := json.Marshal(ingest.PackageRelease{
			PackageManager: "go",
			PackageName:    pkgname,
			PackageVersion: version,
			DocsURL:        "https://pkg.go.dev/" + pkgname,
			SourceURL:      source,
			Dependencies:   deps,
		})
		if err != nil {
			log.Fatal(err)
		}
		return ingest.Event{
			Schema: "hydro.schemas.github.dependencygraph.v0.PackageRelease",
			Value:  string(value),
		}
	}
	wantEvents := []ingest.Event{
		event("github.com/a/one", "v1.2.3+blah", "https://github.com/a/one",
			ingest.Dependency{PackageName: "c.com/c", Requirements: "v1.3.0"}),
	}
	if delta := cmp.Diff(wantEvents, gotEvents); delta != "" {
		t.Errorf("events differ: %s", delta)
	}
}

var events = make(chan ingest.Event)

// proxyServer fakes https://proxy.golang.org.
func proxyServer(w http.ResponseWriter, req *http.Request) {
	log.Println("proxy", req.URL)
	var s string
	switch req.URL.String() {
	case "/github.com/a/one/@latest":
		s = `{"Version":"v1.2.3+blah","Time":"2021-05-28T05:35:13Z"}`
	case "/github.com/a/one/@v/v1.2.3+blah.mod":
		s = "module github.com/a/one\n\ngo 1.1\n\nrequire c.com/c v1.3.0"
	default:
		w.WriteHeader(404)
	}
	io.WriteString(w, s)
}

// fjordServer fakes the Fjord service.
func fjordServer(w http.ResponseWriter, req *http.Request) {
	log.Println("fjord", req.Method, req.URL)

	// Assume POST /api/v1/events
	var fjordEvents ingest.FjordEvents
	if err := readJSON(req, &fjordEvents); err != nil {
		log.Printf("fjord: %v", err)
	}

	for _, ev := range fjordEvents.Events {
		events <- ev
	}
}

// readJSON decodes JSON data from req.Body into the variable pointed to by x.
func readJSON(req *http.Request, x interface{}) error {
	data, err := ioutil.ReadAll(req.Body)
	if err != nil {
		return err
	}
	return json.Unmarshal(data, x)
}
