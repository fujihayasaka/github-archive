// Package ingest provides logic to ingest one or more Go modules into
// the DG packages pipeline: the functionality common to the
// package-manager adaptor (gopma) and the one-off importer.
//
// It provides helper functions for two commands, not a public API.
package ingest

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"sync"
	"time"

	"golang.org/x/mod/modfile"
	"golang.org/x/mod/module"
	"golang.org/x/tools/go/vcs"
)

// flag variables
var (
	verbose  = false
	proxyURL = "https://proxy.golang.org"
	fjordURL = ""
)

// AddFlags exposes the ingest package's global variables as command-line flags.
func AddFlags(fs *flag.FlagSet) {
	fs.BoolVar(&verbose, "v", verbose, "enable verbose logging")
	fs.StringVar(&proxyURL, "proxy_url", proxyURL, "URL of Go proxy service")
	fs.StringVar(&fjordURL, "fjord_url", fjordURL, "URL of Fjord service (for package release events)")
}

// A ModuleVersion identifies a versioned module available from proxy.golang.org.
type ModuleVersion struct {
	// See proxy.golang.org for JSON protocol.
	Path      string    // e.g. "github.com/gobuffalo/fizz"
	Version   string    // e.g. "v1.0.12"
	Timestamp time.Time // microsecond granularity

	// Parsed go.mod file, or parse error.
	modfile *modfile.File
	// Source URL taken from go-import meta tag or derived from import path.
	sourceURL string
	err       error
}

func (mod *ModuleVersion) String() string {
	return fmt.Sprintf("%s@%s (%s)", mod.Path, mod.Version, mod.Timestamp.Format(RFC3339))
}

// RFC3339 is the microsecond-granularity timestamp format used by the Go index server.
const RFC3339 = "2006-01-02T15:04:05.999999Z07:00"

// A PackageRelease describes a new versioned package for the index.
// This type is described at ../README.md, but the canonical schema is
// the one accepted by Kafka:
//
//	https://github.com/github/hydro-schemas/blob/master/proto/hydro/schemas/github/dependencygraph/v0/package_release.proto
type PackageRelease struct {
	PackageManager string       `json:"package_manager"`
	PackageName    string       `json:"package_name"`
	PackageVersion string       `json:"package_version"`
	Dependencies   []Dependency `json:"dependencies,omitempty"`
	DocsURL        string       `json:"docs_url"`
	SourceURL      string       `json:"source_url,omitempty"`
	// + optional fields...
}

type Dependency struct {
	PackageName  string `json:"package_name"`
	Requirements string `json:"requirements"`
	// + optional fields...
}

// Process loads and parses the go.mod files of the specified modules
// from the module mirror (proxy.golang.org).
func Process(mods []*ModuleVersion) error {
	if len(mods) == 0 {
		return nil
	}
	last := mods[len(mods)-1].Timestamp
	log.Printf("got %d entries from %s before %s\n",
		len(mods),
		last.Sub(mods[0].Timestamp).Round(time.Second),
		last.Format(RFC3339))

	// Fetch go.mod files from proxy server in parallel, preserving order.
	sema := make(chan struct{}, 100) // concurrency-limiting counting semaphore
	var wg sync.WaitGroup
	wg.Add(len(mods))
	for _, mod := range mods {
		sema <- struct{}{} // acquire token
		go func(mod *ModuleVersion) {
			mod.modfile, mod.sourceURL, mod.err = parseModule(mod.Path, mod.Version)
			wg.Done()
			<-sema // release token
		}(mod)
	}
	wg.Wait()
	log.Printf("got modules from proxy") // for timing

	// -v: log packages
	if verbose {
		for _, mod := range mods {
			if mod.err != nil {
				log.Print(mod.err)
			} else {
				log.Printf("\t%s\n", mod)
				for _, req := range mod.modfile.Require {
					arrow := "->"
					if req.Indirect {
						arrow = "=>"
					}
					log.Printf("\t\t%s %s\n", arrow, req.Mod)
				}
			}
		}
	}

	// Emit JSON records in PackageRelease format.
	var releases []PackageRelease
	for _, mod := range mods {
		if mod.err != nil {
			// TODO(adonovan): extend protocol to display errors in the UI.
			// Otherwise users may be in the dark as to why their malformed
			// module is not being picked up.
			// See https://github.com/github/dependency-graph-api/issues/1917.
			log.Printf("Error parsing module %s: %s", mod.Path, mod.err)
			continue
		}

		release := PackageRelease{
			PackageManager: "go", // see ../../proto/twirp/v1/dependency_graph_api.proto
			PackageName:    mod.Path,
			PackageVersion: mod.Version,
			SourceURL:      mod.sourceURL,
			// It's tempting to add  "@version", but pkg.go.dev
			// serves a 404 for versions it hasn't indexed.
			DocsURL: "https://pkg.go.dev/" + mod.Path,
		}
		// A module's 'indirect' requirements are treated the same as direct ones,
		// analogous to a NPM package-lock.json file, because they are just
		// as necessary for determinism.
		// TODO(adonovan): handle Exclude, Replace, Retract?
		for _, req := range mod.modfile.Require {
			release.Dependencies = append(release.Dependencies, Dependency{
				PackageName:  req.Mod.Path,
				Requirements: req.Mod.Version,
			})
		}
		releases = append(releases, release)
	}

	defer log.Printf("posted events to Fjord") // for timing
	return postEvents(releases)
}

