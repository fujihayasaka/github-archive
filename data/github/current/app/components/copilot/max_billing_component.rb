# typed: true
# frozen_string_literal: true

module Copilot
  class MaxBillingComponent < ApplicationComponent
    def initialize(user:, payment_duration:, return_to_path:, update_path: nil, tracking_params: nil)
      @user = user.user? ? user : current_user
      @payment_duration = payment_duration
      @return_to_path = return_to_path
      @update_path = update_path
      @tracking_params = tracking_params
    end

    attr_reader :user, :payment_duration, :return_to_path, :tracking_params

    def copilot_user
      Copilot::User.new(user)
    end

    def update_path
      return @update_path if @update_path

      copilot_pro_signup_update_path
    end

    def billing_information
      user.billing_contact
    end

    def has_billing_information?
      user.has_saved_billing_information?
    end

    def hide_billing_information_form?
      has_commercial_restrictions? || billing_info_exists_without_errors?
    end

    def payment_duration?
      return false unless payment_duration.present?

      payment_duration == "monthly" || payment_duration == "yearly"
    end

    def show_billing_information_container?
      payment_duration?
    end

    def show_payment_method_container?
      return false unless GitHub.billing_enabled?
      return false unless logged_in?
      return false if has_billing_info_validation_error?
      return false if has_commercial_restrictions?

      payment_duration? && has_billing_information?
    end

    memoize def billing_info_exists_without_errors?
      helpers.billing_info_exists_without_errors?(user)
    end

    memoize def has_billing_info_validation_error?
      helpers.has_billing_info_validation_error?(user)
    end

    private

    memoize def has_commercial_restrictions?
      user.has_commercial_interaction_restriction?(feature_type: :copilot)
    end
  end
end
