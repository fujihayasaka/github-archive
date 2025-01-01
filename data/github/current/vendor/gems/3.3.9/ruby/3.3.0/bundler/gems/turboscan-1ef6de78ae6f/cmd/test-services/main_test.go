//go:build testallservices

package main_test

import (
	"bufio"
	"context"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"syscall"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	"github.com/github/turboscan/cmd/test-services/mockghghtwirp"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/hydro/publishers"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/sarif/store"
	"github.com/golang/protobuf/ptypes/timestamp"
	"github.com/google/uuid"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/require"
	"golang.org/x/exp/slices"
)

var Reset = "\033[0m"
var Red = "\033[31m"
var Green = "\033[32m"
var Yellow = "\033[33m"
var Purple = "\033[35m"

// startNewRepoService is a mock for the ghgh twirp server
func startNewRepoService(t *testing.T) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(mockghghtwirp.NewMockRepoServer())
	return srv
}

var debug bool

func init() {
	flag.BoolVar(&debug, "debug", false, "print all output to stdout for debugging")
}

func Log(t *testing.T, format string, args ...any) {
	t.Helper()
	if debug {
		t.Logf(format, args...)
	}
}

func setUpProcess(t *testing.T, ctx context.Context, name string, color string, repoSrvAddr string, args ...string) error {
	t.Helper()
	prefix := fmt.Sprintf("%s[%s] >> ", color, name)
	suffix := fmt.Sprintf("%s\n", Reset)
	Log(t, "%s STARTING UP%s", prefix, suffix)
	cmdArgs := []string{"run"}
	cmdArgs = append(cmdArgs, args...)
	cmd := exec.CommandContext(ctx, "go", cmdArgs...)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		Log(t, "%s%s%s%s", prefix, Red, err, suffix)
		return err
	}

	stderr, err := cmd.StderrPipe()
	if err != nil {
		Log(t, "%s%s%s%s", prefix, Red, err, suffix)
		return err
	}

	if name != "turboscansvc" {
		stdout = io.NopCloser(io.TeeReader(stdout, os.Stdout))
		stderr = io.NopCloser(io.TeeReader(stderr, os.Stderr))
	}

	in := bufio.NewScanner(stdout)
	cmd.Env = append(os.Environ(), "GITHUB_TWIRP_ADDR="+repoSrvAddr)
	err = cmd.Start()
	if err != nil {
		Log(t, "%s%s%s%s", prefix, Red, err, suffix)
		return err
	}

	go func() {
		for in.Scan() {
			Log(t, "%s%s%s", prefix, in.Text(), suffix)
		}
		if err := in.Err(); err != nil {
			Log(t, "%s%s%s%s", prefix, Red, err, suffix)
		}
	}()

	inErr := bufio.NewScanner(stderr)
	go func() {
		for inErr.Scan() {
			Log(t, "%s%s%s", prefix, inErr.Text(), suffix)
		}
		if err := inErr.Err(); err != nil {
			Log(t, "%s%s%s%s", prefix, Red, err, suffix)
		}
	}()

	go func() {
		err = cmd.Wait()
		Log(t, "%s%sQUIT UNEXPECTEDLY: %s%s", prefix, Red, err, suffix)
	}()
	return nil
}

