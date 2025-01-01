# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Repo
  # Repo level enablement for Delegated Alert Closures
  class DelegatedClosures
    include SecretScanning::Features::FeatureFlagHelper

    CONFIG_KEY_USER_ENABLED = "secret_scanning.delegated_closures.user_enabled"

    sig { params(repo: Repository).void }
    def initialize(repo)
      @repo = repo
      @token_scanning = T.let(SecretScanning::Features::Repo::TokenScanning.new(@repo), SecretScanning::Features::Repo::TokenScanning)
      @org_owner_delegated_closures = nil #T.let(nil, T.nilable(SecretScanning::Features::Org::DelegatedClosures))
      if @repo.owner&.is_a?(Organization)
        @org_owner_delegated_closures = T.let(SecretScanning::Features::Org::DelegatedClosures.new(T.cast(@repo.owner, Organization)), T.nilable(SecretScanning::Features::Org::DelegatedClosures))
      end
    end

    # Indicate whether opt-in for this feature is available for this repo
    sig { returns(T::Boolean) }
    def feature_available?
      return false unless @token_scanning.enabled?
      return false unless @repo.owner&.advanced_security_purchased?
      # Once we remove the FF, this will just be `true`
      feature_flag_enabled?(@repo, FeatureFlags::SHOW_CLOSURE_REQUESTS_ORG_SETTING)
    end

    sig { returns(T::Boolean) }
    def enabled?
      return false unless self.feature_available?
      return true if self.enabled_by_organization?
      @repo.config.enabled?(CONFIG_KEY_USER_ENABLED)
    end

    sig { returns(T::Boolean) }
    def enabled_by_organization?
      if @org_owner_delegated_closures.nil?
        return false
      end
      @org_owner_delegated_closures.enabled?
    end

    sig { params(actor: User).void }
    def disable(actor:)
      @repo.config.delete(CONFIG_KEY_USER_ENABLED, actor)
    end

    sig { params(actor: User).void }
    def enable(actor:)
      @repo.config.enable(CONFIG_KEY_USER_ENABLED, actor)
    end
  end
end
