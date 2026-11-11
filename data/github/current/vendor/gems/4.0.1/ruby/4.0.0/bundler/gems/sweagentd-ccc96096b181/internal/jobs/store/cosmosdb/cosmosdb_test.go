package cosmosdb

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/command"
	db "github.com/github/sweagentd/internal/jobs/store"
	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/require"
)

func TestCosmosDB_CreateJob(t *testing.T) {
	didPostJob := false
	svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPost {
			didPostJob = true
			require.Equal(t, "/dbs/db-id/colls/jobs/docs", r.URL.Path)

			body, err := io.ReadAll(r.Body)
			require.NoError(t, err)
			defer r.Body.Close()

			// Check that the request body contains the expected JSON
			// structure for the job
			var jobBody map[string]any
			err = json.Unmarshal(body, &jobBody)
			require.NoError(t, err)

			// Check that the job ID is present
			require.Equal(t, "test-job", jobBody["id"].(string))
		}

		w.WriteHeader(http.StatusCreated)
		_, err := fmt.Fprint(w, `{"_rid":"test","_self":"test","_etag":"test","_ts":1234567890, "id":"test-job"}`)
		require.NoError(t, err)
	}))
	t.Cleanup(svr.Close)

	raw := "fakeBase64String"
	base64Str := base64.StdEncoding.EncodeToString([]byte(raw))
	connectionStr := fmt.Sprintf("AccountEndpoint=%s;AccountKey=%s", svr.URL+"/", base64Str)

	obsv := observability.NewNoopExporters()

	store, err := NewCosmosJobStore(obsv, &CosmosJobStoreOpts{
		ConnectionString:       connectionStr,
		DatabaseID:             "db-id",
		JobsContainerID:        "jobs",
		AssignmentsContainerID: "assignments",
		CommandsContainerID:    "commands",
		ProgressContainerID:    "progress",
	})
	require.NoError(t, err)
	require.NotNil(t, store)

	ctx := context.Background()
	j, err := store.CreateJob(ctx, &jobs.Job{
		ID: "test-job",
	})
	require.True(t, didPostJob)
	require.NoError(t, err)
	require.Equal(t, "test-job", j.ID)
}

func TestCosmosDB_CreateCommand(t *testing.T) {
	didPost := false
	svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPost {
			didPost = true
			require.Equal(t, "/dbs/db-id/colls/commands/docs", r.URL.Path)

			body, err := io.ReadAll(r.Body)
			require.NoError(t, err)
			defer r.Body.Close()

			var cmdBody map[string]any
			err = json.Unmarshal(body, &cmdBody)
			require.NoError(t, err)

			require.Equal(t, "test-command", cmdBody["id"].(string))
		}
		w.WriteHeader(http.StatusCreated)
		_, err := fmt.Fprint(w, `{"_rid":"test","_self":"test","_etag":"test","_ts":1234567890, "id":"test-command"}`)
		require.NoError(t, err)
	}))
	t.Cleanup(svr.Close)

	raw := "fakeBase64String"
	base64Str := base64.StdEncoding.EncodeToString([]byte(raw))
	connectionStr := fmt.Sprintf("AccountEndpoint=%s;AccountKey=%s", svr.URL+"/", base64Str)

	obsv := observability.NewNoopExporters()

	store, err := NewCosmosJobStore(obsv, &CosmosJobStoreOpts{
		ConnectionString:       connectionStr,
		DatabaseID:             "db-id",
		JobsContainerID:        "jobs",
		AssignmentsContainerID: "assignments",
		CommandsContainerID:    "commands",
		ProgressContainerID:    "progress",
	})
	require.NoError(t, err)
	require.NotNil(t, store)

	ctx := context.Background()
	cmd := &command.Command{ID: "test-command", AssignmentID: "assignment-id", JobID: "job-id"}
	c, err := store.CreateCommand(ctx, cmd)
	require.True(t, didPost)
	require.NoError(t, err)
	require.Equal(t, "test-command", c.ID)
}