func TestServices(t *testing.T) {
	_, path, _, _ := runtime.Caller(0)
	err := os.Chdir(filepath.Join(filepath.Dir(path), "..", ".."))
	require.NoError(t, err)

	flag.Parse()
	ctx, cancel := context.WithCancel(context.Background())
	go func() {
		defer cancel()
		c := make(chan os.Signal, 1)
		signal.Notify(c, os.Interrupt)
		<-c
		os.Exit(0)
	}()

	srv := startNewRepoService(t)
	defer srv.Close()

	t.Log("setting up...")

	err = setUpProcess(t, ctx, "turboscansvc", Green, srv.URL, "./cmd/turboscan", "service", "start", "turboscansvc")
	require.NoError(t, err)
	err = setUpProcess(t, ctx, "hydrosvc", Yellow, srv.URL, "./cmd/turboscan", "service", "start", "hydrosvc")
	require.NoError(t, err)
	err = setUpProcess(t, ctx, "aqueductsvc", Purple, srv.URL, "./cmd/aqueductsvc")
	require.NoError(t, err)

	t.Log("waiting for turboscansvc...")

	tryFor(t, 1*time.Minute, func() bool {
		resp, err := http.Get("http://127.0.0.1:8888/_ping")
		if errors.Is(err, syscall.ECONNREFUSED) {
			return false
		}
		if err != nil {
			return false
		}
		defer resp.Body.Close()
		return true
	})

	t.Log("starting test...")

	cfg, err := config.Load()
	require.NoError(t, err)

	logger, err := cfg.NewLogger()
	require.NoError(t, err)

	cwd, err := os.Getwd()
	require.NoError(t, err)
	sarifPath := filepath.Join(cwd, "cmd/test-services/testdata", "example.sarif")
	guids, err := sendToHydro(ctx, logger, cfg, []string{sarifPath})
	require.NoError(t, err)

	client := proto.NewResultsJSONClient("http://127.0.0.1:8888", http.DefaultClient)
	require.NotNil(t, client)
	var successfulGuids []string
	tryFor(t, 1*time.Minute, func() bool {
		for _, guid := range guids {
			if slices.Contains(successfulGuids, guid) {
				continue
			}
			resp, err := client.GetDelivery(ctx, &proto.DeliveryRequest{
				RepositoryId: 123,
				SarifId:      guid,
			})
			if err != nil {
				return false
			}
			if resp.Errors != nil {
				t.Errorf("failed with errors %v", resp.Errors)
				return true
			}
			if resp.AnalysisCount > 0 {
				successfulGuids = append(successfulGuids, guid)
			}
		}
		return len(successfulGuids) == len(guids)
	})
	tryFor(t, 1*time.Minute, func() bool {
		alerts, err := client.GetAlerts(ctx, &proto.AlertsRequest{
			RepositoryId: 123,
		})
		require.NoError(t, err)
		return alerts.TotalCount > 0
	})
	alerts, err := client.GetAlerts(ctx, &proto.AlertsRequest{
		RepositoryId: 123,
	})
	require.NoError(t, err)
	require.Equal(t, alerts.TotalCount, uint64(2))
}

func tryFor(t *testing.T, d time.Duration, predicateFunc func() bool) bool {
	t.Helper()
	timeout := time.After(d)
	for {
		select {
		case <-timeout:
			t.Errorf("failed because of timeout")
			return false
		default:
			if predicateFunc() {
				return true
			}
			time.Sleep(100 * time.Millisecond)
		}
	}
}

func sendToHydro(ctx context.Context, logger log.Logger, cfg *config.Config, paths []string) (guids []string, err error) {
	sarifStore := store.NewSarifStore(cfg.GetStorageEngine(), cfg)
	if err := sarifStore.Open(ctx); err != nil {
		return nil, err
	}
	defer sarifStore.Close(ctx)

	kc, err := cfg.NewKafkaConfig(logger, nil)
	if err != nil {
		return nil, err
	}
	publisher, err := publishers.New(*kc, stats.NullStatter)
	if err != nil {
		return nil, err
	}

	for _, path := range paths {
		logger.Info(fmt.Sprintf("Parsing file %s", path))
		f, err := os.Open(path)
		if err != nil {
			return guids, errors.Wrapf(err, "reading SARIF file %s has failed", path)
		}

		guid := uuid.NewString()
		guids = append(guids, guid)
		uri := "testing/" + guid
		err = sarifStore.Upload(ctx, f, uri)
		if err != nil {
			return guids, errors.Wrapf(err, "uploading SARIF file %s has failed", path)
		}
		logger.Info(fmt.Sprintf("SARIF file %s uploaded", path))

		msg := makeAnalysis(uri, guid)
		err = publisher.NewAnalysis(ctx, msg)
		if err != nil {
			return guids, errors.Wrapf(err, "sending SARIF file %s has failed", path)
		}
		logger.Info(fmt.Sprintf("%s sent to hydro", path))
	}
	return guids, nil
}

// makeAnalysis returns a protobuf Analysis from the commandline args and the provided uri
func makeAnalysis(uri string, guid string) *tshydro.Analysis {
	var startTime *timestamp.Timestamp
	msg := &tshydro.Analysis{
		SarifId:            guid,
		RepositoryId:       123,
		SourceRepositoryId: 123,
		RepoNwo:            "github/code-scanning",
		SarifUri:           uri,
		CommitOid:          "1234567890abcdef1234567890abcdef12345678",
		Ref:                []byte("refs/heads/main"),
		AnalysisName:       "CodeQL",
		AnalysisKey:        "codeql",
		CheckoutUri:        "",
		Environment:        "testing",
		WorkflowRunId:      123,
		BuildStartAt:       startTime,
	}

	return msg
}
