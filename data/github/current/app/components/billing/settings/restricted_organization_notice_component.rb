# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    class RestrictedOrganizationNoticeComponent < ApplicationComponent
      include TradeControlsHelper
      include GitHub::Memoizer
      attr_reader :target, :header_view, :selected_nav_item

      def initialize(target:, header_view: nil, selected_nav_item: nil)
        @target = target
        @header_view = header_view
        @selected_nav_item = selected_nav_item
      end

      def show_nav_header?
        target.organization? && header_view.present? && selected_nav_item.present?
      end

      def notice_title
        "We are unable to provide this feature"
      end

      def notice_body
        if target.trade_compliance_true_match_restricted?
          trade_controls_organization_sdn_restricted_notice
        else
          sdn_restriction_notice
        end
      end

      memoize def sdn_restriction_notice
        trade_screening_restriction_notice(target: target)
      end
    end
  end
end