func TestCosmosDB_BatchPatchCommands(t *testing.T) {
	t.Run("no commands is a noop", func(t *testing.T) {
		// Server should not receive any batch specific call because we pass empty slice
		svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// Only allow create command calls if they happen (they shouldn't for this test)
			w.WriteHeader(http.StatusOK)
			_, err := fmt.Fprint(w, `{"_rid":"test","_self":"test","_etag":"test","_ts":1234567890}`)
			require.NoError(t, err)
		}))
		t.Cleanup(svr.Close)

		raw := "fakeBase64String"
		base64Str := base64.StdEncoding.EncodeToString([]byte(raw))
		connectionStr := fmt.Sprintf("AccountEndpoint=%s;AccountKey=%s", svr.URL+"/", base64Str)

		obsv := observability.NewNoopExporters()

		store, err := NewCosmosJobStore(obsv, &CosmosJobStoreOpts{
			ConnectionString:       connectionStr,
			DatabaseID:             "db-id",
			JobsContainerID:        "jobs",
			AssignmentsContainerID: "assignments",
			CommandsContainerID:    "commands",
			ProgressContainerID:    "progress",
		})
		require.NoError(t, err)

		err = store.BatchPatchCommands(context.Background(), []*command.Command{}, db.CommandPatch{Status: nil})
		require.NoError(t, err, "empty slice should be a noop")
	})

	t.Run("mismatched assignment/job IDs returns error before network batch", func(t *testing.T) {
		// We only need to support the initial CreateCommand calls (POST). After that, the
		// BatchPatchCommands should fail prior to performing a network request for the batch.
		var createCount int
		svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.Method == http.MethodGet { // allow any GETs performed by SDK during initialization
				w.WriteHeader(http.StatusOK)
				return
			}
			if r.Method == http.MethodPost && strings.Contains(r.URL.Path, "/colls/commands/docs") {
				createCount++
				w.WriteHeader(http.StatusCreated)
				_, err := fmt.Fprint(w, `{"_rid":"test","_self":"test","_etag":"\"etag\"","_ts":1234567890, "id":"ignored"}`)
				require.NoError(t, err)
				return
			}
			// Any unexpected non-GET request should fail the test (e.g. a batch patch call which shouldn't occur)
			t.Fatalf("unexpected request: %s %s", r.Method, r.URL.Path)
		}))
		t.Cleanup(svr.Close)

		raw := "fakeBase64String"
		base64Str := base64.StdEncoding.EncodeToString([]byte(raw))
		connectionStr := fmt.Sprintf("AccountEndpoint=%s;AccountKey=%s", svr.URL+"/", base64Str)

		obsv := observability.NewNoopExporters()

		store, err := NewCosmosJobStore(obsv, &CosmosJobStoreOpts{
			ConnectionString:       connectionStr,
			DatabaseID:             "db-id",
			JobsContainerID:        "jobs",
			AssignmentsContainerID: "assignments",
			CommandsContainerID:    "commands",
			ProgressContainerID:    "progress",
		})
		require.NoError(t, err)

		ctx := context.Background()
		c1 := &command.Command{ID: "cmd-1", AssignmentID: "a-1", JobID: "j-1"}
		c2 := &command.Command{ID: "cmd-2", AssignmentID: "a-2", JobID: "j-1"}

		_, err = store.CreateCommand(ctx, c1)
		require.NoError(t, err)
		_, err = store.CreateCommand(ctx, c2)
		require.NoError(t, err)
		require.Equal(t, 2, createCount, "expected two create calls")

		err = store.BatchPatchCommands(ctx, []*command.Command{c1, c2}, db.CommandPatch{})
		require.Error(t, err)
		msg := err.Error()
		require.True(t, strings.Contains(msg, "assignment and job") || strings.Contains(msg, "batch operation"), "expected mismatch error, got: %s", msg)
	})
}
