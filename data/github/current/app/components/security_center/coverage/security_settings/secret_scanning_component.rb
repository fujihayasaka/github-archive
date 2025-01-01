# typed: true
# frozen_string_literal: true

module SecurityCenter
  module Coverage
    module SecuritySettings
      class SecretScanningComponent < ApplicationComponent
        extend T::Sig

        SECRET_SCANNING_TEST_SELECTOR = "security-center-enablement-secret-scanning-settings"
        PUSH_PROTECTION_TEST_SELECTOR = "security-center-enablement-push-protection-settings"


        sig { params(enablement_data: Repositories::Settings::SecurityAnalysisEnablementFormComponent::Data).void }
        def initialize(enablement_data)
          @enablement_data = enablement_data
        end

        def setting_disabled?(feature)
          case feature
          when :secret_scanning
            return true if @enablement_data.secret_scanning_blocked_by_in_progress_setting
            @enablement_data.secret_scanning_blocked_by_policy
          when :secret_scanning_push_protection
            return true if @enablement_data.secret_scanning_push_protection_blocked_by_in_progress_setting
            @enablement_data.secret_scanning_push_protection_blocked_by_policy
          end
        end

        def feature_available?(feature)
          case feature
          when :secret_scanning
            @enablement_data.secret_scanning_show_org_enablement_experience
          when :secret_scanning_push_protection
            # Use this check instead of secret_scanning_push_protection_visible because the visibility check relies
            # on token scanning being enabled, which we don't need for the panel, since we still want to show a blocked setting.
            @enablement_data.secret_scanning_push_protection_enabled_for_instance && @enablement_data.show_unarchived_features
          end
        end

        def public_scanning_feature_description
          safe_join([
            "GitHub will always send alerts to partners for detected secrets in public repositories. ",
            ActionController::Base.helpers.link_to(
              "Learn more about partner patterns",
              "#{DocsUrlConfig.url_for("code-security/about-secret-scanning-alerts-for-partners", ghec: true)}"
            ),
            "."]
          )
        end

        def blocked_message
          if @enablement_data.secret_scanning_blocked_by_in_progress_setting || @enablement_data.secret_scanning_push_protection_blocked_by_in_progress_setting
            return "An org-level configuration update is in progress. Please try again later."
          end

          if features_blocked_by_policy.any?
            "Modifying #{features_blocked_by_policy.to_sentence} has been blocked by an enterprise policy. "
          end
        end

        def feature_description(feature)
          case feature
          when :secret_scanning
            if @enablement_data.secret_scanning_public_scanning_enabled
              safe_join([
                "Receive alerts on GitHub for detected secrets, keys, or other tokens detected using partner or custom patterns. ",
                public_scanning_feature_description
              ])
            else
              "Receive alerts on GitHub for detected secrets, keys, or other tokens detected using partner or custom patterns."
            end
          when :secret_scanning_push_protection
            "Block commits that contain secrets."
          end
        end

        def left_margin
          @enablement_data.advanced_security_visible ? 3 : 0
        end

        def heading_font_size
          @enablement_data.advanced_security_visible ? 4 : 3
        end

        private

        memoize def features_blocked_by_policy
          features_blocked = []
          features_blocked << "secret scanning" if @enablement_data.secret_scanning_blocked_by_policy
          features_blocked << "push protection" if @enablement_data.secret_scanning_push_protection_blocked_by_policy
          features_blocked
        end
      end
    end
  end
end
