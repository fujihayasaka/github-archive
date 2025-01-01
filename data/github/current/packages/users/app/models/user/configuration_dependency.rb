# typed: true
# frozen_string_literal: true

module User::ConfigurationDependency
  extend ActiveSupport::Concern

  include Configurable

  # Internal: Set the type for associating configuration entries
  # explicitly using 'User' here instead of the class name so behavior
  # correctly gets inherited by Organization
  def configuration_entry_type
    "User"
  end

  # Internal: Set the configuration owner.
  # values for a User can be cascaded from (or overridden by) the global
  # GitHub object, or the global GitHub enterprise account in GHE server
  def configuration_owner
    return GitHub.global_business if GitHub.single_business_environment?
    GitHub
  end

  include Configurable::ForcePushRejection
  include Configurable::GitLfs
  include Configurable::PackageRegistry
  include Configurable::MaxObjectSize
  include Configurable::DiskQuota
  include Configurable::OperatorMode
  include Configurable::Ssh
  include Configurable::GpgAuthorization
  include Configurable::CodespacesSettingsSyncAuthorization
  include Configurable::CodespacesExpiryNotification
  include Configurable::CodespacesRepositoryAuthorization
  include Configurable::CodespaceTrustedRepositories
  include Configurable::CodespacePreferredEditor
  include Configurable::CodespacePreferredHostImage
  include Configurable::CodespacesVscodeChannel
  include Configurable::CodespaceDefaultIdleTimeout
  include Configurable::CodespaceDefaultLocation
  include Configurable::CodespaceDefaultRetentionPeriod
  include Configurable::CodespaceDotfilesEnabled
  include Configurable::CodespaceDotfilesRepository
  include Configurable::AdvancedSecurityAccessPolicy
  include Configurable::AdvancedSecurityBilling
  include Configurable::AdvancedSecurityNewRepos
  include Configurable::CommitVerificationStatus
  include Configurable::CodespaceDefaultTelemetryLevel
  include Configurable::PackagesCanInheritAccessFromRepo
  include Configurable::AuditLogSourceIpDisclosure
  include Configurable::AuditLogApiRequestEvents
  include Configurable::AuditLogCodeSearchEvents
  include Configurable::MaxPackagesAuthorizablePerToken
  include Configurable::SponsorshipsAccess
  include Configurable::CopilotSweAgentAccess
  include Configurable::ModelsBilling
  include Configurable::FailFastMode

  def git_lfs_enabled?
    git_lfs_config_enabled?
  end

  # This feature isn't available to Users, so hardcode false since the corresponding Configurable class is for orgs:
  def security_configurations_enabled?
    false
  end
end
