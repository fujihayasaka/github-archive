package eventpublisher_test

import (
	"testing"
	"time"

	"github.com/github/osslicensecompliance/internal/eventpublisher"
	"github.com/github/osslicensecompliance/internal/eventpublisher/testpublisher"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/timestamppb"

	dependencygraphv1 "github.com/github/osslicensecompliance/hydroproto/hydro/schemas/github/dependencygraph/v1"
	"github.com/github/osslicensecompliance/hydroproto/hydro/schemas/github/dependencygraph/v1/entities"
	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
	"google.golang.org/protobuf/types/known/wrapperspb"
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
				PackageManager:        entities.PackageManager_PACKAGE_MANAGER_NPM,
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

func TestPublishAlertStatusChanged(t *testing.T) {
	prNumber := uint32(42)
	prID := uint64(9999)
	createdAt := time.Now()
	userID := uint64(123)
	closureUserID := uint64(124)
	enterpriseID := uint64(555)
	comment := "Licenses added to policy"

	testCases := []struct {
		name           string
		alert          *models.Alert
		previousStatus models.AlertStatus
		userID         *uint64
		closureUserID  *uint64
		comment        string
		expectedProto  *dependencygraphv1.LicenseComplianceAlertStatusChanged
	}{
		{
			name: "with enterprise ID and comment",
			alert: &models.Alert{
				ID:                    456,
				Number:                10,
				Status:                models.AlertStatusClosed,
				Resolution:            models.AlertResolutionLicensesAdded,
				CreatedAt:             createdAt,
				RepositoryID:          789,
				OrganizationID:        111,
				EnterpriseID:          &enterpriseID,
				PullRequestNumber:     &prNumber,
				ManifestName:          "package.json",
				PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
				PackageName:           "test-package",
				PackageVersion:        "1.0.0",
				SPDXLicenseExpression: "MIT",
			},
			previousStatus: models.AlertStatusOpen,
			userID:         &userID,
			comment:        comment,
			closureUserID:  nil,
			expectedProto: &dependencygraphv1.LicenseComplianceAlertStatusChanged{
				Alert: &entities.LicenseComplianceAlert{
					AlertId:               456,
					AlertNumber:           10,
					Status:                entities.AlertStatus_ALERT_STATUS_CLOSED,
					CreatedAt:             timestamppb.New(createdAt),
					RepositoryId:          789,
					OrganizationId:        111,
					EnterpriseId:          &wrapperspb.Int64Value{Value: int64(enterpriseID)},
					PullRequestNumber:     int32(prNumber),
					PullRequestId:         int64(prID),
					ManifestName:          "package.json",
					PackageManager:        entities.PackageManager_PACKAGE_MANAGER_NPM,
					PackageName:           "test-package",
					PackageVersion:        "1.0.0",
					SpdxLicenseExpression: "MIT",
				},
				PreviousStatus: entities.AlertStatus_ALERT_STATUS_OPEN,
				UserId:         int64(userID),
				Comment:        &wrapperspb.StringValue{Value: comment},
				ClosureUserId:  nil,
			},
		},
		{
			name: "without enterprise ID and no comment",
			alert: &models.Alert{
				ID:                    456,
				Number:                10,
				Status:                models.AlertStatusClosed,
				Resolution:            models.AlertResolutionOutdated,
				CreatedAt:             createdAt,
				RepositoryID:          789,
				OrganizationID:        111,
				EnterpriseID:          nil,
				PullRequestNumber:     &prNumber,
				ManifestName:          "package.json",
				PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
				PackageName:           "test-package",
				PackageVersion:        "1.0.0",
				SPDXLicenseExpression: "MIT",
			},
			previousStatus: models.AlertStatusOpen,
			userID:         nil,
			comment:        "",
			closureUserID:  nil,
			expectedProto: &dependencygraphv1.LicenseComplianceAlertStatusChanged{
				Alert: &entities.LicenseComplianceAlert{
					AlertId:               456,
					AlertNumber:           10,
					Status:                entities.AlertStatus_ALERT_STATUS_CLOSED,
					CreatedAt:             timestamppb.New(createdAt),
					RepositoryId:          789,
					OrganizationId:        111,
					EnterpriseId:          nil,
					PullRequestNumber:     int32(prNumber),
					PullRequestId:         int64(prID),
					ManifestName:          "package.json",
					PackageManager:        entities.PackageManager_PACKAGE_MANAGER_NPM,
					PackageName:           "test-package",
					PackageVersion:        "1.0.0",
					SpdxLicenseExpression: "MIT",
				},
				PreviousStatus: entities.AlertStatus_ALERT_STATUS_OPEN,
				UserId:         0,
				Comment:        nil,
				ClosureUserId:  nil,
			},
		},
		{
			name: "with closure user ID",
			alert: &models.Alert{
				ID:                    456,
				Number:                10,
				Status:                models.AlertStatusClosed,
				Resolution:            models.AlertResolutionLicensesAdded,
				CreatedAt:             createdAt,
				RepositoryID:          789,
				OrganizationID:        111,
				EnterpriseID:          &enterpriseID,
				PullRequestNumber:     &prNumber,
				ManifestName:          "package.json",
				PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
				PackageName:           "test-package",
				PackageVersion:        "1.0.0",
				SPDXLicenseExpression: "MIT",
			},
			previousStatus: models.AlertStatusReviewRequested,
			userID:         &userID,
			comment:        comment,
			closureUserID:  &closureUserID,
			expectedProto: &dependencygraphv1.LicenseComplianceAlertStatusChanged{
				Alert: &entities.LicenseComplianceAlert{
					AlertId:               456,
					AlertNumber:           10,
					Status:                entities.AlertStatus_ALERT_STATUS_CLOSED,
					CreatedAt:             timestamppb.New(createdAt),
					RepositoryId:          789,
					OrganizationId:        111,
					EnterpriseId:          &wrapperspb.Int64Value{Value: int64(enterpriseID)},
					PullRequestNumber:     int32(prNumber),
					PullRequestId:         int64(prID),
					ManifestName:          "package.json",
					PackageManager:        entities.PackageManager_PACKAGE_MANAGER_NPM,
					PackageName:           "test-package",
					PackageVersion:        "1.0.0",
					SpdxLicenseExpression: "MIT",
				},
				PreviousStatus: entities.AlertStatus_ALERT_STATUS_REVIEW_REQUESTED,
				UserId:         int64(userID),
				Comment:        &wrapperspb.StringValue{Value: comment},
				ClosureUserId:  wrapperspb.Int64(int64(closureUserID)),
			},
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			tp := testpublisher.NewTestPublisher(t)
			var opts []eventpublisher.AlertStatusChangedOption
			if tc.userID != nil {
				opts = append(opts, eventpublisher.WithUserID(tc.userID))
			}
			if tc.comment != "" {
				comment := tc.comment
				opts = append(opts, eventpublisher.WithComment(&comment))
			}
			if tc.closureUserID != nil {
				opts = append(opts, eventpublisher.WithClosureEventUserID(tc.closureUserID))
			}

			err := tp.PublishAlertStatusChanged(t.Context(), tc.alert, tc.previousStatus, prID, opts...)
			require.NoError(t, err)

			tp.AssertMessagePublished(t, "github.dependencygraph.v1.LicenseComplianceAlertStatusChanged", tc.expectedProto)
		})
	}
}