// ModuleBaseURL returns the base URL for proxy queries about a given module path.
// See https://golang.org/ref/mod#goproxy-protocol.
func ModuleBaseURL(path string) (string, error) {
	path, err := module.EscapePath(path)
	if err != nil {
		return "", fmt.Errorf("bad path: %v", err)
	}
	return proxyURL + "/" + path, nil
}

// parseModule fetches the go.mod file from the proxy server, then parses and
// returns the parsed mod file and the source url for the package.
func parseModule(path, version string) (*modfile.File, string, error) {
	// Escape path and version.
	baseURL, err := ModuleBaseURL(path)
	if err != nil {
		return nil, "", err
	}
	version, err = module.EscapeVersion(version)
	if err != nil {
		return nil, "", fmt.Errorf("bad version: %v", err)
	}

	// Fetch and parse go.mod file from module mirror.
	url := fmt.Sprintf("%s/@v/%s.mod", baseURL, version)

	// -v: performance debugging
	if verbose {
		t0 := time.Now()
		log.Println("begin parseModule", url)
		defer func() { log.Println("end parseModule", url, time.Since(t0)) }()
	}

	resp, err := http.Get(url)
	if err != nil {
		return nil, "", fmt.Errorf("GET go.mod file of %s: %v", path, err)
	}
	if resp.StatusCode != http.StatusOK {
		if resp.StatusCode == http.StatusGone {
			// TODO(adonovan): 410 Gone records. When the proxy tells us that a
			// go.mod no longer exists, how do we record this information to Fjord?
			return nil, "", fmt.Errorf("%s@%s gone", path, version)
		}
		return nil, "", fmt.Errorf("server returned error: %s", resp.Status)
	}
	defer resp.Body.Close() // ignore error
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, "", fmt.Errorf("reading HTTP response: %v", err)
	}
	parsed, err := modfile.Parse(url, data, nil)
	if err != nil {
		return nil, "", fmt.Errorf("parsing mod file: %v", err)
	}

	repoRoot, err := vcs.RepoRootForImportPath(path, false)
	if err != nil {
		return nil, "", fmt.Errorf("getting source path for %s: %v", path, err)
	}

	return parsed, repoRoot.Repo, nil
}

// -- Fjord --

// postEvents posts the PackageRelease events to Fjord.
func postEvents(releases []PackageRelease) error {
	var events []Event
	for _, release := range releases {
		value, err := json.Marshal(release)
		if err != nil {
			log.Fatalf("internal error: %v", err)
		}
		events = append(events, Event{
			Schema: "hydro.schemas.github.dependencygraph.v0.PackageRelease",
			Value:  string(value),
		})
	}
	if len(events) == 0 {
		log.Printf("events is empty, not posting to Fjord.")
		return nil
	}
	return HTTPJSON("POST", fjordURL+"/api/v1/events", FjordEvents{Events: events})
}

// FjordEvents describes the JSON payload of a Fjord /api/v1/events POST request.
// See README.md at https://github.com/github/fjord for the authoritative declaration.
type FjordEvents struct {
	Events []Event `json:"events"`
}

// An Event describes the JSON payload of a single Fjord event.
type Event struct {
	Cluster string `json:"cluster,omitempty"` // name of the hydro cluster (e.g. "localhost")
	Schema  string `json:"schema"`            // name of the hydro schema
	Value   string `json:"value"`             // JSON-encoded payload
	// + optional fields: timestamp, key, partition_key, topic
}

// HTTPJSON puts or posts the JSON encoding of payload to the specified URL.
func HTTPJSON(method, url string, payload interface{}) error {
	data, err := json.MarshalIndent(payload, "", "\t")
	if err != nil {
		log.Fatalf("internal error: %v", err)
	}
	// -v: debugging
	if verbose {
		log.Printf("%s\n", data)
	}
	req, err := http.NewRequest(method, url, bytes.NewReader(data))
	if err != nil {
		return fmt.Errorf("%s failed: %v", method, err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("ClientID", "dependency-graph-api") // (only needed for Fjord)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("%s failed: %v", method, err)
	}
	if resp.StatusCode != http.StatusOK {
		data, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("%s returned %s (%s)", method, resp.Status, data)
	}
	return nil
}
