package eventpublisher_test

import (
	"testing"
	"time"

	"github.com/github/osslicensecompliance/internal/eventpublisher/testpublisher"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/timestamppb"

	dependencygraphv1 "github.com/github/osslicensecompliance/hydroproto/hydro/schemas/github/dependencygraph/v1"
	"github.com/github/osslicensecompliance/hydroproto/hydro/schemas/github/dependencygraph/v1/entities"
	"github.com/github/osslicensecompliance/pkg/proto/v0"
)

func TestPublishPRLicenseCheckCompleteEvent_WithOpenAlerts(t *testing.T) {
	tp := testpublisher.NewTestPublisher(t)
	prNumber := uint32(42)
	prID := uint64(9999)
	repoID := uint64(1001)
	commitSHA := "abc123def456"
	createdAt := time.Now()
	remediationGuidance := "remediation-guidance"
	alerts := []*models.Alert{
		{
			ID:                    123,
			Number:                1,
			CreatedAt:             createdAt,
			RepositoryID:          456,
			OrganizationID:        789,
			PullRequestNumber:     &prNumber,
			ManifestName:          "package.json",
			PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			PackageName:           "test-package",
			PackageVersion:        "1.0.0",
			SPDXLicenseExpression: "GPL-3.0",
		},
	}
	err := tp.PublishPRLicenseCheckCompleteEvent(t.Context(), repoID, prID, prNumber, commitSHA, "base123sha456", alerts, remediationGuidance)
	require.NoError(t, err)

	expectedProto := &dependencygraphv1.PullRequestLicenseCheckComplete{
		PullRequestId:     int64(prID),     // #nosec G115
		PullRequestNumber: int32(prNumber), // #nosec G115
		CommitSha:         commitSHA,
		BaseSha:           "base123sha456",
		OpenLicenseAlerts: []*entities.LicenseComplianceAlert{
			{
				AlertId:               int64(alerts[0].ID),     // #nosec G115
				AlertNumber:           int32(alerts[0].Number), // #nosec G115
				CreatedAt:             timestamppb.New(alerts[0].CreatedAt),
				RepositoryId:          int64(alerts[0].RepositoryID),   // #nosec G115
				OrganizationId:        int64(alerts[0].OrganizationID), // #nosec G115
				PullRequestNumber:     int32(prNumber),                 // #nosec G115
				PullRequestId:         int64(prID),                     // #nosec G115
				ManifestName:          alerts[0].ManifestName,
				PackageName:           alerts[0].PackageName,
				PackageVersion:        alerts[0].PackageVersion,
				SpdxLicenseExpression: alerts[0].SPDXLicenseExpression,
			},
		},
		RepositoryId:        int64(repoID), // #nosec G115
		RemediationGuidance: remediationGuidance,
	}
	tp.AssertMessagePublished(t, "github.dependencygraph.v1.PullRequestLicenseCheckComplete", expectedProto)
}

func TestPublishPRLicenseCheckCompleteEvent_NoOpenAlerts(t *testing.T) {
	tp := testpublisher.NewTestPublisher(t)
	prNumber := uint32(42)
	prID := uint64(9999)
	repoID := uint64(1001)
	commitSHA := "abc123def456"
	err := tp.PublishPRLicenseCheckCompleteEvent(t.Context(), repoID, prID, prNumber, commitSHA, "base123sha456", nil, "")
	require.NoError(t, err)

	expectedProto := &dependencygraphv1.PullRequestLicenseCheckComplete{
		PullRequestId:       int64(prID),     // #nosec G115
		PullRequestNumber:   int32(prNumber), // #nosec G115
		RepositoryId:        int64(repoID),   // #nosec G115
		CommitSha:           commitSHA,
		BaseSha:             "base123sha456",
		RemediationGuidance: "",
	}
	tp.AssertMessagePublished(t, "github.dependencygraph.v1.PullRequestLicenseCheckComplete", expectedProto)
}
