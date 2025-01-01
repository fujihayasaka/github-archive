# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning::Features::Repo
  # Core Token Scanning feature (ie. GHAS Secret Scanning)
  #
  # We currently distinguish 2 branches of Secret Scanning:
  #
  # [Public scans]
  # - Included and mandatory for ALL public repos no matter their ownership or licensing
  # - Includes automatic revocation of github and partner tokens
  #
  # [GHAS scans]
  # - Only available to repos part of a GHAS organization/enterprise
  # - Includes the full Secret Scanning user experience
  # - Available to repos of any visibility (Public, Internal, Private), including archived repos.
  #
  # As a result, public repos can currently benefit from both types of scans if they are also part of a GHAS org.
  #
  # This feature class focuses on GHAS Secret Scanning. Public scanning will be handled in a separate PublicScanning feature class.
  class TokenScanning
    extend T::Sig
    include SecretScanning::Features::FeatureFlagHelper

    CONFIG_KEY_USER_ENABLED = "token_scanning.user_enabled"
    CONFIG_KEY_STAFF_DISABLED = "token_scanning.disabled"
    CONFIG_KEY_STAFF_NETWORK_DISABLED = "token_scanning.network_disabled"

    sig { params(repo: Repository).void }
    def initialize(repo)
      @repo = repo
    end

    # Indicates whether the GHAS Token Scanning feature as a whole is available to the current repository
    #
    # This contains the most basic checks and those NOT indicate whether the feature is enabled.
    # Refer to #enabled? for most use cases.
    sig { returns(T::Boolean) }
    def feature_available?
      self.base_feature_available? && !self.staff_locked?
    end

    # Indicates whether GHAS Token Scanning is enabled for the current repository
    sig { returns(T::Boolean) }
    def enabled?
      # can't be enabled on a deleted repo
      return false if @repo.deleted?

      # base feature must be available
      return false unless self.feature_available?

      # if available, advanced security must be enabled
      return false if SecretScanning::Features::AdvancedSecurityHelper.advanced_security_configurable?(@repo) && !@repo.advanced_security_enabled?

      # repo config check
      @repo.config.enabled?(CONFIG_KEY_USER_ENABLED)
    end

    # Indicates whether the feature is available to administer in stafftools
    # This is exposed separately because most other enablement methods need to check for staff locks
    sig { returns(T::Boolean) }
    def stafftools_available?
      return false if GitHub.enterprise? # no stafftool features for GHES currently

      self.base_feature_available?
    end

    # Enable token scanning for the current repository
    # NOTE: This only sets the config key for secret scanning. It does not include instrumentation for backfills, repo-sync, analytics, etc.
    # Most flows requiring end-to-end secret scanning enablement should instead use:
    # SecurityProduct::ServiceManager.new(repository).toggle_services(owner, services_to_enable: [:token_scanning])
    sig { params(actor: User).void }
    def enable(actor:)
      @repo.config.enable(CONFIG_KEY_USER_ENABLED, actor)
    end

    # Disable token scanning for the current repository
    sig { params(actor: User).void }
    def disable(actor:)
      @repo.config.delete(CONFIG_KEY_USER_ENABLED, actor)
    end

    # Indicates if token scanning is staff locked for the current repository
    sig { returns(T::Boolean) }
    def staff_locked?
      self.staff_disabled? || self.staff_network_disabled?
    end

    # Removes token scanning staff locks for the current repository
    sig { params(actor: User).void }
    def staff_unlock(actor:)
      @repo.config.delete(CONFIG_KEY_STAFF_DISABLED, actor)
    end

    # Removes token scanning network staff locks for the current repository
    sig { params(actor: User).void }
    def staff_network_unlock(actor:)
      @repo.config.delete(CONFIG_KEY_STAFF_NETWORK_DISABLED, actor)
    end

    # Staff lock token scanning for the current repository
    sig { params(actor: User).void }
    def staff_disable(actor:)
      @repo.config.enable(CONFIG_KEY_STAFF_DISABLED, actor)
    end

    # Staff lock token scanning for the current repository, marked as part of a network disable
    sig { params(actor: User).void }
    def staff_network_disable(actor:)
      @repo.config.enable(CONFIG_KEY_STAFF_NETWORK_DISABLED, actor)
    end

    # Indicates whether a feedback banner should be shown for general secret scanning feedback
    # A push protection feedback banner is handled separately in the push protection feature
    sig { returns(T::Boolean) }
    def feedback_link_enabled?
      return false unless self.feature_available?
      feature_flag_enabled?(@repo, FeatureFlags::FEEDBACK_LINK)
    end

    # Indicates whether a historical backfill scan should be queued if none has been run for the given repository
    sig { returns(T::Boolean) }
    def historical_backfill_scan_enabled?
      return false unless @repo.public?
      return false unless GitHub.dotcom_request?
      return false if @repo.owner&.advanced_security_purchased?
      feature_flag_enabled?(@repo, FeatureFlags::HISTORICAL_BACKFILL_SCAN)
    end

    sig { returns(T::Boolean) }
    def staff_disabled?
      @repo.config.enabled?(CONFIG_KEY_STAFF_DISABLED)
    end

    sig { returns(T::Boolean) }
    def staff_network_disabled?
      @repo.config.enabled?(CONFIG_KEY_STAFF_NETWORK_DISABLED)
    end

    # Indicates whether the given actor is allowed to view alerts for the current repository
    sig { params(actor: T.nilable(User)).returns(T::Boolean) }
    def view_alerts_allowed?(actor)
      return false if actor.nil?
      return false unless self.feature_available?

      @repo.can_view_secret_scanning_alerts?(actor)
    end

    # Indicates whether the given actor is allowed to resolve alerts for the current repository
    # commits type should be Google::Protobuf::RepeatedField[String] but is breaking Sorbet right now
    sig { params(actor: T.nilable(User), commits: T.untyped).returns(T::Boolean) }
    def resolve_alerts_allowed?(actor, commits)
      return false if actor.nil?
      return false unless self.feature_available?

      @repo.can_resolve_secret_scanning_alerts?(actor, commits)
    end

    # Indicates whether the repo is part of the beta release of expanding the
    # full Secret Scanning experience to all public repos.
    #
    # This makes the additional check against GHAS because we want callers of this method
    # to be separate enablement coming from the beta versus `base_feature_available?`
    sig { returns(T::Boolean) }
    def ux_on_public_repo_enabled?
      return false unless @repo.public?
      return false if SecretScanning::Features::AdvancedSecurityHelper.advanced_security_available?(@repo)
      return false if @repo.owner.nil?
      feature_flag_enabled?(T.must(@repo), FeatureFlags::READ_PUBLIC_REPO_ALERTS)
    end

    sig { returns(T::Boolean) }
    def show_page_serialize_location_refactor_enabled?
      return false unless self.enabled?

      feature_flag_enabled?(@repo, FeatureFlags::SHOW_PAGE_SERIALIZE_LOCATION_REFACTOR)
    end

    sig { params(alert: GitHub::TokenScanning::Service::Token).returns(T::Boolean) }
    def one_click_reporting_enabled?(alert)
      return false if @repo.public?
      return false unless enabled?
      return false if GitHub.single_or_multi_tenant_enterprise?
      return false unless feature_flag_enabled?(@repo, FeatureFlags::ONE_CLICK_REPORT)
      github_reportable_types = %w(GITHUB_TOKEN_V2 GITHUB GITHUB_PERSONAL_ACCESS_TOKEN)
      # This feature is only available for classic and fine-grained PATs right now
      return false unless github_reportable_types.include?(alert.token_type)
      true
    end

    private

    # Base feature availability checks
    sig { returns(T::Boolean) }
    def base_feature_available?
      # global config check
      # should be on by default for dotcom and needs to be enabled for enterprise
      return false unless GitHub.configuration_secret_scanning_enabled?

      # For orgs with advanced security, private and public repos within it have
      # secret scanning available
      return true if SecretScanning::Features::AdvancedSecurityHelper.advanced_security_available?(@repo)

      # For public repos, we need to check the feature flag for now.
      # Long-term, the feature flag check can be removed and as long as the repo is public,
      # then the secret scanning UX will be available to them.
      if @repo.public?
        # check for flag
        return false unless ux_on_public_repo_enabled?
        true
      else
        false
      end
    end
  end
end
