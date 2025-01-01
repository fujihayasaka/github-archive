# typed: true
# frozen_string_literal: true

module Business::ConfigurationDependency
  extend ActiveSupport::Concern

  include Configurable
  include Configurable::ActionsAccess
  include Configurable::ActionsAllowedEntities
  include Configurable::ActionsForkPrApprovals
  include Configurable::ActionsPrivateForkPrApprovals
  include Configurable::ActionInvocation
  include Configurable::ActionsRetentionLimit
  include Configurable::AllowPrivateRepositoryForking
  include Configurable::DeployKeyPolicy
  include Configurable::DisplayCommenterFullName
  include Configurable::DefaultRepositoryPermission
  include Configurable::DisableOrganizationProjects
  include Configurable::EnableProjectsAutomation
  include Configurable::DisableRepositoryProjects
  include Configurable::DisableRepositoryMemexProjects
  include Configurable::DisableUserProjects
  include Configurable::DisableTeamDiscussions
  include Configurable::ForkPrWorkflowsPolicy
  include Configurable::PublicForkPrWorkflowsPolicy
  include Configurable::DefaultWorkflowPermissions
  include Configurable::IpAllowlistEnabled
  include Configurable::IpAllowlistUserLevelEnforcementEnabled
  include Configurable::IpAllowlistAppAccessEnabled
  include Configurable::EmuContributionsSharingEnabled
  include Configurable::MembersCanChangeProjectVisibility
  include Configurable::MembersCanChangeRepoVisibility
  include Configurable::MembersCanCreateRepositories
  include Configurable::RestrictCreateRepositoriesInPersonalNamespace
  include Configurable::MembersCanDeleteIssues
  include Configurable::MembersCanDeleteRepositories
  include Configurable::MembersCanInviteOutsideCollaborators
  include Configurable::MembersCanMakePurchases
  include Configurable::MembersCanUpdateProtectedBranches
  include Configurable::MembersCanViewDependencyInsights
  include Configurable::PackageAvailability
  include Configurable::SshCertificateRequirement
  include Configurable::SshCertificateUserOwnedRepoAccess
  include Configurable::TwoFactorRequired
  include Configurable::AdvancedSecurityBilling
  include Configurable::AdvancedSecurityBillingConfig
  include Configurable::AdvancedSecurityTrialConfig
  include Configurable::AdvancedSecurityAccessPolicy
  include Configurable::AdvancedSecurityEligibility
  include Configurable::AdvancedSecurityEnablementPolicy
  include Configurable::SecretScanningSettingsPolicy
  include Configurable::GenericSecretsSettingsPolicy
  include Configurable::DependabotAlertsEnablementPolicy
  include Configurable::CodeScanningAutofixSettingsPolicy
  include Configurable::SupportPlan
  include Configurable::MicrosoftSupportPlan
  include Configurable::RestrictNotificationDelivery
  include Configurable::ReferrerOverride
  include Configurable::AuditLogSourceIpDisclosure
  include Configurable::AuditLogApiRequestEvents
  include Configurable::AuditLogCodeSearchEvents
  include Configurable::AutomaticSelfServePayment
  include Configurable::ActionsCacheSizeLimit
  include Configurable::AutoApprovePersonalAccessTokenGrantRequests
  include Configurable::RestrictLegacyPersonalAccessTokens
  include Configurable::RestrictPersonalAccessTokens
  include Configurable::ProgrammaticAccessTokensOptIn
  include Configurable::SsoRedirect
  include Configurable::SkipIdpIpAllowlistAppAccessEnabled
  include Configurable::IdpIpAllowlistForWeb
  include Configurable::IpAllowlistConfiguration
  include Configurable::ActionsLargerRunnersOnboarding
  include Configurable::ActionsRepoSelfHostedRunners
  include Configurable::SponsorshipsAllowedOrgs
  include Configurable::OrgsCanCreateNetworkConfiguration
  include Configurable::OpenSCIM
  include Configurable::PersonalAccessTokenExpirationLimit
  include Configurable::PersonalAccessTokenExpirationLimitExemptionEnabled

  # Internal: Get the configuration owner.
  #
  # Values for a Business can be cascaded from (or overridden by) the global
  # GitHub object.
  def configuration_owner
    GitHub
  end

  # All EMU businesses will be given a restrictive (effective) default repo collaborator policy
  def set_default_emu_repo_collab_policy
    return unless self.enterprise_managed_user_enabled?
    # this should only be called on EMU business creation, prevent action if a value is already set
    return if self.members_can_invite_outside_collaborators_set?

    self.enterprise_admins_only_can_invite_outside_collaborators(actor: User.ghost, skip_log: true)
  end

  def security_configurations_enabled?
    false
  end
end
