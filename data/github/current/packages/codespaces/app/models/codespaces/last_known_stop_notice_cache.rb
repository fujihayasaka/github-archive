# typed: true
# frozen_string_literal: true

module Codespaces
  class LastKnownStopNoticeCache
    EXPIRY_HOURS = 1

    ENTITLEMENTS_LIMIT_REACHED_FOR_USER = "entitlements_limit_reached_user"
    SPENDING_LIMIT_REACHED_FOR_USER     = "spending_limit_reached_user"
    SPENDING_LIMIT_REACHED_FOR_ORG      = "spending_limit_reached_org"
    GENERIC_BILLING_ERROR_FOR_USER      = "generic_billing_error_for_user"
    GENERIC_BILLING_ERROR_FOR_ORG       = "generic_billing_error_for_org"

    NOTICE_TEXT = {
      ENTITLEMENTS_LIMIT_REACHED_FOR_USER => "you've used 100% of included services for GitHub Codespaces.",
      SPENDING_LIMIT_REACHED_FOR_USER     => "you've used 100% of your spending limit for GitHub Codespaces. You can update your limit in your GitHub billing settings to continue using Codespaces.",
      SPENDING_LIMIT_REACHED_FOR_ORG      => "you've used 100% of your spending limit for GitHub Codespaces. Please contact an organization administrator to continue using Codespaces.",
      GENERIC_BILLING_ERROR_FOR_USER      => "there was an error with your GitHub billing account. Please check your billing settings to continue using Codespaces.",
      GENERIC_BILLING_ERROR_FOR_ORG       => "there was an error with your GitHub billing account. Please contact an organization administrator to continue using Codespaces.",
    }.freeze

    class << self
      def mset(billable_owner_ids:, notice:)
        return unless FeatureFlag.vexi.enabled_or_raise?(:codespaces_stop_notice_cache) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        return unless billable_owner_ids&.any? && notice.present?

        ActiveRecord::Base.connected_to(role: :writing) do
          Codespaces::Kv.store.mset(
            build_codespace_last_known_stop_notices_hash(billable_owner_ids, notice),
            expires: EXPIRY_HOURS.hours.from_now
          )
        end
      end

      def get(billable_owner_id:)
        return unless FeatureFlag.vexi.enabled_or_raise?(:codespaces_stop_notice_cache) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

        Codespaces::Kv.store.get(key(billable_owner_id: billable_owner_id)).value { nil }
      end

      def get_text(billable_owner_id:)
        cached_notice = get(billable_owner_id: billable_owner_id)

        NOTICE_TEXT[cached_notice]
      end

      def key(billable_owner_id:)
        "codespaces:last_known_stop_notice:v1:#{billable_owner_id}"
      end

      def clear(billable_owner_id:)
        return unless Codespaces::Kv.store.exists(key(billable_owner_id: billable_owner_id)).value!

        ActiveRecord::Base.connected_to(role: :writing) do
          Codespaces::Kv.store.del(key(billable_owner_id: billable_owner_id))
        end
      end

      private

      def build_codespace_last_known_stop_notices_hash(billable_owner_ids, notice)
        billable_owner_ids.each_with_object({}) do |billable_owner_id, hash|
          hash[key(billable_owner_id: billable_owner_id)] = notice
        end
      end
    end
  end
end
