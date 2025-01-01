# typed: true
# frozen_string_literal: true

module Copilot
  class TradeScreeningCannotProceedComponent < ApplicationComponent
    include TradeControlsHelper

    # user - the User or Organization who is paying for copilot
    # show_title - Boolean indicating whether the title should be shown; Boolean
    def initialize(user:, show_title: true)
      @user = user
      @show_title = show_title
    end

    private

    attr_reader :user

    def render?
      trade_screening_error_data.present?
    end

    def show_title?
      @show_title
    end

    memoize def trade_screening_error_data
      trade_screening_cannot_proceed_error_data(target: user, check_for_current_user: true, feature_type: :copilot)
    end
  end
end
