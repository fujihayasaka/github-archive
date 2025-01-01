package ts_test

import (
	"bytes"
	"compress/gzip"
	"context"
	"encoding/base64"
	"io"
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/workflows"
	"github.com/stretchr/testify/require"
)

func TestGetRef(t *testing.T) {
	c := &ts.CodeqlRun{Ref: []byte("main")}
	require.Equal(t, "main", c.Ref.String())

	c = &ts.CodeqlRun{Ref: []byte("main")}
	require.Equal(t, "main", c.Ref.String())
}

func TestRunName(t *testing.T) {
	cr := &ts.CodeqlRun{
		Ref:             []byte("refs/pull/1/head"),
		TriggeringEvent: ts.CodeqlRunTriggeringEvent_PULL_REQUEST,
	}
	require.Equal(t, "PR #1", cr.RunName())

	cr = &ts.CodeqlRun{
		Ref:             []byte("refs/heads/main/branch"),
		TriggeringEvent: ts.CodeqlRunTriggeringEvent_PUSH,
	}
	require.Equal(t, "Push on main/branch", cr.RunName())

	cr = &ts.CodeqlRun{
		Ref:             []byte("refs/heads/main"),
		TriggeringEvent: ts.CodeqlRunTriggeringEvent_VALIDATION,
	}
	require.Equal(t, "CodeQL Setup", cr.RunName())

	// Ill formated PR ref
	cr = &ts.CodeqlRun{
		Ref:             []byte("refs/pul/1/had"),
		TriggeringEvent: ts.CodeqlRunTriggeringEvent_PULL_REQUEST,
	}
	require.Equal(t, "CodeQL", cr.RunName())

	// Ill formatted Push ref
	cr = &ts.CodeqlRun{
		Ref:             []byte("refs/hes/main"),
		TriggeringEvent: ts.CodeqlRunTriggeringEvent_PUSH,
	}
	require.Equal(t, "CodeQL", cr.RunName())
}

func TestCompressedWorkflow(t *testing.T) {
	template := workflows.NewLibrary().GetWorkflowTemplate(context.Background(), 0)
	wf, err := template.CodeQLWorkflow(&ts.CodeqlConfig{
		Languages: []string{"javascript"},
	})
	require.NoError(t, err)

	c := &ts.CodeqlRun{
		Workflow: wf,
	}

	b64, err := c.CompressedWorkflow()
	require.NoError(t, err)

	// Decompress
	gz, err := base64.StdEncoding.DecodeString(b64)
	require.NoError(t, err)

	r, err := gzip.NewReader(bytes.NewReader(gz))
	require.NoError(t, err)

	workflow, err := io.ReadAll(r)
	require.NoError(t, err)
	require.Equal(t, wf, string(workflow))
}

func TestPacksAsWorkflowString(t *testing.T) {
	var nilPack *ts.CodeqlPacks = nil
	require.Equal(t, "", nilPack.AsWorkflowString())

	equalPacks(t, "", "")
	equalPacks(t, "", "\n\n\n")
	equalPacks(t, "abc", "abc")
	equalPacks(t, "abc", "\nabc\n")
	equalPacks(t, "abc", "\n abc \n")
	equalPacks(t, "abc,def", "abc\ndef")
	equalPacks(t, "abc,def", " abc \n def ")
	equalPacks(t, "abc,def", " \n \nabc \n def \n ")
}

func equalPacks(t *testing.T, expected, actual string) {
	t.Helper()
	pack := ts.CodeqlPacks(actual)
	require.Equal(t, expected, (&pack).AsWorkflowString())
}
