package twirp

import proto "github.com/github/osslicensecompliance/pkg/proto/v0"

// singlePolicyBackwardsCompatibility is a temporary function to provide backwards
// compatibility for the monolith code that was built for a single policy with
// "contexts" but not `DistributionPolicy`s. This function pulls the
// "distributed" policy licenses and packages up a level for compatibility.
// If there is no "distributed" policy, it pulls the data from the first
// distribution policy it finds.
func singlePolicyBackwardsCompatibility(policy *proto.EnterprisePolicy) {
	if policy == nil || len(policy.DistributionPolicies) == 0 {
		return
	}

	var distPolicy *proto.DistributionPolicy
	for _, dp := range policy.DistributionPolicies {
		if dp.Name == "distributed" {
			distPolicy = dp
			break
		}
	}
	if distPolicy == nil {
		distPolicy = policy.DistributionPolicies[0]
	}

	policy.Licenses = distPolicy.Licenses //nolint:staticcheck // SA1019: accessing deprecated field for backwards compatibility
	policy.Packages = distPolicy.Packages //nolint:staticcheck // SA1019: accessing deprecated field for backwards compatibility
}
