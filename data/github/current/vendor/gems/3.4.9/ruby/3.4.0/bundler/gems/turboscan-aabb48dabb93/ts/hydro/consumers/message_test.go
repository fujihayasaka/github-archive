package consumers_test

import (
	"testing"

	envelope "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	hydro_schemas_code_scanning_v0 "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	"github.com/github/turboscan/ts/hydro/consumers"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
)

func WrapEnvelope(t *testing.T, msg []byte) []byte {
	t.Helper()

	env := &envelope.Envelope{Message: msg}
	data, err := proto.Marshal(env)
	require.NoError(t, err)

	return data
}

func WrapAnalysisMessage(t *testing.T, a *hydro_schemas_code_scanning_v0.Analysis) []byte {
	t.Helper()

	data, err := proto.Marshal(a)
	require.NoError(t, err)
	return data
}

func TestCloneAnalysisMessage(t *testing.T) {
	clone := consumers.CloneAnalysisMessage(&hydro_schemas_code_scanning_v0.Analysis{CommitOid: "deadbeef"})
	require.Equal(t, clone.CommitOid, "deadbeef")
}

func TestUnwrap(t *testing.T) {
	data := WrapEnvelope(t, WrapAnalysisMessage(t, &hydro_schemas_code_scanning_v0.Analysis{CommitOid: "deadbeef"}))
	var e envelope.Envelope
	require.NoError(t, consumers.UnwrapEnvelope(data, &e))
	var a hydro_schemas_code_scanning_v0.Analysis
	require.NoError(t, consumers.UnwrapAnalysisMessage(e.Message, &a))
	require.Equal(t, a.CommitOid, "deadbeef")
}
