// The gooneoff command retrieves information about the named Go module
// and sends a PackageRelease record to Fjord, in a similar manner to
// the inner loop of the Go package-mananger adaptor (gopma).
//
// For an overview, see "Go module support in Dependency Graph", ../../../../docs/go-modules.md.
package main

import (
	"encoding/json"
	"flag"
	"io/ioutil"
	"log"
	"net/http"
	"time"

	"github.com/github/dependency-graph-api/ecosystem/go/internal/ingest"
)

func main() {
	// Parse flags.
	ingest.AddFlags(flag.CommandLine)
	flag.Parse()
	if flag.NArg() != 1 {
		log.Fatalf("usage: gooneoff module")
	}
	path := flag.Args()[0]

	// Request latest module version from https://proxy.golang.org/$module/@latest.
	// See https://golang.org/ref/mod#goproxy-protocol.
	baseURL, err := ingest.ModuleBaseURL(path)
	if err != nil {
		log.Fatalf("forming proxy URL: %v", err)
	}
	resp, err := http.Get(baseURL + "/@latest")
	if err != nil {
		log.Fatalf("GET request failed: %v", err)
	}
	data, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		log.Fatalf("reading response: %v", err)
	}
	resp.Body.Close() // ignore error
	if resp.StatusCode != http.StatusOK {
		if len(data) > 240 {
			data = append(data[:237], "..."...)
		}
		log.Fatalf("proxy.golang.org request failed: %s (body: %s)", resp.Status, data)
	}

	var info struct {
		Version string    // version string
		Time    time.Time // commit time
	}
	if err := json.Unmarshal(data, &info); err != nil {
		log.Fatalf("server returned invalid JSON: %v", err)
	}

	// Process the sole record.
	mods := []*ingest.ModuleVersion{{
		Path:      path,
		Version:   info.Version,
		Timestamp: info.Time,
	}}
	if err := ingest.Process(mods); err != nil {
		log.Fatal(err)
	}
}
