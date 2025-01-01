# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Repo
  # Repository level enablement for Delegated Bypass
  class DelegatedBypass
    include SecretScanning::Features::FeatureFlagHelper

    CONFIG_KEY_USER_ENABLED = "secret_scanning.delegated_bypass.user_enabled"

    sig { params(repo: Repository).void }
    def initialize(repo)
      @repo = repo
      @push_protection = T.let(SecretScanning::Features::Repo::PushProtection.new(@repo), SecretScanning::Features::Repo::PushProtection)
      @org_owner_delegated_bypass = T.let(nil, T.nilable(SecretScanning::Features::Org::DelegatedBypass))
      if @repo.owner&.is_a?(Organization)
        @org_owner_delegated_bypass = T.let(SecretScanning::Features::Org::DelegatedBypass.new(T.cast(@repo.owner, Organization)), T.nilable(SecretScanning::Features::Org::DelegatedBypass))
      end
    end

    sig { params(actor: User).void }
    def disable(actor:)
      @repo.config.delete(CONFIG_KEY_USER_ENABLED, actor)
    end

    sig { params(actor: User).void }
    def enable(actor:)
      @repo.config.enable(CONFIG_KEY_USER_ENABLED, actor)
    end

    # Indicate whether opt-in for this feature is available for this repository
    sig { returns(T::Boolean) }
    def feature_available?
      return false unless @push_protection.enabled?
      return false unless SecretScanning::Features::AdvancedSecurityHelper.secret_scanning_available?(@repo) && @repo.owner&.is_a?(Organization)
      true
    end

    # Indicate whether the feature is enabled for this repository, either directly
    # or via its owning organization
    sig { returns(T::Boolean) }
    def enabled?
      return false unless self.feature_available?
      return false if self.disabled_by_security_configuration?
      return true if self.enabled_by_security_configuration?
      return false if @repo.config.inherited?(CONFIG_KEY_USER_ENABLED)
      @repo.config.enabled?(CONFIG_KEY_USER_ENABLED)
    end

    sig { returns(T::Boolean) }
    def enabled_by_security_configuration?
      return false unless feature_available_for_org_or_business?

      applied_security_configuration&.secret_scanning_delegated_bypass_enabled? || false
    end

    sig { returns(T::Boolean) }
    def disabled_by_security_configuration?
      return false unless feature_available_for_org_or_business?

      applied_security_configuration&.secret_scanning_delegated_bypass_disabled? || false
    end

    # Indicates whether the given actor is allowed to view the bypass requests list
    sig { params(actor: T.nilable(User)).returns(T::Boolean) }
    def can_view_requests_list?(actor)
      return false if actor.nil?
      return false unless self.enabled?

      @repo.can_view_delegated_bypass_requests_list?(actor)
    end

    private

    sig { returns(T::Boolean) }
    def feature_available_for_org_or_business?
      org_feature_available = @org_owner_delegated_bypass&.feature_available? || false
      business_feature_available = @business_owner_delegated_bypass&.feature_available? || false
      org_feature_available || business_feature_available
    end

    sig { returns(T.nilable(SecurityConfiguration)) }
    def applied_security_configuration
      repo_config = @repo.repository_security_configuration
      return nil unless repo_config&.applied?

      repo_config.security_configuration
    end
  end
end
