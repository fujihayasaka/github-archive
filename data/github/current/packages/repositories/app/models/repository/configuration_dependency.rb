# typed: true
# frozen_string_literal: true

module Repository::ConfigurationDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  include Configurable

  requires_ancestor { Repository }

  # Internal: Get the configuration owner.
  # values for a Repository can be cascaded from (or overridden by) the repo owner
  def configuration_owner
    owner
  end

  # Internal: Get the configuration owner asynchronously.
  # values for a Repository can be cascaded from (or overridden by) the repo owner
  def async_configuration_owner
    async_owner
  end

  include Configurable::RepositoryExportedToUrl
  include Configurable::AllowPrivateRepositoryForking
  include Configurable::AllowAutoDeletingBranches
  include Configurable::AutoMerge
  include Configurable::MergeCommits
  include Configurable::RebaseCommits
  include Configurable::SquashCommits
  include Configurable::AllowUpdatingBranch
  include Configurable::CommitDcoSignoff
  include Configurable::RepoCloneRuleSuite
  include Configurable::MaxRefUpdates
  include Configurable::DeploymentsSidebarSectionEnabled
  include Configurable::EnvironmentsSidebarSectionEnabled
  include Configurable::PackagesSidebarSectionEnabled
  include Configurable::PagesUrlSidebarSectionEnabled
  include Configurable::ReleasesSidebarSectionEnabled
  include Configurable::ActionsAccess
  include Configurable::ActionsAllowedByOwner
  include Configurable::ActionsForkPrApprovals
  include Configurable::ActionsPrivateForkPrApprovals
  include Configurable::ActionInvocation
  include Configurable::ActionsRetentionLimit
  include Configurable::ActionsRepositorySharePolicy
  include Configurable::ArchiveProgramOptOut
  include Configurable::ForcePushRejection
  include Configurable::ForkPrWorkflowsPolicy
  include Configurable::PublicForkPrWorkflowsPolicy
  include Configurable::DefaultWorkflowPermissions
  include Configurable::GitLfs
  include Configurable::MaxObjectSize
  include Configurable::DiskQuota
  include Configurable::Ssh
  include Configurable::AnonymousGitAccess
  include Configurable::AnonymousGitAccessLock
  include Repository::AnonymousGitAccess
  include Configurable::SshCertificateRequirement
  include Configurable::AdvancedSecurityAccessPolicy
  include Configurable::ActionsCacheSizeLimit
  include Configurable::ActionsRepoSelfHostedRunners
  include Configurable::ArchiveResourceBlocking

  # Internal: Read the level of force-push rejection from the git config on disk
  #
  # This method and the set_force_push_rejection_in_db alias, below, exist
  # solely to allow explicit data transition from disk to db.
  #
  # Returns String or false
  # (see #set_force_push_rejection for explanation of return values)
  def force_push_rejection_from_git_config
    if rpc.config_get("receive.denynonfastforwards") == "true"
      "all"
    elsif rpc.config_get("receive.denynonffhead") == "true"
      "default"
    else
      false
    end
  end

  # ensure git config on disk doesn't interfere with operations
  def set_force_push_rejection(*args)
    super

    clear_git_config_force_push_rejection
  end
  alias_method :set_force_push_rejection_in_db, :set_force_push_rejection

  # ensure git config on disk doesn't interfere with operations
  def clear_force_push_rejection(*args)
    super

    clear_git_config_force_push_rejection
  end

  # Clear the force-push rejection values from git config on disk
  #
  # There doesn't seem to be a way to *remove* something from the git config,
  # so explicitly set the values to false, but only if they're already set.
  def clear_git_config_force_push_rejection
    do_checksums = T.let(false, T::Boolean)
    %w[denynonfastforwards denynonffhead].each do |key|
      key = "receive.#{key}"
      next unless rpc.config_get(key)
      rpc.config_store(key, "false")
      do_checksums = true
    end
    GitHub::DGit::Maintenance.safely_recompute_checksums(self, :vote) if do_checksums
  end

  def git_lfs_enabled?
    repo = !network_root? && root ? root : self
    repo.git_lfs_config_enabled?
  end
end
