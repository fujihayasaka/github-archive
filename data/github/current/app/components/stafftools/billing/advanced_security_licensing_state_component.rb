# typed: strict
# frozen_string_literal: true

module Stafftools
  module Billing
    class AdvancedSecurityLicensingStateComponent < ApplicationComponent
      sig { params(entity: T.any(::Organization, Business)).void }
      def initialize(entity:)
        @entity = entity
      end

      sig { returns T::Boolean }
      def active_advanced_security_trial?
        @entity.is_a?(Business) && @entity.has_active_advanced_security_trial?
      end

      sig { returns(String) }
      def trial_type_label
        trial_type = @entity.config.get("code_security_trial_type").presence ||
                     @entity.config.get("secret_protection_trial_type").presence

        helpers.trial_type_display_name(trial_type&.to_sym) || "Self-Serve"
      end

      sig { returns T::Boolean }
      def manual_advanced_security_trial?
        return true if manual_secret_protection_trial? && manual_code_security_trial?
        @entity.advanced_security_enabled_type_for_entity == Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME &&
        @entity.advanced_security_seats_for_entity == 0
      end

      sig { returns T::Boolean }
      def manual_secret_protection_trial?
        (@entity.advanced_security_enabled_type_for_entity == Configurable::AdvancedSecurityBillingConfig::SPLIT_VOLUME ||
          @entity.advanced_security_enabled_type_for_entity == Configurable::AdvancedSecurityBillingConfig::SECRET_PROTECTION_VOLUME) &&
          @entity.secret_scanning_license_count == 0
      end

      sig { returns T::Boolean }
      def manual_code_security_trial?
        (@entity.advanced_security_enabled_type_for_entity == Configurable::AdvancedSecurityBillingConfig::SPLIT_VOLUME ||
          @entity.advanced_security_enabled_type_for_entity == Configurable::AdvancedSecurityBillingConfig::CODE_SECURITY_VOLUME) &&
          @entity.code_security_license_count == 0
      end

      sig { returns EnterpriseCloudOnboard::SecretProtectionTrial }
      memoize def secret_protection_trial
        EnterpriseCloudOnboard::SecretProtectionTrial.new(billable_entity: @entity)
      end

      sig { returns EnterpriseCloudOnboard::CodeSecurityTrial }
      memoize def code_security_trial
        EnterpriseCloudOnboard::CodeSecurityTrial.new(billable_entity: @entity)
      end

      sig { returns T::Boolean }
      def any_trial?
        active_advanced_security_trial? ||
        manual_secret_protection_trial? ||
        manual_code_security_trial? ||
        secret_protection_trial.enabled? ||
        code_security_trial.enabled?
      end

      sig { returns(T::Boolean) }
      def any_metered_lock?
        @entity.advanced_security_metered_usage_locked? ||
          @entity.secret_protection_metered_usage_locked? ||
          @entity.code_security_metered_usage_locked?
      end
    end
  end
end
