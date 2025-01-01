# typed: true
# frozen_string_literal: true
module Billing
  module Settings
    class NameAddressSummaryComponent < ApplicationComponent

      attr_reader :profile, :wrapper_class, :unbold_profile_name_text_style, :is_new_org, :actor, :target

      def initialize(profile:, wrapper_class: nil, unbold_profile_name_text_style: false, is_new_org: false, actor: nil, target: nil, show_avatar_header: false, short: false)
        @profile = profile
        @wrapper_class = wrapper_class.nil? ? "clearfix pb-3 text-sm-left " : wrapper_class += " clearfix pb-3 text-sm-left "
        @unbold_profile_name_text_style = unbold_profile_name_text_style
        @is_new_org = is_new_org
        @actor = actor
        @target = target
        @show_avatar_header = show_avatar_header
        @short = short
      end

      def profile_owner
        profile.owner
      end

      private

      def render?
        new_org_with_profile = is_new_org && profile.present?
        existing_profile_with_fields = profile&.persisted? && has_filled_profile_fields?
        new_org_with_profile || existing_profile_with_fields
      end

      def show_avatar_header?
        @show_avatar_header
      end

      def short_summary?
        @short || org_account_is_linked_to_another_owner?
      end

      memoize def has_filled_profile_fields?
        profile.fullname.present? ||
        profile.vat_code.present? ||
        profile.address1.present? ||
        profile.address2.present? ||
        profile.city.present? ||
        profile.region.present? ||
        profile.postal_code.present? ||
        profile.country_code.present?
      end

      def org_account_is_linked_to_another_owner?
        return false unless profile&.persisted? && actor.present? && target.present?
        return false unless target.org_is_on_standard_tos?
        return true unless target.has_linked_trade_screening_record?

        !actor.has_trade_screening_record_linked_to_org?(organization: target)
      end
    end
  end
end
