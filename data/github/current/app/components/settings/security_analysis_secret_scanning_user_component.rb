# typed: true
# frozen_string_literal: true

module Settings
  class SecurityAnalysisSecretScanningUserComponent < ApplicationComponent
    include GitHub::Memoizer
    include SecurityAnalysisSettingsHelper
    include SecretScanning::Features::FeatureFlagHelper

    sig { params(owner: User).void }
    def initialize(owner:)
      @owner = owner
      @push_protection = SecretScanning::Features::User::PushProtection.new(@owner)
    end

    private

    # Display the push protection toggle if the push protection feature is available
    sig { returns(T::Boolean) }
    def render?
      return false unless @owner.user?
      return false unless @push_protection.feature_available?
      feature_flag_enabled_in_hierarchy?(@owner, FeatureFlags::PUSH_PROTECTION_USER_SETTINGS)
    end

    sig { returns(T::Boolean) }
    def secret_scanning_push_protection_feature_available?
      @push_protection.feature_available?
    end

    sig { returns(T::Boolean) }
    def secret_scanning_push_protection_enabled_for_user?
      @push_protection.enabled?
    end

    sig { returns(T::Boolean) }
    def secret_scanning_push_protection_enabled_for_user_by_default?
      feature_flag_enabled_in_hierarchy?(@owner, FeatureFlags::PUSH_PROTECTION_FOR_USERS_OPT_OUT)
    end

    sig { returns(String) }
    def supported_secrets_href
      "#{docs_base_url}/code-security/secret-scanning/secret-scanning-patterns#supported-secrets"
    end

    sig { returns(String) }
    def docs_base_url
      GitHub.help_url(ghec_exclusive: @owner.organization? && (@owner.business || @owner.business_plus?))
    end

    sig { returns(String) }
    def get_disable_dialog_box_text
      return "Pushes that contain secrets will not be blocked." if secret_scanning_push_protection_enabled_for_user_by_default?
      "This will disable push protection wherever you push"
    end

    sig { returns(String) }
    def get_enable_dialog_box_text
      return "Pushes that contain secrets will be blocked on public repositories. You'll have the option to bypass the block." if secret_scanning_push_protection_enabled_for_user_by_default?
      "This will enable push protection wherever you push"
    end
  end
end
