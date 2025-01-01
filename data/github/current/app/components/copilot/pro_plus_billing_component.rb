# typed: true
# frozen_string_literal: true

module Copilot
  class ProPlusBillingComponent < ApplicationComponent
    def initialize(user:, payment_duration:, premium_requests: nil, return_to_path:, update_path: nil, tracking_params: nil)
      @user = user.user? ? user : current_user
      @payment_duration = payment_duration
      @premium_requests = premium_requests
      @return_to_path = return_to_path
      @update_path = update_path
      @tracking_params = tracking_params
    end

    attr_reader :user, :payment_duration, :premium_requests, :return_to_path, :tracking_params

    def copilot_user
      Copilot::User.new(user)
    end

    def update_path
      return @update_path if @update_path

      copilot_pro_plus_signup_update_path
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

    def premium_requests?
      return false unless premium_requests_feature_enabled?
      return false unless premium_requests.present?

      premium_requests == "disabled" || premium_requests == "enabled"
    end

    def premium_requests_enabled?
      premium_requests == "enabled"
    end

    def show_billing_information_container?
      if premium_requests_feature_enabled?
        payment_duration? && premium_requests?
      else
        payment_duration?
      end
    end

    def show_payment_method_container?
      return false unless GitHub.billing_enabled?
      return false unless logged_in?
      return false if has_billing_info_validation_error?
      return false if has_commercial_restrictions?

      if premium_requests_feature_enabled?
        payment_duration? && premium_requests? && has_billing_information?
      else
        payment_duration? && has_billing_information?
      end
    end

    def premium_requests_feature_enabled?
      FeatureFlag.vexi.enabled?(:copilot_pro_plus_premium_requests, current_user, default: false)
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
