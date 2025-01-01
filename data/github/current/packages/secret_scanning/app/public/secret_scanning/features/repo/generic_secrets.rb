# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Repo
  # Repository level enablement for Generic Secrets
  class GenericSecrets
    include SecretScanning::Features::FeatureFlagHelper

    CONFIG_KEY_USER_ENABLED = "secret_scanning.generic_secrets.user_enabled"

    sig { params(repo: Repository).void }
    def initialize(repo)
      @repo = repo
      @token_scanning = T.let(SecretScanning::Features::Repo::TokenScanning.new(@repo), SecretScanning::Features::Repo::TokenScanning)
    end

    sig { params(actor: User).void }
    def disable(actor:)
      @repo.config.delete(CONFIG_KEY_USER_ENABLED, actor)
    end

    sig { params(actor: User).void }
    def enable(actor:)
      @repo.config.enable(CONFIG_KEY_USER_ENABLED, actor)
    rescue Configuration::ConflictingRecordError
      # Apparently can happen cuz of a race condition.
      # This error is rare and happens intermittently,
      # so just gonna assume it's weird user behavior and no-op.
    end

    # Indicate whether opt-in for this feature is available for this repository
    sig { returns(T::Boolean) }
    def feature_available?
      return false if GitHub.enterprise?
      return false unless @token_scanning.enabled?
      return false unless @repo.owner&.advanced_security_purchased?
      true
    end

    # Indicate whether the feature is enabled for this repository
    sig { returns(T::Boolean) }
    def enabled?
      return false unless self.feature_available?
      return true if self.enabled_by_enterprise?
      return true if self.enabled_by_organization?
      @repo.config.enabled?(CONFIG_KEY_USER_ENABLED)
    end

    sig { returns(T::Boolean) }
    def enabled_by_organization?
      owner = @repo.owner
      return false unless owner.is_a?(Organization)
      SecretScanning::Features::Org::GenericSecrets.new(owner).enabled?
    end

    sig { returns(T::Boolean) }
    def enabled_by_enterprise?
      owner = @repo.owner
      return false unless owner.is_a?(Organization)
      return false unless owner.business
      SecretScanning::Features::Business::GenericSecrets.new(T.must(owner.business)).enabled?
    end

    sig { params(user: User).returns(T::Boolean) }
    def show_user_feedback_link?(user)
      return false unless enabled?
      return false unless feature_flag_enabled?(user, FeatureFlags::GENERIC_SECRETS_FEEDBACK_LINK)
      return false if user.dismissed_notice?(UserNotice::AI_DETECTED_SECRET_SCANNING_FEEDBACK_NOTICE)
      true
    end

    sig { returns(T::Boolean) }
    def show_security_config_ux?
      feature_flag_enabled?(@repo, FeatureFlags::GENERIC_SECRETS_IN_SECURITY_CONFIGURATIONS)
    end
  end
end
