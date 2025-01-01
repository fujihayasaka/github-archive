# typed: true
# frozen_string_literal: true

module SecurityCenter
  module Coverage
    module SecuritySettings
      class AdvancedSecurityComponent < ApplicationComponent
        extend T::Sig

        TEST_SELECTOR = "security-center-enablement-advanced-security-settings"

        sig { params(enablement_data: Repositories::Settings::SecurityAnalysisEnablementFormComponent::Data, advanced_security_contributor_count: Integer).void }
        def initialize(enablement_data, advanced_security_contributor_count)
          @enablement_data = enablement_data
          @advanced_security_contributor_count = advanced_security_contributor_count
        end

        def setting_disabled?
          return true if @enablement_data.advanced_security_blocked_by_turboghas_error
          return true if @enablement_data.advanced_security_blocked_by_in_progress_setting

          @enablement_data.advanced_security_blocked_by_policy ||
            @enablement_data.advanced_security_blocked_by_backfill ||
            @enablement_data.advanced_security_will_exceed_seat_allowance
        end

        def blocked_message
          return "Unable to determine license usage. Please try again later." if @enablement_data.advanced_security_blocked_by_turboghas_error
          return "An org-level configuration update is in progress. Please try again later." if @enablement_data.advanced_security_blocked_by_in_progress_setting

          if @enablement_data.advanced_security_blocked_by_policy
            "Modifying GitHub Advanced Security has been blocked by an enterprise policy. "
          elsif @enablement_data.advanced_security_blocked_by_backfill
            "GitHub Advanced Security backfill in progress. Please try again later."
          elsif @enablement_data.advanced_security_will_exceed_seat_allowance
            "You do not have enough seats to enable GitHub Advanced Security."
          end
        end

        def feature_description
          if @enablement_data.advanced_security_enabled || @enablement_data.advanced_security_blocked_by_turboghas_error
            "GitHub Advanced Security features are billed per active committer."
          else
            "GitHub Advanced Security features are billed per active committer. Enabling will use #{@enablement_data.advanced_security_license_prompt}"
          end
        end
      end
    end
  end
end
