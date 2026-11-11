# typed: strict
# frozen_string_literal: true

module SecurityProduct
  class DependabotDelegatedAlertDismissal < SecurityProduct::Service

    sig { params(repository: Repository).void }
    def initialize(repository)
      super(repository)
      @delegated_closures = T.let(Dependabot::SecurityProduct::DelegatedClosures.new(repository), Dependabot::SecurityProduct::DelegatedClosures)
    end

    sig { override.returns(T::Boolean) }
    def enabled?
      log_timing do
        @delegated_closures.enabled?
      end
    end

    sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def can_enable?(actor:, options:)
      log_timing do
        if repository.archived? || repository.deleted?
          return Result.new(false, :feature_not_available_on_archived_or_deleted_repos)
        end

        # Check if GHAS is enabled (required for delegated alert dismissal)
        unless ::CodeSecurity::Features::AdvancedSecurityHelper.code_security_features_usable?(repository: repository)
          message = if repository.advanced_security_products_bundled?
            :advanced_security_disabled
          else
            :code_security_disabled
          end
          return Result.new(false, message)
        end

        # Check if feature is available (feature flag, user-owned repos, etc.)
        unless @delegated_closures.can_enable?
          return Result.new(false, :feature_not_available)
        end

        # Vulnerability Alerts must be enabled as a prerequisite
        vulnerability_alerts = SecurityProduct::VulnerabilityAlerts.new(repository)
        unless vulnerability_alerts.enabled?
          return Result.new(false, :vulnerability_alerts_disabled)
        end

        # Check enterprise policy restrictions
        if blocked_by_enterprise_policy?(actor, options)
          return Result.new(false, :vulnerability_alerts_restricted_by_enablement_policy)
        end

        Result.new(true)
      end
    end

    sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def on_enable(actor:, options:)
      log_timing do
        return SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(to_sym, options)) if repository.deleted?

        @delegated_closures.enable(actor: actor)

        SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(to_sym, options))
      end
    end

    sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def on_disable(actor:, options:)
      log_timing do
        return SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(to_sym, options)) if repository.deleted?

        @delegated_closures.disable(actor: actor)

        SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(to_sym, options))
      end
    end

    sig { override.returns(Symbol) }
    def to_sym
      :dependabot_delegated_alert_dismissal
    end

    sig { override.returns(String) }
    def self.name
      "Dependabot Delegated Alert Dismissal"
    end

    sig { override.params(symbol: T.nilable(SecurityProduct::Result::Error)).returns(String) }
    def self.error_to_message(symbol)
      case symbol
      when :advanced_security_disabled
        "Delegated alert dismissal cannot be enabled because Advanced Security is disabled for this repository."
      when :code_security_disabled
        "Delegated alert dismissal cannot be enabled because code security features are disabled for this repository."
      when :feature_not_available
        "Delegated alert dismissal is not available for this repository."
      when :vulnerability_alerts_disabled
        "Delegated alert dismissal cannot be enabled because vulnerability alerts are disabled for this repository."
      when :vulnerability_alerts_restricted_by_enablement_policy
        "Delegated alert dismissal cannot be enabled due to an enterprise policy."
      else
        super
      end
    end

    private

    # Checks if toggling Dependabot delegated alert dismissal is restricted by Configurable::DependabotAlertsEnablementPolicy
    sig { params(actor: User, options: T.untyped).returns(T::Boolean) }
    def blocked_by_enterprise_policy?(actor, options)
      return false if options.present? && options[:is_repo_creation]
      SecurityProduct::Permissions::RepoAuthz.new(repository, actor:).manage_repo_dependabot_alerts_enablement_blocked_by_policy?
    end
  end
end
