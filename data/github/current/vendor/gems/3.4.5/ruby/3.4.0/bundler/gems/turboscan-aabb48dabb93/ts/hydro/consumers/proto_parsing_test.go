package consumers_test

import (
	"strings"
	"testing"

	pb "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	"github.com/github/turboscan/ts/hydro/consumers"
	"github.com/stretchr/testify/require"
)

func TestDeliveryFromProtoBytesValidation_CommitOid(t *testing.T) {
	analysis := defaultMsg()
	analysis.CommitOid = ""
	protoMsg := WrapAnalysisMessage(t, analysis)

	_, err := consumers.DeliveryFromProtoBytes(protoMsg)
	require.Error(t, err)
}

func TestDeliveryFromProtoBytesValidation_Ref(t *testing.T) {
	analysis := defaultMsg()
	analysis.Ref = []byte{}
	protoMsg := WrapAnalysisMessage(t, analysis)

	_, err := consumers.DeliveryFromProtoBytes(protoMsg)
	require.Error(t, err)
}

func TestDeliveryFromProtoBytesValidation_RepoID(t *testing.T) {
	analysis := defaultMsg()
	analysis.RepositoryId = 0
	protoMsg := WrapAnalysisMessage(t, analysis)

	_, err := consumers.DeliveryFromProtoBytes(protoMsg)
	require.Error(t, err)
}

func TestDeliveryFromProtoBytesValidation_AnalysisKey(t *testing.T) {
	analysis := defaultMsg()
	analysis.AnalysisKey = ""
	protoMsg := WrapAnalysisMessage(t, analysis)

	_, err := consumers.DeliveryFromProtoBytes(protoMsg)
	require.Error(t, err)
}

func TestDeliveryFromProtoBytesValidation_Env(t *testing.T) {
	analysis := defaultMsg()
	analysis.Environment = "garbage"
	protoMsg := WrapAnalysisMessage(t, analysis)

	d, err := consumers.DeliveryFromProtoBytes(protoMsg)
	require.NoError(t, err)
	require.Empty(t, d.Environment)
}

func TestDeliveryFromProtoBytesNonEmptyEnv(t *testing.T) {
	analysis := defaultMsg()
	analysis.Environment = "{\"os\":\"linux\"}"
	protoMsg := WrapAnalysisMessage(t, analysis)

	d, err := consumers.DeliveryFromProtoBytes(protoMsg)
	require.NoError(t, err)
	require.NotEmpty(t, d.Environment)
}

func TestDeliveryFromProtoBytesNonEmptyAuditLogContext(t *testing.T) {
	analysis := defaultMsg()
	analysis.AuditLogContext = &pb.Analysis_AuditLogContext{
		Org: "widgetsco",
	}
	protoMsg := WrapAnalysisMessage(t, analysis)

	d, err := consumers.DeliveryFromProtoBytes(protoMsg)
	require.NoError(t, err)
	require.Equal(t, d.AuditLogContext.Org, "widgetsco")
}

func TestDeliveryFromProtoBytes(t *testing.T) {
	analysis := defaultMsg()
	protoMsg := WrapAnalysisMessage(t, analysis)

	d, err := consumers.DeliveryFromProtoBytes(protoMsg)
	require.NoError(t, err)
	require.EqualValues(t, analysis.CommitOid, d.CommitOid)
	require.EqualValues(t, analysis.Ref, d.Ref)
	require.EqualValues(t, analysis.RepositoryId, d.RepositoryID)
	require.EqualValues(t, analysis.SarifUri, d.SarifPath)
	require.EqualValues(t, analysis.CheckoutUri, d.CheckoutURI)
	require.EqualValues(t, analysis.CheckRunIds, d.CheckRunIds)
}

func defaultMsg() *pb.Analysis {
	return &pb.Analysis{
		CommitOid:    strings.Repeat("a", 40),
		Ref:          []byte("refs/heads/branch"),
		RepositoryId: 1234,
		RepoNwo:      "myorg/myrepo",
		RequestId:    "1234-5467",
		AnalysisKey:  "./github/workflows/codeql.yml:codeql",
		Environment:  "{}",
		SarifUri:     "file://example.sarif",
		CheckoutUri:  "file:///tmp",
		CheckRunIds:  []uint64{1, 2, 3},
	}
}
