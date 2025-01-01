# typed: true
# frozen_string_literal: true

module Copilot
  class ProPlusBillingComponent < ApplicationComponent
    def initialize(user:, payment_duration:, return_to_path:, tracking_params: nil)
      @user = user.user? ? user : current_user
      @payment_duration = payment_duration
      @return_to_path = return_to_path
      @tracking_params = tracking_params
    end

    attr_reader :user, :payment_duration, :return_to_path, :tracking_params

    def billing_information
      user.trade_screening_record
    end

    def has_billing_information?
      user.has_saved_trade_screening_record?
    end

    def hide_billing_information_form?
      has_commercial_restrictions? || has_billing_information?
    end

    def show_payment_method_container?
      return false unless GitHub.billing_enabled?
      return false unless logged_in?
      return false if has_commercial_restrictions?

      has_billing_information?
    end

    private

    memoize def has_commercial_restrictions?
      user.has_commercial_interaction_restriction?(feature_type: :copilot)
    end
  end
end
