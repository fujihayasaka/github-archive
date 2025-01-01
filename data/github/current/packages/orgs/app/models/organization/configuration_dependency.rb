# typed: true
# frozen_string_literal: true

module Organization::ConfigurationDependency
  extend ActiveSupport::Concern

  include Configurable
  include Configurable::ActionsAccess
  include Configurable::ActionsAllowedByOwner
  include Configurable::ActionsAllowedEntities
  include Configurable::ActionsCustomImagesAllowedByOwner
  include Configurable::ActionsForkPrApprovals
  include Configurable::ActionsPrivateForkPrApprovals
  include Configurable::ActionsRetentionLimit
  include Configurable::CommitDcoSignoff
  include Configurable::ForkPrWorkflowsPolicy
  include Configurable::PublicForkPrWorkflowsPolicy
  include Configurable::DefaultWorkflowPermissions
  include Configurable::DeployKeyPolicy
  include Configurable::MembersCanDeleteIssues
  include Configurable::MembersCanUpdateProtectedBranches
  include Configurable::MembersCanChangeProjectVisibility
  include Configurable::MembersCanChangeRepoVisibility
  include Configurable::MembersCanCreateRepositories
  include Configurable::MembersCanDeleteRepositories
  include Configurable::MembersCanInviteOutsideCollaborators
  include Configurable::MembersCanMakePurchases
  include Configurable::MembersCanViewDependencyInsights
  include Configurable::ModelsAccess
  include Configurable::ModelsBilling
  include Configurable::AllowPrivateRepositoryForking
  include Configurable::CodespaceTrustedRepositories
  include Configurable::AcceptOrganizationCodespacesTerms
  include Configurable::OrganizationCodespacesUserLimit
  include Configurable::OrganizationCodespacesOwnershipSetting
  include Configurable::DisableTeamDiscussions
  include Configurable::DefaultRepositoryPermission
  include Configurable::TwoFactorRequired
  include Configurable::TwoFactorDisallowedMethods
  include Configurable::RestrictNotificationDelivery
  include Configurable::DisplayCommenterFullName
  include Configurable::MembersCanCreateTeams
  include Configurable::SshCertificateRequirement
  include Configurable::IpAllowlistEnabled
  include Configurable::IpAllowlistAppAccessEnabled
  include Configurable::MemberFeatureRequestNotificationsOptOut
  include Configurable::ReadersCanCreateDiscussions
  include Configurable::MembersCanPublishPackages
  include Configurable::PackagesCanInheritAccessFromRepo
  include Configurable::MembersCanCreatePages
  include Configurable::RepositoryActionVerifiedOrg
  include Configurable::MarketplaceCreatorVerification
  include Configurable::AdvancedSecurityNewRepos
  include Configurable::AdvancedSecurityBilling
  include Configurable::AdvancedSecurityBillingConfig
  include Configurable::AdvancedSecurityTrialConfig
  include Configurable::AdvancedSecurityAccessPolicy
  include Configurable::AdvancedSecurityEligibility
  include Configurable::PackageAvailability
  include Configurable::ActionsCacheSizeLimit
  include Configurable::AutoApprovePersonalAccessTokenGrantRequests
  include Configurable::RestrictLegacyPersonalAccessTokens
  include Configurable::AuditLogSourceIpDisclosure
  include Configurable::AuditLogApiRequestEvents
  include Configurable::RestrictPersonalAccessTokens
  include Configurable::ProgrammaticAccessTokensOptIn
  include Configurable::OutsideCollaboratorsCanRequestThirdPartyAccess
  include Configurable::MaxPackagesAuthorizablePerToken
  include Configurable::ActionsLargerRunnersOnboarding
  include Configurable::ActionsRepoSelfHostedRunners
  include Configurable::SponsorshipsAccess
  include Configurable::OrgToEnterpriseMigration
  include Configurable::SecurityConfigurations
  include Configurable::PersonalAccessTokenExpirationLimit
  include Configurable::CopilotSweAgentAccess
  include Configurable::DependabotDefaultRepositoryAccess

  # Internal: Get the configuration owner.
  #
  # Values for an Organization can be cascaded from (or overridden by)
  # a Business if the Organization is a member in a Business,
  # or the global GitHub object.
  def configuration_owner
    async_configuration_owner.sync
  end

  # Internal: Get the configuration owner asynchronously.
  #
  # Values for an Organization can be cascaded from (or overridden by)
  # a Business if the Organization is a member in a Business,
  # or the global GitHub object.
  def async_configuration_owner
    self.async_business.then { |business| business || GitHub }
  end

  def personal_access_token_classic_expiration_limit_exempted_for?(actor)
    return false unless business

    T.must(business).personal_access_token_classic_expiration_limit_exempted_for?(actor)
  end
end
