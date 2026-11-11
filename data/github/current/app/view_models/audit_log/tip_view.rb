# typed: true
# frozen_string_literal: true

module AuditLog
  class TipView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include TipsHelper

    attr_reader :user

    def tips
      tips = [
        "Exclude events created by you with -actor:#{user.display_login}",
        "Filter events by country with country:US",
        "View all events created yesterday created:#{24.hours.ago.strftime("%Y-%m-%d")}",
      ]

      tips
    end

    def selected_tip
      raise NotImplementedError
    end
  end
end
