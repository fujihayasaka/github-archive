// Package topics contains the list of Hydro topics that we might listen to
package topics

// Topic constants.
const (
	AdvancedSecurityToggledTopic              = "github.security_center.v0.AdvancedSecurityToggled"
	BillingPlanChangeTopic                    = "cp1-iad.ingest.github.v1.BillingPlanChange"
	EnterpriseManagedIdentitySuspendedTopic   = "github.licensing.v0.EnterpriseManagedIdentitySuspended"
	EnterpriseManagedIdentityUnsuspendedTopic = "github.licensing.v0.EnterpriseManagedIdentityUnsuspended"
	MembershipUpdateTopic                     = "cp1-iad.ingest.github.v1.MembershipUpdate"
	OrganizationAddTopic                      = "github.enterprise_account.v0.OrganizationAdd"
	OrganizationRemoveTopic                   = "github.enterprise_account.v0.OrganizationRemove"
	OrganizationRestoreTopic                  = "github.v1.OrganizationRestore"
	OrganizationSoftDeleteTopic               = "github.v1.OrganizationSoftDelete"
	OrganizationTransferTopic                 = "github.enterprise_account.v0.OrganizationTransfer"
	OrganizationUpgradeTopic                  = "github.enterprise_account.v0.OrganizationUpgrade"
	RepositoryAddMemberTopic                  = "github.v1.RepositoryAddMember"
	RepositoryVisibilityChangedTopic          = "github.repositories.v1.VisibilityChanged"
)

// All returns all the topics.
func All() []string {
	return []string{
		AdvancedSecurityToggledTopic,
		BillingPlanChangeTopic,
		EnterpriseManagedIdentitySuspendedTopic,
		EnterpriseManagedIdentityUnsuspendedTopic,
		MembershipUpdateTopic,
		OrganizationAddTopic,
		OrganizationRemoveTopic,
		OrganizationRestoreTopic,
		OrganizationSoftDeleteTopic,
		OrganizationTransferTopic,
		OrganizationUpgradeTopic,
		RepositoryAddMemberTopic,
		RepositoryVisibilityChangedTopic,
	}
}
