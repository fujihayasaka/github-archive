// The gopma command is the Dependency Graph (DG) package-manager
// adaptor (PMA) for Go's module system.  It polls the Go module index
// server (index.golang.org) for new Go modules known to the proxy
// server (proxy.golang.org), then loads the go.mod file for each one
// from that server, and emits a record of the module and its
// dependency edges into Fjord. After each successful update, the
// timestamp checkpoint is recorded in the DG API service.
//
// The program fails if any of the Go, Fjord, or DG services are
// unavailable.
//
// By default, it exits after each request, which is useful for
// testing. Given a positive -poll duration, it runs forever; this is
// useful for rapidly backfilling the database, and for reducing the
// latency of ingestion of new packages.
//
// Further reading:
// - Go module reference: https://golang.org/ref/mod
// - Go Module Mirror & Index servers: https://proxy.golang.org
// - ../README.md: general information on PMAs.
// - Go module in GitHub's Dependency Graph: ../../../../docs/go-modules.md
//
// Integration testing:
// - Run 'go test' in this directory to run gopma_test, an automated
//   integration test using fake implementations of the four services.
//   Alternatively, use script/test for the Dockerized version.
// - For manual integration testing against real services,
//   run Kafka, Fjord, and Depgraph locally.
//   - Fjord:
//      $ (cd fjord && script/server --docker) &
//   - Depgraph:
//      $ (cd dependency-graph-api && script/server) &
//   - This program, reading actual data from the last hour:
//      $ (cd dependency-graph-api/package_manager_adapters && script/start go -since 1h)
//   It may be preferable to use the 'staging' Fjord and Kafka instances
//   production, but I have not tried that.
//
// To monitor the progress of package ingestion in production, see:
//   https://app.datadoghq.com/dashboard/9im-uhe-hwd/dg-package-manager-adapters
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"time"

	"github.com/github/dependency-graph-api/ecosystem/go/internal/ingest"
)

// flags
var (
	apiURL       = flag.String("api_url", "", "URL of DG API service (for checkpoints)")
	pollInterval = flag.Duration("poll", 0, "index server polling interval (default: run once and exit")
	// testing only:
	indexURL  = flag.String("index_url", "https://index.golang.org", "URL of Go index service")
	sinceFlag = flag.Duration("since", 0, "start of query window, before now (default: zero, meaning use last checkpoint)")
)

func main() {
	ingest.AddFlags(flag.CommandLine) // -v -fjord_url -proxy_url
	flag.Parse()

	// Set initial time for request.
	var t0 time.Time
	if *sinceFlag != 0 {
		// Use recent duration from -since flag.
		t0 = time.Now().UTC().Add(-*sinceFlag)
	} else {
		// Read last checkpoint.
		if cp, err := loadCheckpoint(); err != nil {
			log.Fatal(err)
		} else {
			t0 = cp
		}
	}

	// Each iteration requests entries not earlier than t0.
	for {
		log.Printf("t0 = %s", t0.Format(ingest.RFC3339))

		// Get next batch of 2000 entries, which is the server's limit.
		// The log starts at 2019-04-10. As of Mar 2021 it holds 3.5M entries,
		// and 2000 entries is a couple of hours' data.
		// We poll it, like tail -f.
		const limit = 2000
		url := fmt.Sprintf("%s/index?limit=%d&since=%s",
			*indexURL, limit, t0.Format(ingest.RFC3339))
		resp, err := http.Get(url)
		if err != nil {
			log.Fatalf("GET request failed: %v", err)
		}
		if resp.StatusCode != http.StatusOK {
			log.Fatalf("index.golang.org request failed: %s", resp.Status)
		}

		dec := json.NewDecoder(resp.Body)
		var mods []*ingest.ModuleVersion
		for {
			mod := new(ingest.ModuleVersion)
			if err := dec.Decode(mod); err != nil {
				if err != io.EOF {
					log.Fatalf("Server returned invalid JSON: %v", err)
				}
				break
			}
			mods = append(mods, mod)
		}
		if err := resp.Body.Close(); err != nil {
			log.Fatalf("closing HTTP response: %v", err)
		}

		// Process the records.
		if err := ingest.Process(mods); err != nil {
			log.Fatal(err)
		}

		// Advance the cursor timestamp by at least ε = 1μs, and persist it.
		//
		// This ensures that the request URL differs each time.
		// Otherwise, if a request returned no results, and we repeat
		// the same request, HTTP caching in the CDN may return the
		// same empty response, even if the server has new records,
		// causing us to get stuck.
		//
		// This also ensures that we don't get stuck on a run of
		// >=2000 records with the same timestamp. Instead of
		// re-requesting the whole run, we discard the suffix that
		// was truncated by the limit. This should be vanishingly rare.
		if n := len(mods); n > 0 {
			t0 = mods[n-1].Timestamp
		}
		t0 = t0.Add(1 * time.Microsecond)
		if err := saveCheckpoint(t0); err != nil {
			log.Fatal(err)
		}

		// Stop, in one-shot 'cron' mode. (Loop in 'backfill' mode.)
		if *pollInterval <= 0 {
			break
		}

		// Delay before reading next batch, to reduce server load.
		delay := *pollInterval
		if len(mods) == limit {
			// Possibly incomplete result? Reduce delay while catching up.
			delay = 100 * time.Millisecond
		}

		time.Sleep(delay)
	}
}

// --- DG API ---

// loadCheckpoint reads the last checkpoint timestamp from the DG API server.
func loadCheckpoint() (time.Time, error) {
	resp, err := http.Get(*apiURL + "/checkpoints/gopma")
	if err != nil {
		return time.Time{}, fmt.Errorf("checkpoint GET request failed: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		return time.Time{}, fmt.Errorf("checkpoint request returned %s", resp.Status)
	}
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return time.Time{}, fmt.Errorf("reading checkpoint response: %v", err)
	}
	var cp Checkpoint
	if err := json.Unmarshal(data, &cp); err != nil {
		return time.Time{}, fmt.Errorf("decoding checkpoint JSON: %v", err)
	}
	return time.Unix(0, cp.Value).UTC(), nil
}

// saveCheckpoint reads the last checkpoint timestamp from the DG API server.
func saveCheckpoint(t time.Time) error {
	return ingest.HTTPJSON("PUT", *apiURL+"/checkpoints/gopma", Checkpoint{Value: t.UnixNano()})
}

// A Checkpoint is the state recorded by the DG API server; see checkpoints_controller.rb.
type Checkpoint struct {
	Value int64 `json:"value"` // nanoseconds since UNIX epoch, UTC
}