func TestModelToProtoPackageManager(t *testing.T) {
	// Ensure enum values are aligned between OLC and Hydro protos
	// by actually calling the conversion function
	tests := []struct {
		name     string
		input    proto.PackageManager
		expected entities.PackageManager
	}{
		{"unknown", proto.PackageManager_PACKAGE_MANAGER_UNKNOWN, entities.PackageManager_PACKAGE_MANAGER_UNKNOWN},
		{"rubygems", proto.PackageManager_PACKAGE_MANAGER_RUBYGEMS, entities.PackageManager_PACKAGE_MANAGER_RUBYGEMS},
		{"npm", proto.PackageManager_PACKAGE_MANAGER_NPM, entities.PackageManager_PACKAGE_MANAGER_NPM},
		{"pip", proto.PackageManager_PACKAGE_MANAGER_PIP, entities.PackageManager_PACKAGE_MANAGER_PIP},
		{"maven", proto.PackageManager_PACKAGE_MANAGER_MAVEN, entities.PackageManager_PACKAGE_MANAGER_MAVEN},
		{"nuget", proto.PackageManager_PACKAGE_MANAGER_NUGET, entities.PackageManager_PACKAGE_MANAGER_NUGET},
		{"composer", proto.PackageManager_PACKAGE_MANAGER_COMPOSER, entities.PackageManager_PACKAGE_MANAGER_COMPOSER},
		{"gomod", proto.PackageManager_PACKAGE_MANAGER_GOMOD, entities.PackageManager_PACKAGE_MANAGER_GOMOD},
		{"rust", proto.PackageManager_PACKAGE_MANAGER_RUST, entities.PackageManager_PACKAGE_MANAGER_RUST},
		{"actions", proto.PackageManager_PACKAGE_MANAGER_ACTIONS, entities.PackageManager_PACKAGE_MANAGER_ACTIONS},
		{"pub", proto.PackageManager_PACKAGE_MANAGER_PUB, entities.PackageManager_PACKAGE_MANAGER_PUB},
		{"swift", proto.PackageManager_PACKAGE_MANAGER_SWIFT, entities.PackageManager_PACKAGE_MANAGER_SWIFT},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := eventpublisher.ModelToProtoPackageManager(tt.input)
			require.Equal(t, tt.expected, result,
				"ModelToProtoPackageManager must correctly convert %s", tt.name)
			// Also verify underlying int32 values match
			require.Equal(t, int32(tt.expected), int32(result),
				"Enum numeric values must match for %s", tt.name)
		})
	}
}

