# typed: true
# frozen_string_literal: true

module Stafftools
  module User
    class TradeControlsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      attr_reader :user
      attr_reader :show_billing_info

      def page_title
        "#{user.login} - Trade compliance"
      end

      def plan
        unless GitHub.enterprise?
          user.plan.display_name == "free" ? user.plan.name.humanize : user.plan.display_name.humanize
        end
      end

      def trade_controls_restriction_events
        user.trade_controls_restriction.valid_events_with_subsequent_state
      end

      def trade_controls_restriction_type
        @_trade_controls_restriction_type ||= user.trade_controls_restriction.type
      end
    end
  end
end
