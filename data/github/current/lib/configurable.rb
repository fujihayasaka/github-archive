# typed: true
# frozen_string_literal: true

module Configurable
  autoload :AnonymousGitAccess, "configurable/anonymous_git_access"
  autoload :OrgMembershipVisibility, "configurable/org_membership_visibility"
  autoload :GitLfs, "configurable/git_lfs"
  autoload :ContentAnalysis, "configurable/content_analysis"
  autoload :Dependabot, "configurable/dependabot"
  autoload :DotcomDownloadActionsArchive, "configurable/dotcom_download_actions_archive"
  autoload :DisplayCommenterFullName, "configurable/display_commenter_full_name"
  autoload :OrgCreation, "configurable/org_creation"
  autoload :AllowAutoDeletingBranches, "configurable/allow_auto_deleting_branches"
  autoload :ArchiveProgramOptOut, "configurable/archive_program_opt_out"
  autoload :RepositoryDependencyUpdates, "configurable/repository_dependency_updates"
  autoload :TokenScanning, "configurable/token_scanning"
  autoload :IpAllowlistEnabled, "configurable/ip_allowlist_enabled"
  autoload :IpAllowlistUserLevelEnforcementEnabled, "configurable/ip_allowlist_user_level_enforcement_enabled"
  autoload :EmuContributionsSharingEnabled, "configurable/emu_contributions_sharing_enabled"
  autoload :TwoFactorRequired, "configurable/two_factor_required"
  autoload :ForcePushRejection, "configurable/force_push_rejection"
  autoload :TieredReporting, "configurable/tiered_reporting"
  autoload :TieredReportingAllUsers, "configurable/tiered_reporting_all_users"
  autoload :DisableTeamDiscussions, "configurable/disable_team_discussions"
  autoload :DisableTeamPostCreation, "configurable/disable_team_post_creation"
  autoload :DefaultNewRepoBranch, "configurable/default_new_repo_branch"
  autoload :EnterpriseDormancyThreshold, "configurable/enterprise_dormancy_threshold"
  autoload :Ssh, "configurable/ssh"
  autoload :Showcase, "configurable/showcase"
  autoload :DotcomPrivateSearch, "configurable/dotcom_private_search"
  autoload :RepositoryFundingLinks, "configurable/repository_funding_links"
  autoload :RepositoryExportedToUrl, "configurable/repository_exported_to_url"
  autoload :DisableOrganizationProjects, "configurable/disable_organization_projects"
  autoload :EnableProjectsAutomation, "configurable/enable_projects_automation"
  autoload :ReadersCanCreateDiscussions, "configurable/readers_can_create_discussions"
  autoload :RepositoryActionVerifiedOrg, "configurable/repository_action_verified_org"
  autoload :MarketplaceCreatorVerification, "configurable/marketplace_creator_verification"
  autoload :MembersCanUpdateProtectedBranches, "configurable/members_can_update_protected_branches"
  autoload :MembersCanCreateTeams, "configurable/members_can_create_teams"
  autoload :CrossRepoConflictEditor, "configurable/cross_repo_conflict_editor"
  autoload :DotcomSearch, "configurable/dotcom_search"
  autoload :MaxObjectSize, "configurable/max_object_size"
  autoload :DotcomUserLicenseUsageUpload, "configurable/dotcom_user_license_usage_upload"
  autoload :MembersCanInviteOutsideCollaborators, "configurable/members_can_invite_outside_collaborators"
  autoload :SecuritySettings, "configurable/security_settings"
  autoload :DisableRepositoryProjects, "configurable/disable_repository_projects"
  autoload :DisableRepositoryMemexProjects, "configurable/disable_repository_memex_projects"
  autoload :DisableUserProjects, "configurable/disable_user_projects"
  autoload :DefaultRepoVisibility, "configurable/default_repo_visibility"
  autoload :CodeScanning, "configurable/code_scanning"
  autoload :CodeScanningAutofix, "configurable/code_scanning_autofix"
  autoload :CodeScanningAutofixSettingsPolicy, "configurable/code_scanning_autofix_settings_policy"
  autoload :MembersCanMakePurchases, "configurable/members_can_make_purchases"
  autoload :SuggestedProtocol, "configurable/suggested_protocol"
  autoload :DependencyGraph, "configurable/dependency_graph"
  autoload :MembersCanViewDependencyInsights, "configurable/members_can_view_dependency_insights"
  autoload :MembersCanDeleteRepositories, "configurable/members_can_delete_repositories"
  autoload :MembersCanPublishPackages, "configurable/members_can_publish_packages"
  autoload :PackagesCanInheritAccessFromRepo, "configurable/packages_can_inherit_access_from_repo"
  autoload :MembersCanCreatePages, "configurable/members_can_create_pages"
  autoload :MembersCanCreateRepositories, "configurable/members_can_create_repositories"
  autoload :RestrictCreateRepositoriesInPersonalNamespace, "configurable/restrict_create_repositories_in_personal_namespace"
  autoload :DotcomContributions, "configurable/dotcom_contributions"
  autoload :MembersCanDeleteIssues, "configurable/members_can_delete_issues"
  autoload :PackageAvailability, "configurable/package_availability"
  autoload :ForkPrWorkflowsPolicy, "configurable/fork_pr_workflows_policy"
  autoload :PublicForkPrWorkflowsPolicy, "configurable/public_fork_pr_workflows_policy"
  autoload :DefaultWorkflowPermissions, "configurable/default_workflow_permissions"
  autoload :RestrictNotificationDelivery, "configurable/restrict_notification_delivery"
  autoload :OperatorMode, "configurable/operator_mode"
  autoload :ActionsAccess, "configurable/actions_access"
  autoload :ActionsAllowedEntities, "configurable/actions_allowed_entities"
  autoload :ActionsForkPrApprovals, "configurable/actions_fork_pr_approvals"
  autoload :ActionsPrivateForkPrApprovals, "configurable/actions_private_fork_pr_approvals"
  autoload :ActionsRetentionLimit, "configurable/actions_retention_limit"
  autoload :ActionsRepositorySharePolicy, "configurable/actions_repository_share_policy"
  autoload :ResellerCustomer, "configurable/reseller_customer"
  autoload :ActionsAllowedByOwner, "configurable/actions_allowed_by_owner"
  autoload :RepositoryVulnerabilityAlerts, "configurable/repository_vulnerability_alerts"
  autoload :GheContentAnalysis, "configurable/ghe_content_analysis"
  autoload :SshCertificateRequirement, "configurable/ssh_certificate_requirement"
  autoload :SshCertificateUserOwnedRepoAccess, "configurable/ssh_certificate_user_owned_repo_access"
  autoload :IpAllowlistAppAccessEnabled, "configurable/ip_allowlist_app_access_enabled"
  autoload :ActionInvocation, "configurable/action_invocation"
  autoload :MembersCanChangeProjectVisibility, "configurable/members_can_change_project_visibility"
  autoload :MembersCanChangeRepoVisibility, "configurable/members_can_change_repo_visibility"
  autoload :DefaultRepositoryPermission, "configurable/default_repository_permission"
  autoload :AdvancedSecurity, "configurable/advanced_security"
  autoload :AdvancedSecurityBilling, "configurable/advanced_security_billing"
  autoload :AdvancedSecurityBillingConfig, "configurable/advanced_security_billing_config"
  autoload :AdvancedSecurityTrialConfig, "configurable/advanced_security_trial_config"
  autoload :AdvancedSecurityNewRepos, "configurable/advanced_security_new_repos"
  autoload :AdvancedSecurityAccessPolicy, "configurable/advanced_security_access_policy"
  autoload :AdvancedSecurityEligibility, "configurable/advanced_security_eligibility"
  autoload :AdvancedSecurityEnablementPolicy, "configurable/advanced_security_enablement_policy"
  autoload :SecretScanningSettingsPolicy, "configurable/secret_scanning_settings_policy"
  autoload :GenericSecretsSettingsPolicy, "configurable/generic_secrets_settings_policy"
  autoload :DependabotAlertsEnablementPolicy, "configurable/dependabot_alerts_enablement_policy"
  autoload :UsedBy, "configurable/used_by"
  autoload :AllowPrivateRepositoryForking, "configurable/allow_private_repository_forking"
  autoload :PackageRegistry, "configurable/package_registry"
  autoload :AnonymousGitAccessLock, "configurable/anonymous_git_access_lock"
  autoload :SmsForTwoFactorAuth, "configurable/sms_for_two_factor_auth"
  autoload :DiskQuota, "configurable/disk_quota"
  autoload :SupportPlan, "configurable/support_plan"
  autoload :MicrosoftSupportPlan, "configurable/microsoft_support_plan"
  autoload :DiscussionsEnablement, "configurable/discussions_enablement"
  autoload :AutoMerge, "configurable/auto_merge"
  autoload :CommitVerificationStatus, "configurable/commit_verification_status"
  autoload :ReferrerOverride, "configurable/referrer_override"
  autoload :RestrictNonCommentPullRequestReviews, "configurable/restrict_non_comment_pull_request_reviews"
  autoload :GheUsageMetrics, "configurable/ghe_usage_metrics"
  autoload :GheDependabotAccessToDotcom, "configurable/ghe_dependabot_access_to_dotcom"
  autoload :AllowUpdatingBranch, "configurable/allow_updating_branch"
  autoload :AuditLogSourceIpDisclosure, "configurable/audit_log_source_ip_disclosure"
  autoload :AuditLogApiRequestEvents, "configurable/audit_log_api_request_events"
  autoload :AuditLogCodeSearchEvents, "configurable/audit_log_code_search_events"
  autoload :AutomaticSelfServePayment, "configurable/automatic_self_serve_payment"
  autoload :AutoApprovePersonalAccessTokenGrantRequests, "configurable/auto_approve_personal_access_token_grant_requests"
  autoload :SquashMergeCommitTitle, "configurable/squash_merge_commit_title"
  autoload :SquashMergeCommitMessage, "configurable/squash_merge_commit_message"
  autoload :MergeCommitTitle, "configurable/merge_commit_title"
  autoload :MergeCommitMessage, "configurable/merge_commit_message"
  autoload :CommitDcoSignoff, "configurable/commit_dco_signoff"
  autoload :SeatLimitForUpgrades, "configurable/seat_limit_for_upgrades"
  autoload :RestrictLegacyPersonalAccessTokens, "configurable/restrict_legacy_personal_access_tokens"
  autoload :RestrictPersonalAccessTokens, "configurable/restrict_personal_access_tokens"
  autoload :ProgrammaticAccessTokensOptIn, "configurable/programmatic_access_tokens_opt_in"
  autoload :RepoCloneRuleSuite, "configurable/repo_clone_rule_suite"
  autoload :SsoRedirect, "configurable/sso_redirect"
  autoload :OutsideCollaboratorsCanRequestThirdPartyAccess, "configurable/outside_collaborators_can_request_third_party_access"
  autoload :SkipIdpIpAllowlistAppAccessEnabled, "configurable/skip_idp_ip_allowlist_app_access_enabled"
  autoload :IdpIpAllowlistForWeb, "configurable/idp_ip_allowlist_for_web"
  autoload :IpAllowlistConfiguration, "configurable/ip_allowlist_configuration"
  autoload :MaxPackagesAuthorizablePerToken, "configurable/max_packages_authorizable_per_token"
  autoload :SelfServeInvoicePreference, "configurable/self_serve_invoice_preference"
  autoload :ArchiveResourceBlocking, "configurable/archive_resource_blocking"
  autoload :MaxRefUpdates, "configurable/max_ref_updates"
  autoload :DeploymentsSidebarSectionEnabled, "configurable/deployments_sidebar_section_enabled"
  autoload :EnvironmentsSidebarSectionEnabled, "configurable/environments_sidebar_section_enabled"
  autoload :PackagesSidebarSectionEnabled, "configurable/packages_sidebar_section_enabled"
  autoload :PagesUrlSidebarSectionEnabled, "configurable/pages_url_sidebar_section_enabled"
  autoload :ReleasesSidebarSectionEnabled, "configurable/releases_sidebar_section_enabled"
  autoload :OrgToEnterpriseMigration, "configurable/org_to_enterprise_migration"
  autoload :SecurityConfigurations, "configurable/security_configurations"
  autoload :OrgsCanCreateNetworkConfiguration , "configurable/orgs_can_create_network_configuration"
  autoload :OpenSCIM, "configurable/open_scim"
  autoload :PersonalAccessTokenExpirationLimit, "configurable/personal_access_token_expiration_limit"
  autoload :PersonalAccessTokenExpirationLimitExemptionEnabled, "configurable/personal_access_token_expiration_limit_exemption_enabled"
  autoload :DeployKeyPolicy, "configurable/deploy_key_policy"

  extend ActiveSupport::Concern

  included do
    if respond_to?(:has_many)
      T.cast(self, T.class_of(ApplicationRecord::Base)).has_many :configuration_entries,
        as: :target,
        class_name: "Configuration::Entry",
        dependent: :destroy
    end
  end

  # Public: Get the configuration, for getting/setting/listing values.
  #
  # Returns a Configuration object
  def config
    @_configuration ||= ::Configuration.new self
  end

  # Public: Entry a setting would come from if current setting is cleared.
  #
  # name - String entry name
  #
  # Returns a Configuration::Entry or nil
  def configuration_default_entry(name)
    return unless configuration_owner
    configuration_owner.config.entries[name]
  end

  # Public: Where a setting would come from if current setting is cleared.
  #
  # name - String entry name
  #
  # Returns a Configurable or nil
  def configuration_default_entry_owner(name)
    entry = configuration_default_entry(name)
    entry && entry.target
  end

  # Public: What a setting would be if current setting is cleared.
  #
  # name - String entry name
  #
  # Returns a string or nil
  def configuration_default_entry_value(name)
    entry = configuration_default_entry(name)
    entry && entry.value
  end

  # Public: Clear memoized config, then calls super if defined
  #
  # Returns whatever super would return or self if there is no super
  def reload(*args)
    reset_config
    defined?(super) ? super : self
  end

  # Internal: Clear the cached Configuration object
  #
  # Returns nothing
  def reset_config
    @_configuration = nil
  end

  # Internal: Has this object had its Configuration loaded yet?
  #
  # Returns a Boolean
  def config_loaded?
    @_configuration&.loaded?
  end

  # Internal: Populate the Configuration with a preloaded instance. Only valid if the Configuration has not already
  # been loaded.
  #
  # Returns nothing
  def accept_preloaded_config(config)
    @_configuration = config
  end

  # Internal: Define the "owner", for use in cascading configuration values
  #
  # Should return a Configurable or nil
  def configuration_owner
    nil
  end

  # Internal: Define the chain of "owners", for use in cascading configuration values
  # THIS METHOD SHOULD NOT BE OVERRIDDEN
  #
  # Returns an array of Configurables and/or nil
  def configuration_owners
    return [] unless configuration_owner

    configuration_owner.configuration_owners + [configuration_owner]
  end

  # Internal: Load `configuration_owner` in an asynchronous context.
  #
  # Returns a promise resolving to `configuration_owner`
  def async_configuration_owner
    Promise.resolve(configuration_owner)
  end

  # Internal: Defines the chain of configuration owners in an asynchronous context.
  # This is an asynchronous implementation of `configuration_owners`.
  # THIS METHOD SHOULD NOT BE OVERRIDDEN
  #
  # Returns a promise resolving to an array of Configurables and/or nil
  def async_configuration_owners
    async_configuration_owner.then do |owner|
      next [] unless owner

      owner.async_configuration_owners.then do |ancestors|
        ancestors + [owner]
      end
    end
  end

  # Internal: The ID in use for associating configuration entries
  #
  # Can be overridden (see GitHub.configuration_entry_id, below), but should
  # easily be left alone in practice
  #
  # Returns a Integer
  def configuration_entry_id
    T.cast(self, ApplicationRecord::Base).id
  end

  # Internal: The type in use for associating configuration entries
  #
  # Can be overridden (see GitHub.configuration_entry_type, below), but should
  # easily be left alone in practice
  #
  # Returns a String
  def configuration_entry_type
    T.cast(self, Object).class.name
  end

  # Public: Preload all configuration entries for a collection of Configurable models with a small number of database
  # queries. After this call returns, subsequent calls to methods that invoke `.config.get()` will access the cached
  # configuration entries and not touch the database.
  #
  # models - Enumerable collection of any Configurable objects.
  #
  # Returns the collection of models.
  def self.preload_configuration(models)
    needs_config = models.reject(&:config_loaded?)
    entries_by_target = ::Configuration.fetch_entries_for_targets(needs_config)
    needs_config.each do |model|
      config = ::Configuration.new(model, entries: entries_by_target[model])
      model.accept_preloaded_config(config)
    end
    models
  end

  # Async helpers for Configurable
  # usage: `extend Configurable::Async`
  module Async
    # Internal: defines a new method as `async_{method}` that uses a platform
    # loader to asynchronously load a synchronous `Configurable` method
    def async_configurable(*methods)
      methods.each do |method|
        T.cast(self, Module).define_method "async_#{method}" do
          ::Platform::Loaders::Configuration.load(self, method)
        end
      end
    end
  end
end
