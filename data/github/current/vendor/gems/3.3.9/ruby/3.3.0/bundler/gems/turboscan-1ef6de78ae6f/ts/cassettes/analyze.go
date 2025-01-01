package cassettes

import (
	"os"
	"testing"

	"github.com/SamuelTissot/sqltime"
	"github.com/google/uuid"
	"github.com/stretchr/testify/require"

	"github.com/github/turboscan/ts"
)

type AnalyzeOption func(d *ts.Delivery)

func WithSarifID(sarifID string) AnalyzeOption {
	return func(d *ts.Delivery) {
		d.SarifID, _ = ts.NewSarifID(sarifID)
	}
}

func WithEnvironment(env ts.AnalysisEnv) AnalyzeOption {
	return func(d *ts.Delivery) {
		d.Environment = env
	}
}

func WithCommitOid(commitOid string) AnalyzeOption {
	return func(d *ts.Delivery) {
		d.CommitOid = ts.ToSha(commitOid)
	}
}

func WithCreatedAt(v sqltime.Time) AnalyzeOption {
	return func(d *ts.Delivery) {
		d.CreatedAt = v
	}
}

func WithTrackStatus() AnalyzeOption {
	return func(d *ts.Delivery) {
		d.TrackStatus = true
	}
}

func WithIsOutdated(toolName ts.ToolName, category string) AnalyzeOption {
	return func(d *ts.Delivery) {
		d.OutdatedConfiguration = ts.OutdatedConfiguration{ToolName: toolName, Category: ts.ToCategory(category)}
	}
}

func WithDeliveryOrigin(origin ts.DeliveryOrigin) AnalyzeOption {
	return func(d *ts.Delivery) {
		d.Origin = origin
	}
}

// Analyze ingests a SARIF file into the database
func (session *Session) Analyze(t *testing.T, repositoryID uint64, path, key, ref string, opts ...AnalyzeOption) {
	t.Helper()

	var uri string
	var err error
	if path != "" {
		var f *os.File
		f, err = os.Open(path)
		if err != nil {
			require.NoError(t, err, "reading SARIF file %s has failed", path)
		}
		defer f.Close()

		uri = "testing/" + uuid.NewString()
		err = session.sarifUploader.Upload(session.ctx, f, uri)
		if err != nil {
			require.NoError(t, err, "uploading SARIF file %s has failed", path)
		}
	}

	// It does not matter what time we use here,
	// as it will be replaced with a constant in the output.
	uploadStartTime := session.now
	uploadFinishedTime := session.now

	delivery := &ts.Delivery{
		BuildStartedAt:     &session.now,
		RepositoryID:       ts.RepositoryEID(repositoryID),
		RepositoryNWO:      "dsp-testing/test",
		OwnerID:            1,
		Environment:        ts.AnalysisEnv{},
		SarifPath:          uri,
		SarifID:            "",
		Ref:                []byte(ref),
		AnalysisKey:        ts.ToAnalysisKey(key),
		SourceRepositoryID: ts.RepositoryEID(repositoryID),
		CommitOid:          "b000000000000000000000000000000000000000",
		UploadStartedAt:    &uploadStartTime,
		UploadFinishedAt:   &uploadFinishedTime,
	}
	// Start Transitional code: This data should come as part of the request but for now it does not
	// See https://github.com/github/code-scanning/issues/7691
	delivery.Origin = delivery.OriginFromAnalysisKey()
	delivery.WorkflowPath = delivery.WorkflowPathFromAnalysisKey()
	// End Transitional code

	for _, opt := range opts {
		opt(delivery)
	}

	_, err = session.processor.ProcessNewDelivery(session.ctx, delivery)
	require.NoError(t, err)
}

// CreatePendingDelivery creates a new delivery in a pending state.
func (session *Session) CreatePendingDelivery(t *testing.T, repositoryID uint64, ref string, opts ...AnalyzeOption) {
	t.Helper()

	// It does not matter what time we use here,
	// as it will be replaced with a constant in the output.
	uploadStartTime := session.now
	uploadFinishedTime := session.now

	delivery := &ts.Delivery{
		BuildStartedAt:     &session.now,
		RepositoryID:       ts.RepositoryEID(repositoryID),
		RepositoryNWO:      "dsp-testing/test",
		Environment:        ts.AnalysisEnv{},
		SarifPath:          "path/to/sarif.sarif",
		SarifID:            "",
		Ref:                []byte(ref),
		AnalysisKey:        "key",
		SourceRepositoryID: ts.RepositoryEID(repositoryID),
		CommitOid:          "b000000000000000000000000000000000000000",
		UploadStartedAt:    &uploadStartTime,
		UploadFinishedAt:   &uploadFinishedTime,
		Origin:             ts.DeliveryOrigin_YML,
		WorkflowPath:       ts.EmptyWorkflowPath(),
	}

	for _, opt := range opts {
		opt(delivery)
	}

	require.NoError(t, session.deliveryService.CreateDelivery(session.ctx, delivery))
}
