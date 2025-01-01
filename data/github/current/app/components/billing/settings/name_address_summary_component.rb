# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    class NameAddressSummaryComponent < ApplicationComponent

      attr_reader :contact, :wrapper_class, :unbold_contact_name_text_style, :is_new_org, :actor, :target

      def initialize(contact:, target:, wrapper_class: nil, unbold_contact_name_text_style: false, is_new_org: false, actor: nil, show_avatar_header: false, short: false)
        @contact = contact
        @wrapper_class = wrapper_class.nil? ? "clearfix pb-3 text-sm-left " : wrapper_class += " clearfix pb-3 text-sm-left "
        @unbold_contact_name_text_style = unbold_contact_name_text_style
        @is_new_org = is_new_org
        @actor = actor
        @target = target
        @show_avatar_header = show_avatar_header
        @short = short
      end

      def contact_owner
        contact.billable_owner
      end

      private

      def render?
        return false if target.delegate_billing_to_business?

        new_org_with_contact = is_new_org && contact.present?
        existing_contact_with_fields = contact&.persisted? && has_filled_contact_fields?
        new_org_with_contact || existing_contact_with_fields
      end

      def show_avatar_header?
        @show_avatar_header
      end

      def short_summary?
        @short || org_account_is_linked_to_another_owner?
      end

      memoize def has_filled_contact_fields?
        contact.fullname.present? ||
        contact.vat_code.present? ||
        contact.address1.present? ||
        contact.address2.present? ||
        contact.city.present? ||
        contact.region.present? ||
        contact.postal_code.present? ||
        contact.country_code.present?
      end

      def org_account_is_linked_to_another_owner?
        return false unless contact&.persisted? && actor.present? && target.present?
        return false unless target.org_is_on_standard_tos?
        return true unless target.has_linked_billing_contact?

        !target.has_linked_billing_contact_to_actor?(actor: actor)
      end
    end
  end
end
