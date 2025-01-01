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
        if target.trade_screening_record.true_match?
          trade_controls_organization_sdn_restricted_notice
        else
          trade_screening_error_data[:message]
        end
      end

      memoize def trade_screening_error_data
        trade_screening_cannot_proceed_error_data(target: target)
      end
    end
  end
end
