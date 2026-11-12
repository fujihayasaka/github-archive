// Package testhelpers package provides shared functions, variables, and constants used in tests.
package testhelpers

import (
	"crypto/rand"
	"encoding/binary"
	"fmt"
	"math"
	"testing"
	"time"

	dg "github.com/github/dependency-graph-api/gen/go/v1"
	"github.com/github/github-telemetry-go/log/logtest"
	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/dependencies"
	"github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/golang/protobuf/ptypes/timestamp"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// PR42AsUint32 represents a pull request with number 42 as a uint32.
const PR42AsUint32 = uint32(42)

// PR42AsUint64 represents a pull request with number 42 as a uint64.
const PR42AsUint64 = uint64(42)

// AllDistributionContexts is a list of all possible distribution contexts.
var AllDistributionContexts = []string{"distributed", "network", "internal"}

// SubsetContexts is a list of some distribution contexts.
var SubsetContexts = []string{"network", "internal"}

// DistributedContext is a list of some distribution contexts.
var DistributedContext = "distributed"

// RandomIDForDatabase returns a random uint64 suitable for use as a database ID.
func RandomIDForDatabase() uint64 {
	var b [8]byte
	_, err := rand.Read(b[:])
	if err != nil {
		// fallback to a safe value if random fails
		return 1
	}
	id := binary.LittleEndian.Uint64(b[:])
	return id % math.MaxInt32
}

// SetupPolicy sets up an organization policy in the database for testing.
// NOTE: nullconfig allows passing in additional configs (e.g. DiffStatusConfig)
// to use when creating the new null app.
func SetupPolicy(t *testing.T, orgID, repoID uint64, depLicense, policyLicense string, policyContexts []string, baseSHA, commitSHA string, nullConfig *application.NullConfig) (app *application.Application, buf *logtest.Buffer) {
	dpConfig := dependencies.NullConfig{
		GetSnapshotsDiffResponses: map[string]*dg.GetSnapshotsDiffResponse{
			fmt.Sprintf("%d:%s:%s", repoID, baseSHA, commitSHA): {
				ChangedManifests: []*dg.GetSnapshotsDiffResponse_ManifestDiff{
					{
						Type:     dg.PackageManager_PACKAGE_MANAGER_RUBYGEMS,
						FilePath: "./Gemfile.lock",
						Dependencies: []*dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff{
							{
								Name:          "foo/bar",
								TargetVersion: "1.0.1",
								ChangeType:    dg.GetSnapshotsDiffResponse_ManifestDiff_DependencyDiff_DEPENDENCY_CHANGE_TYPE_ADDED,
								License:       depLicense,
							},
						},
					},
				},
			},
		},
	}
	logger, buf := logtest.NewTestLogger(t)
	if nullConfig == nil {
		nullConfig = &application.NullConfig{}
	}
	nullConfig.DependenciesConfig = dpConfig

	app, err := application.NewNullApplication(nullConfig, logger)
	require.NoError(t, err)
	t.Cleanup(func() {
		err = app.Close()
		if err != nil {
			t.Errorf("failed to close app: %v", err)
		}
	})

	policy := &proto.OrganizationPolicy{
		OrganizationId:       orgID,
		DistributionPolicies: CreateDistributionPolicies([]string{policyLicense}, nil, policyContexts),
	}

	_, err = app.Subsystems.Storage.CreateOrganizationPolicy(t.Context(), policy)
	require.NoError(t, err)

	return app, buf
}

// MustParseTime is a helper that parses a time string and panics on error.
func MustParseTime(t *testing.T, timeStr string) (parsedTime time.Time) {
	parsedTime, err := time.Parse(time.RFC3339, timeStr)
	require.NoError(t, err, "failed to parse time %q: %v", timeStr, err)
	return parsedTime
}

// MustProtoTimestamp converts a time string to a protobuf timestamp, panicking on error.
func MustProtoTimestamp(t *testing.T, timeStr string) *timestamp.Timestamp {
	parsedTime, err := time.Parse(time.RFC3339, timeStr)
	require.NoError(t, err, "failed to parse time %q: %v", timeStr, err)
	return timestamppb.New(parsedTime)
}

// CreateLicenseEntries creates a slice of LicenseEntry protos from a slice of license strings.
func CreateLicenseEntries(licenses []string) []*proto.LicenseEntry {
	licenseEntries := []*proto.LicenseEntry{}
	for _, l := range licenses {
		licenseEntries = append(licenseEntries, &proto.LicenseEntry{
			SpdxId: l,
		})
	}
	return licenseEntries
}

// CreateDistributionPolicies creates distribution policies for the given licenses, package policies, and contexts.
func CreateDistributionPolicies(licenses []string, packagePolicies []*proto.PackagePolicy, contexts []string) []*proto.DistributionPolicy {
	var distributionPolicies []*proto.DistributionPolicy
	if packagePolicies == nil {
		packagePolicies = []*proto.PackagePolicy{}
	}
	for _, context := range contexts {
		distributionPolicies = append(distributionPolicies, &proto.DistributionPolicy{
			Name: context,
			Licenses: &proto.PolicyLicenses{
				Allowed: CreateLicenseEntries(licenses),
			},
			Packages: packagePolicies,
		})
	}
	return distributionPolicies
}

// CreateLicenseEntriesWithAllContexts creates LicenseEntry protos from a slice of SPDX IDs.
func CreateLicenseEntriesWithAllContexts(licenses []string) []*proto.LicenseEntry {
	allowed := make([]*proto.LicenseEntry, 0, len(licenses))
	for _, license := range licenses {
		allowed = append(allowed, &proto.LicenseEntry{SpdxId: license, Contexts: AllDistributionContexts})
	}
	return allowed
}
