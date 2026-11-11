# typed: true
# frozen_string_literal: true

module Stafftools
  module AdvancedSecurity
    class MeteredServicesLockFormComponent < ApplicationComponent
      attr_reader :is_bundled, :entity, :disable_padding

      REASON_LABELS = T.let({
        "BudgetExhausted" => "Budget Exhausted",
        "BillingLocked" => "Billing Locked",
        "true" => "Legacy Lock",
      }.freeze, T::Hash[String, String])

      def initialize(is_bundled:, entity:, disable_padding: false)
        @is_bundled = is_bundled
        @entity = entity
        @disable_padding = disable_padding
      end

      def sku_entries
        if is_bundled
          [{
            label: "Advanced Security",
            locked: entity.advanced_security_metered_usage_locked?,
            reason: entity.advanced_security_metered_usage_lock_reason_for_entity,
            hidden_fields: { is_bundled: "true" },
          }]
        else
          [
            {
              label: "Secret Protection",
              locked: entity.secret_protection_metered_usage_locked?,
              reason: entity.secret_protection_metered_usage_lock_reason_for_entity,
              hidden_fields: { is_bundled: "false", sku: "secret_security" },
            },
            {
              label: "Code Security",
              locked: entity.code_security_metered_usage_locked?,
              reason: entity.code_security_metered_usage_lock_reason_for_entity,
              hidden_fields: { is_bundled: "false", sku: "code_security" },
            },
          ]
        end
      end

      def reason_label(reason)
        REASON_LABELS[reason] || reason
      end
    end
  end
end
