// This is an integration test of the "go" package-manager adapter
// (PMA). It runs gopma, providing it with fake versions of all four
// services. The fake versions of the two source services
// (({index,proxy}.golang.org) provide constant data, and the test
// checks that gopma has the correct effects on the two sink services
// (DG API and Fjord).
//
// The test runs gopma as a child process and treats it as a black
// box. It is fully deterministic and does not depend on the clock.
package main_test

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"os/exec"
	"testing"
	"time"

	gopma "github.com/github/dependency-graph-api/ecosystem/go/gopma"
	"github.com/github/dependency-graph-api/ecosystem/go/internal/ingest"
	"github.com/google/go-cmp/cmp"
)

// TODO(adonovan): clean-up:
// - extract the Checkpoint API from gopma main package, and don't import main.
// - abstract the handler behavior away from the global init so we can run multiple tests.

var buildFlag = flag.Bool("build", true, "build the executable to test; false under Docker")

func TestMain(m *testing.M) {
	flag.Parse()

	// Run 'go build' in this directory to produce gopma executable.
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
	serve("localhost:12346", indexServer)
	serve("localhost:12347", fjordServer)
	serve("localhost:12348", depgraphServer)

	os.Exit(m.Run())
}

func serve(addr string, fn http.HandlerFunc) {
	go func() {
		if err := http.ListenAndServe(addr, fn); err != nil {
			log.Fatal(err)
		}
	}()
}

func TestBasics(t *testing.T) {
	// Run the gopma process against the fake services.
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	cmd := exec.CommandContext(
		ctx,
		"./gopma",
		"-proxy_url=http://localhost:12345",
		"-index_url=http://localhost:12346",
		"-fjord_url=http://localhost:12347",
		"-api_url=http://localhost:12348",
		"-poll=100ms") // small interval => faster test
	cmd.Stdout = os.Stderr
	cmd.Stderr = os.Stderr
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}

	// Record interactions with fake handlers until we have 2 checkpoints.
	var gotEvents []ingest.Event
	var gotCheckpoint []string
loop:
	for {
		select {
		case ev := <-events:
			gotEvents = append(gotEvents, ev)
		case cp := <-checkpoints:
			gotCheckpoint = append(gotCheckpoint, cp.String())
			if len(gotCheckpoint) == 2 {
				break loop
			}
		case <-ctx.Done():
			t.Error("timeout")
			break loop
		}
	}
	cmd.Process.Kill()
	cmd.Wait()

	// Check accumulated values.
	wantCheckpoints := []string{
		"2020-01-01 12:00:00.123459 +0000 UTC",
		"2020-01-01 13:00:00.000001 +0000 UTC",
	}
	if delta := cmp.Diff(wantCheckpoints, gotCheckpoint); delta != "" {
		t.Errorf("checkpoints differ: %s", delta)
	}
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
			// Cluster: "localhost", ??
			Schema: "hydro.schemas.github.dependencygraph.v0.PackageRelease",
			Value:  string(value),
		}
	}
	wantEvents := []ingest.Event{
		event("github.com/a/one/repo/name", "v1.0.0", "https://github.com/a/one"),
		event("gopkg.in/yaml.v2", "v1.2.0", "https://gopkg.in/yaml.v2",
			ingest.Dependency{PackageName: "bitbucket.org/ai69/popua", Requirements: "v1.3.0"}),
		event("bitbucket.org/ai69/popua", "v1.3.0", "https://bitbucket.org/ai69/popua.git"),
		event("gopkg.in/yaml.v2", "v1.3.0", "https://gopkg.in/yaml.v2"),
	}
	if delta := cmp.Diff(wantEvents, gotEvents); delta != "" {
		t.Errorf("events differ: %s", delta)
	}
}

var (
	events      = make(chan ingest.Event)
	checkpoints = make(chan time.Time)
)

// indexServer fakes https://index.golang.org.
func indexServer(w http.ResponseWriter, req *http.Request) {
	log.Println("index", req.URL)
	req.ParseForm() // ignore error
	since := req.Form.Get("since")
	if since < "2020-01-01T12:00:00.123458Z" {
		fmt.Fprintf(w, `
{"Path":"github.com/a/one/repo/name","Version":"v1.0.0","Timestamp":"2020-01-01T12:00:00.123456Z"}
{"Path":"gopkg.in/yaml.v2","Version":"v1.2.0","Timestamp":"2020-01-01T12:00:00.123457Z"}
{"Path":"bitbucket.org/ai69/popua","Version":"v1.3.0","Timestamp":"2020-01-01T12:00:00.123458Z"}`)
	} else if since < "2020-01-01T13:00:00.000000Z" {
		fmt.Fprintf(w, `{"Path":"gopkg.in/yaml.v2","Version":"v1.3.0","Timestamp":"2020-01-01T13:00:00.000000Z"}`)
	} else {
		// no more records
	}
}

// proxyServer fakes https://proxy.golang.org.
func proxyServer(w http.ResponseWriter, req *http.Request) {
	log.Println("proxy", req.URL)
	var s string
	switch req.URL.String() {
	case "/github.com/a/one/repo/name/@v/v1.0.0.mod":
		s = "module github.com/a/one/repo/name"
	case "/gopkg.in/yaml.v2/@v/v1.2.0.mod":
		s = "module gopkg.in/yaml.v2\n\ngo 1.21.0\ntoolchain go1.21.0\n\nrequire bitbucket.org/ai69/popua v1.3.0"
	case "/bitbucket.org/ai69/popua/@v/v1.3.0.mod":
		s = "module bitbucket.org/ai69/popua"
	case "/gopkg.in/yaml.v2/@v/v1.3.0.mod":
		s = "module gopkg.in/yaml.v2"
	default:
		log.Printf("Returned 404 for %q", req.URL.String())
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

// depgraphServer fakes the Dependency Graph API service.
func depgraphServer(w http.ResponseWriter, req *http.Request) {
	log.Println("depgraph", req.Method, req.URL)

	// Assume /checkpoints/gopma
	switch req.Method {
	case "PUT":
		var check gopma.Checkpoint
		if err := readJSON(req, &check); err != nil {
			log.Printf("depgraph: %v", err)
		}
		checkpoints <- time.Unix(0, check.Value).UTC()

	case "GET":
		// Always return the Jan 1, 1970, regardless of PUTs.
		ancient := time.Unix(0, 0)
		if err := writeJSON(w, gopma.Checkpoint{Value: ancient.UnixNano()}); err != nil {
			log.Printf("depgraph: %v", err)
		}
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

// writeJSON writes the JSON encoding of x into w.
func writeJSON(w http.ResponseWriter, x interface{}) error {
	w.Header().Set("Content-Type", "application/json")
	data, err := json.Marshal(x)
	if err != nil {
		return err
	}
	_, err = w.Write(data)
	return err
}
