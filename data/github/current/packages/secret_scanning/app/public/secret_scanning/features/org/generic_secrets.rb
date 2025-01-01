# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Org
  # Organization level enablement for Generic Secrets
  class GenericSecrets
    include SecretScanning::Features::FeatureFlagHelper

    CONFIG_KEY_USER_ENABLED = "secret_scanning.generic_secrets.user_enabled"
    CONFIG_KEY_ENABLED_FOR_NEW_REPOS = "secret_scanning.generic_secrets.new_business_repos_enable"

    sig { params(org: Organization).void }
    def initialize(org)
      @org = org
      @token_scanning = T.let(SecretScanning::Features::Org::TokenScanning.new(@org), SecretScanning::Features::Org::TokenScanning)
    end

    sig { params(actor: User).void }
    def disable(actor:)
      @org.config.delete(CONFIG_KEY_USER_ENABLED, actor)
    end

    sig { params(actor: User).void }
    def enable(actor:)
      @org.config.enable(CONFIG_KEY_USER_ENABLED, actor)
    end

    # Indicate whether opt-in for this feature is available for this organization
    sig { returns(T::Boolean) }
    def feature_available?
      return false if GitHub.enterprise?
      return false unless @token_scanning.feature_available?
      return false unless @org.advanced_security_purchased?
      true
    end

    # Indicate whether the feature is enabled for this organization
    sig { returns(T::Boolean) }
    def enabled?
      return false unless self.feature_available?
      return true if self.enabled_by_enterprise?
      @org.config.enabled?(CONFIG_KEY_USER_ENABLED)
    end

    sig { returns(T::Boolean) }
    def enabled_by_enterprise?
      # When using security configs, it's not possible to enable it at the enterprise level.
      return false if show_security_config_ux?
      return false unless @org.business
      SecretScanning::Features::Business::GenericSecrets.new(T.must(@org.business)).enabled?
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
      feature_flag_enabled?(@org, FeatureFlags::GENERIC_SECRETS_IN_SECURITY_CONFIGURATIONS)
    end

    # Indicates whether automatic repository opt-in is enabled for this business
    sig { returns(T::Boolean) }
    def enabled_for_new_repos?
      false
    end
  end
end
