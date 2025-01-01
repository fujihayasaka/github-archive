# typed: true
# frozen_string_literal: true

module Coupons
  class ShowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

    attr_reader :coupon, :selected_account, :plan, :current_user

    def discount_amount
      interval = coupon.discount > 1 ? " per month" : ""
      text = "#{coupon.human_discount}#{interval} off"
      text
    end

    def discount_duration
      coupon.human_duration
    end

    # Returns the most sensible user login for a given coupon.
    #
    # user   - User that is redeeming the coupon
    # coupon - Da Coupon
    #
    # Returns a user id as a String
    def default_user_login(user, coupon)
      coupon.user_only? ? user.display_login : ""
    end

    # Returns the most sensible plan for a given coupon.
    #
    # user   - User that is redeeming the coupon
    # coupon - Da Coupon
    #
    # Returns the plan name String
    def default_plan(user, coupon)
      coupon.plan? ? coupon.plan.name : GitHub.default_plan_name
    end

    def redeem_button_disabled
      "disabled" if !coupon.user_only? || !coupon.plan?
    end

    def account_selected(account)
      "selected" if selected_account == account
    end

    def account
      selected_account.presence || current_user
    end

    def org_has_no_linked_info_but_user_has_saved_info?
      return false unless account.org_is_on_standard_tos?
      return false if account.has_linked_trade_screening_record?

      current_user.has_saved_trade_screening_record?
    end

    def linked_trade_screening_record_belongs_to_current_user?
      current_user.has_trade_screening_record_linked_to_org?(organization: account)
    end

    def has_valid_payment_method?
      account.has_valid_payment_method?(check_for_stopgap_restriction: true)
    end

    def has_linked_trade_screening_record_for_other_admin_but_no_payment_method?
      return false unless account.has_linked_trade_screening_record?
      return false if linked_trade_screening_record_belongs_to_current_user?

      !has_valid_payment_method?
    end

    def show_billing_info_edit_button?
      return false unless account.present?
      return false if account.org_is_on_standard_tos?

      account.is_allowed_to_edit_trade_screening_information?
    end

    def account_type
      if account.is_a?(Business)
        "Enterprise"
      elsif account.user?
        "Personal"
      else
        "Organization"
      end
    end

    def payment_method_required?
      return @payment_method_required if defined?(@payment_method_required)
      return false unless account.present? && account.has_saved_trade_screening_record?

      pricing_plan = begin
        # A payment method is required for a business if the balance exceeds the discounts from the annual plan and coupon
        if account.business?
          subscription_items_to_transfer = account.upgrade_initiated_from_organization&.subscription_items.to_a
          Billing::Pricing.new(
            account: account,
            plan: GitHub::Plan.business_plus,
            plan_duration: account.plan_duration,
            plan_annual_discount: account.yearly_plan?,
            seats: account.default_seats,
            coupon: coupon,
            subscription_items: subscription_items_to_transfer,
          )
        else
          Billing::Pricing.new(
            plan: plan,
            seats: account.default_seats,
            discount: coupon&.discount,
            plan_duration: User::BillingDependency::MONTHLY_PLAN,
          )
        end
      end

      @payment_method_required = if pricing_plan.discounted.zero? || has_valid_payment_method?
        false
      else
        true
      end
    end

    def show_payment_form?
      return false if has_linked_trade_screening_record_for_other_admin_but_no_payment_method?

      # we also want to show the payment method summary if account has a valid payment method
      has_billing_info_and_payment_method = account.has_saved_trade_screening_record? && has_valid_payment_method?
      if payment_method_required? || has_billing_info_and_payment_method
        true
      else
        false
      end
    end

    def show_redemption_button?
      has_saved_screening_record = account.present? && account.has_saved_trade_screening_record?
      has_saved_screening_record && !account.has_commercial_interaction_restriction? && !payment_method_required?
    end

    def trade_screening_record

      return nil unless account.present? && account.has_saved_trade_screening_record?

      account.trade_screening_record
    end

    def hide_name_address_collection_wrapper?
      return true unless account.present?

      account.has_saved_trade_screening_record?
    end

    # Checks if we should show the "Create new enterprise" button in the account switcher dropdown
    #
    # Returns Boolean
    def show_create_enterprise_account_from_coupon_button?
      eligible_accounts = coupon.eligible_self_serve_enterprise_accounts(current_user)
      return false if eligible_accounts.empty?
      # We don't want to show the button if the user has EAs in the process of being created from a coupon
      eligible_accounts.select(&:creation_initiated_from_coupon?).none?
    end
  end
end
