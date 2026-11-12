package twirp

import (
	"testing"

	"github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestSinglePolicyBackwardsCompatibility(t *testing.T) {
	r := require.New(t)
	a := assert.New(t)

	policy := &proto.EnterprisePolicy{
		DistributionPolicies: []*proto.DistributionPolicy{
			{
				Name: "distributed",
				Licenses: &proto.PolicyLicenses{
					Allowed: []*proto.LicenseEntry{
						{SpdxId: "MIT"},
						{SpdxId: "Apache-2.0"},
					},
				},
				Packages: []*proto.PackagePolicy{
					{Name: "github.com/example/repo"},
				},
			},
		},
	}
	singlePolicyBackwardsCompatibility(policy)

	r.NotNil(policy.Licenses)                                //nolint:staticcheck // SA1019: accessing deprecated field for test
	r.Len(policy.Licenses.Allowed, 2)                        //nolint:staticcheck // SA1019: accessing deprecated field for test
	a.Equal("MIT", policy.Licenses.Allowed[0].SpdxId)        //nolint:staticcheck // SA1019: accessing deprecated field for test
	a.Equal("Apache-2.0", policy.Licenses.Allowed[1].SpdxId) //nolint:staticcheck // SA1019: accessing deprecated field for test

	r.NotNil(policy.Packages)                                   //nolint:staticcheck // SA1019: accessing deprecated field for test
	r.Len(policy.Packages, 1)                                   //nolint:staticcheck // SA1019: accessing deprecated field for test
	a.Equal("github.com/example/repo", policy.Packages[0].Name) //nolint:staticcheck // SA1019: accessing deprecated field for test
}

func TestSinglePolicyBackwardsCompatibility_NoDistributedPolicy(t *testing.T) {
	r := require.New(t)
	a := assert.New(t)

	policy := &proto.EnterprisePolicy{
		DistributionPolicies: []*proto.DistributionPolicy{
			{
				Name: "internal",
				Licenses: &proto.PolicyLicenses{
					Allowed: []*proto.LicenseEntry{
						{SpdxId: "GPL-3.0"},
					},
				},
				Packages: []*proto.PackagePolicy{
					{Name: "github.com/example/internal-repo"},
				},
			},
		},
	}
	singlePolicyBackwardsCompatibility(policy)

	r.NotNil(policy.Licenses)                             //nolint:staticcheck // SA1019: accessing deprecated field for test
	r.Len(policy.Licenses.Allowed, 1)                     //nolint:staticcheck // SA1019: accessing deprecated field for test
	a.Equal("GPL-3.0", policy.Licenses.Allowed[0].SpdxId) //nolint:staticcheck // SA1019: accessing deprecated field for test

	r.NotNil(policy.Packages)                                            //nolint:staticcheck // SA1019: accessing deprecated field for test
	r.Len(policy.Packages, 1)                                            //nolint:staticcheck // SA1019: accessing deprecated field for test
	a.Equal("github.com/example/internal-repo", policy.Packages[0].Name) //nolint:staticcheck // SA1019: accessing deprecated field for test
}
