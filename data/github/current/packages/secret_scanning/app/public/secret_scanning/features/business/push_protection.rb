# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning::Features::Business
  # Business level enablement for Push Protection
  class PushProtection
    include SecretScanning::Features::FeatureFlagHelper

    CONFIG_KEY_ENABLED_FOR_NEW_REPOS = "secret_scanning_push_protection.new_business_repos_enable"
    CONFIG_KEY_CUSTOM_MESSAGE_ENABLED = "secret_scanning_push_protection.business.custom_message_enabled"

    sig { params(business: Business).void }
    def initialize(business)
      @business = business
      @token_scanning = SecretScanning::Features::Business::TokenScanning.new(@business)
    end

    # Indicate whether the feature is available for this business
    sig { returns(T::Boolean) }
    def feature_available?
      # the business should have the GHAS license
      return false unless @business.advanced_security_purchased? ||
        feature_flag_enabled_in_hierarchy?(@business, FeatureFlags::PUSH_PROTECTION_FOR_FPR)

      # token scanning must be available
      @token_scanning.feature_available?
    end

    # Indicates whether automatic repository opt-in is enabled for this business
    sig { returns(T::Boolean) }
    def enabled_for_new_repos?
      return false unless self.feature_available?

      @business.config.enabled?(CONFIG_KEY_ENABLED_FOR_NEW_REPOS)
    end

    # Enable automatic repository opt-in
    sig { params(actor: User).void }
    def enable_for_new_repos(actor:)
      @business.config.enable(CONFIG_KEY_ENABLED_FOR_NEW_REPOS, actor)
    end

    # Disable automatic repository opt-in
    sig { params(actor: User).void }
    def disable_for_new_repos(actor:)
      @business.config.delete(CONFIG_KEY_ENABLED_FOR_NEW_REPOS, actor)
    end

    # Indicates whether the custom message feature is available for this business
    sig { returns(T::Boolean) }
    def custom_message_enabled?
      return false unless self.feature_available?
      @business.config.enabled?(CONFIG_KEY_CUSTOM_MESSAGE_ENABLED)
    end

    # Indicates whether or not the custom message should actually be displayed.
    # Returns true if the custom message is both enabled and not empty.
    sig { returns(T::Boolean) }
    def custom_message_active?
      return false if @business.nil?
      msg = @business.get_push_protection_custom_message
      self.custom_message_enabled? && !msg.nil? && !msg.empty?
    end

    # Enables displaying a custom message on blocked pushes for this business
    sig { params(actor: User).void }
    def enable_custom_message(actor:)
      @business.config.enable(CONFIG_KEY_CUSTOM_MESSAGE_ENABLED, actor)
    end

    # Disables displaying a custom message on blocked pushes for this business
    sig { params(actor: User).void }
    def disable_custom_message(actor:)
      @business.config.delete(CONFIG_KEY_CUSTOM_MESSAGE_ENABLED, actor)
    end
  end
end
