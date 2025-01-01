# typed: true
# frozen_string_literal: true

module Copilot
  class BillingInfoComponent < ApplicationComponent
    include AvatarHelper
    include TradeControlsHelper

    def initialize(user:, payment_duration:, return_to_path:, subscribe_path: nil, payment_success_path: nil, show_contact_info: false, show_header: false, show_footer: true, show_border: false)
      @user = user
      @payment_duration = payment_duration
      @return_to_path = return_to_path
      @subscribe_path = subscribe_path
      @payment_success_path = payment_success_path
      @show_contact_info = show_contact_info
      @show_header = @user.user? || show_header
      @show_footer = show_footer
      @show_border = show_border
    end

    private

    attr_reader :user, :payment_duration, :return_to_path, :payment_success_path, :show_contact_info, :show_header, :show_footer, :show_border

    delegate :billing_contact, :has_commercial_interaction_restriction?, :org_is_on_standard_tos?, :has_saved_billing_information?, to: :user

    def account_type
      if user.organization?
        "Organization"
      elsif user.business?
        "Enterprise"
      else
        "Personal"
      end
    end

    def payment_return_to_path
      return if user.user?

      return_to_path
    end

    def show_linking_billing_information?
      org_is_on_standard_tos?
    end

    def org_has_no_linked_info_but_user_has_saved_info?
      return false unless org_is_on_standard_tos?
      return false if user.has_linked_billing_contact?

      current_user.has_saved_billing_information?
    end

    memoize def hide_name_address_collection_wrapper?
      target_to_use = user.user? ? user : current_user
      return true if target_to_use.has_commercial_interaction_restriction?(feature_type: :copilot)

      has_saved_billing_information?
    end

    def subscribe_path
      @subscribe_path || copilot_signup_subscribe_path
    end
  end
end
