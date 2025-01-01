# typed: true
# frozen_string_literal: true

module Codespaces
  module UniqueCodespaceBillingIdentifierHelper
    extend T::Sig
    extend T::Helpers

    abstract!

    sig { abstract.returns(Codespaces::EphemeralBillingMessage) }
    def billing_message; end

    sig { abstract.returns(T.untyped) }
    def billing_entry; end

    sig { abstract.returns(T.untyped) }
    def tracked_usage; end

    def unique_identifier(prefix = "")
      parts = [
        billing_message.event_id,
        billing_entry.codespace_plan_name,
        billing_entry.codespace_guid,
        tracked_usage.formatted_sku_name
      ]
      prefix + parts.join("-")
    end

    def prebuild_unique_identifier(prefix = "")
      parts = [
        billing_message.event_id,
        billing_entry.prebuild_plan_name,
        billing_entry.prebuild_template_guid,
        tracked_usage.formatted_sku_name
      ]
      prefix + parts.join("-")
    end
  end
end