func TestPublishPolicyChanged_Actions(t *testing.T) {
	tests := []struct {
		name   string
		action eventpublisher.PolicyAction
	}{
		{"policy_created", eventpublisher.PolicyActionPolicyCreated},
		{"license_added", eventpublisher.PolicyActionLicenseAdded},
		{"license_removed", eventpublisher.PolicyActionLicenseRemoved},
		{"package_exemption_added", eventpublisher.PolicyActionPackageExemptionAdded},
		{"package_exemption_removed", eventpublisher.PolicyActionPackageExemptionRemoved},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tp := testpublisher.NewTestPublisher(t)

			err := tp.PublishPolicyChanged(t.Context(), eventpublisher.PolicyChangedEvent{
				Action:   tt.action,
				Level:    eventpublisher.PolicyLevelRepository,
				EntityID: 12345,
			})
			require.NoError(t, err)

			tp.AssertMessagePublished(t, "github.dependencygraph.v1.LicensePolicyChanged", &dependencygraphv1.LicensePolicyChanged{
				Action:   tt.action,
				Level:    dependencygraphv1.LicensePolicyChanged_POLICY_LEVEL_REPOSITORY,
				EntityId: 12345,
			})
		})
	}
}

func TestPublishPolicyChanged_Levels(t *testing.T) {
	tests := []struct {
		name  string
		level eventpublisher.PolicyLevel
	}{
		{"repository", eventpublisher.PolicyLevelRepository},
		{"organization", eventpublisher.PolicyLevelOrganization},
		{"enterprise", eventpublisher.PolicyLevelEnterprise},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tp := testpublisher.NewTestPublisher(t)

			err := tp.PublishPolicyChanged(t.Context(), eventpublisher.PolicyChangedEvent{
				Action:               eventpublisher.PolicyActionLicenseAdded,
				Level:                tt.level,
				EntityID:             12345,
				DistributionContexts: []string{"distributed", "internal"},
			})
			require.NoError(t, err)

			tp.AssertMessagePublished(t, "github.dependencygraph.v1.LicensePolicyChanged", &dependencygraphv1.LicensePolicyChanged{
				Action:               dependencygraphv1.LicensePolicyChanged_POLICY_ACTION_LICENSE_ADDED,
				Level:                tt.level,
				EntityId:             12345,
				DistributionContexts: []string{"distributed", "internal"},
			})
		})
	}
}
