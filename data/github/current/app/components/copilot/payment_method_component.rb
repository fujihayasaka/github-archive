# typed: true
# frozen_string_literal: true

module Copilot
  class PaymentMethodComponent < ApplicationComponent
    def initialize(user:, payment_duration:, return_to_path: nil, subscribe_path: nil, success_path: nil, show_contact_info: false, show_footer: true, show_border: false)
      @user = user
      @payment_duration = payment_duration
      @return_to_path = return_to_path
      @subscribe_path = subscribe_path
      @success_path = success_path
      @show_contact_info = show_contact_info
      @show_footer = show_footer
      @show_border = show_border
    end

    private

    attr_reader :user, :payment_duration, :return_to_path, :success_path, :show_contact_info, :show_footer, :show_border

    delegate :payment_method, to: :user

    def render?
      return false unless GitHub.billing_enabled?
      return false unless logged_in?
      return false if has_commercial_interaction_restriction?
      return false if has_linked_billing_contact_for_other_admin_but_no_payment_method?

      user.has_saved_billing_information?
    end

    memoize def has_commercial_interaction_restriction?
      if user.user?
        return user.has_commercial_interaction_restriction?(feature_type: :copilot)
      end

      user.has_commercial_interaction_restriction?(feature_type: :copilot) || T.must(current_user).has_commercial_interaction_restriction?(feature_type: :copilot)
    end

    memoize def has_linked_billing_contact?
      return false unless user.organization?
      user.has_linked_billing_contact?
    end

    memoize def linked_billing_contact_belongs_to_current_user?
      return false unless user.organization?
      user.has_linked_billing_contact_to_actor?(actor: current_user)
    end

    memoize def has_linked_billing_contact_for_other_admin_but_no_payment_method?
      return false unless has_linked_billing_contact?
      return false if linked_billing_contact_belongs_to_current_user?
      return false if has_valid_payment_method?

      true
    end

    def credit_card_last_four
      return unless payment_method.last_four.present?
      "ending #{payment_method.last_four}"
    end

    def credit_card_expiration
      exp_date = payment_method.expiration_date
      return "" unless exp_date
      exp_date.strftime("%-m/%Y")
    end

    def account_type
      if user.organization?
        "Organization"
      elsif user.business?
        "Enterprise"
      else
        "Personal"
      end
    end

    memoize def has_valid_payment_method?
      user.has_valid_payment_method?
    end

    def subscribe_path
      @subscribe_path || copilot_signup_subscribe_path
    end
  end
end
