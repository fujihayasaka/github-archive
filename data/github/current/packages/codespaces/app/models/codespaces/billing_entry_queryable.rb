# typed: true
# frozen_string_literal: true

module Codespaces
  module BillingEntryQueryable

    def get_billing_entry(guid, period_start)
      is_prebuild_template = false

      # try to find the billing entry for the codespace
      billing_entry = find_billing_entry(guid, period_start)

      if billing_entry.nil?

        # try to find the billing entry for the prebuild template
        billing_entry = find_prebuild_template_billing_entry(guid, period_start)
        is_prebuild_template = billing_entry.present?
      end

      [billing_entry, is_prebuild_template]
    end

    private

    def find_billing_entry(guid, period_start)
      entry = Codespaces::BillingEntry.latest_created_before(guid, period_start)
      return entry if entry.present?

      # with brand new codespaces the `period_start` could be before the codespace and its billing
      # entry were created. if we didn't find one above make sure that `period_start` is not before
      # the earliest known billing entry for the codespace with `guid`. If it is, use the first billing entry
      entry = Codespaces::BillingEntry.where(codespace_guid: guid).first
      entry if entry.present? && period_start < entry.created_at
    end

    def find_prebuild_template_billing_entry(guid, period_start)
      # query the prebuild template billing entry db
      entry = Codespaces::PrebuildTemplateBillingEntry.latest_created_before(guid, period_start)
      return entry if entry.present?

      entry = Codespaces::PrebuildTemplateBillingEntry.where(prebuild_template_guid: guid).first
      entry if entry.present? && period_start < entry.created_at
    end
  end
end
