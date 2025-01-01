# typed: true
# frozen_string_literal: true

# Used for upgrading to Pro & Business
module BillingSettings
  class ConfirmationView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

    include UrlHelpers
    include UrlHelper
    include BillingSettingsHelper
    include TradeControlsHelper
    include EnterpriseManagedUsersHelper
    extend Forwardable

    def_delegators :plan_change, \
      :changing_duration?,
      :data_pack_change,
      :new_subscription,
      :price_difference,
      :renewal_list_price,
      :total_seats_price,
      :total_subscription_items_price

    def_delegators :new_subscription,
      :duration,
      :plan

    def_delegators :plan,
      :base_units

    attr_reader :account, :plan_change, :return_to, :actor

    sig { params(logged_in: T::Boolean, source: T.nilable(String)).returns(T::Boolean) }
    def upgrade_to_team_as_link?(logged_in:, source: nil)
      return false unless account.organization?

      !!(logged_in &&
         source == "trial_upgrade" &&
         plan == GitHub::Plan.business_plus &&
         Billing::EnterpriseCloudTrial.new(account).ever_been_in_trial?)
    end

    sig { returns(T::Boolean) }
    def apple_iap_subscription_enabled?
      account.user? && account.apple_iap_subscription?
    end

    def taken_seat_count
      @_taken_seat_count ||= Organization::LicenseAttributer.new(account).unique_count
    end

    def show_seats?
      account.upgrading_from_trial?
    end

    #todo get rid of this method
    def data_collection_enabled?
      account.user? || account.org_is_on_business_tos?
    end

    def show_payment_form?(current_user)
      if data_collection_enabled?
        (target_has_saved_trade_screening_record? && needs_valid_payment_method?) || account.has_valid_payment_method?(check_for_stopgap_restriction: true)
      elsif account.org_is_on_standard_tos?
        # org does not have a saved payment method, and also the billing information was not added by the current viewer
        return false if needs_valid_payment_method? && org_has_screening_record_linked_to_another_owner?(current_user)

        needs_valid_payment_method? || account.has_valid_payment_method?(check_for_stopgap_restriction: true)
      else
        needs_valid_payment_method?
      end
    end

    def show_sdn_blocking_notice?
      feature_type = duration_change_only? ? :billing_cycle_update : :default
      account.has_trade_screening_restriction?(feature_type: feature_type)
    end

    def allowed_to_submit_payment_information_or_upgrade?
      feature_type = duration_change_only? ? :billing_cycle_update : :default
      return false if has_sdn_blocking_restriction?(actor, feature_type: feature_type)

      account.perform_live_sdn_screening(feature_type: feature_type)
    end

    def show_org_upgrade_call_to_action_button?
      return false if cannot_upgrade_seats?

      allowed_to_submit_payment_information_or_upgrade?
    end

    def amount_due_new_style
      "border color-bg-accent color-border-subtle rounded-2 p-3"
    end

    def show_data_collection_form?
      return false unless data_collection_enabled?
      return true if needs_valid_payment_method?
      target_has_saved_trade_screening_record? || account.has_lic_r_stopgap_restriction?
    end

    def show_business_owner_section?(current_user)
      return true if target_has_saved_trade_screening_record? || current_user.has_saved_trade_screening_record?(skip_validation_errors: true)

      !account.has_valid_payment_method?(check_for_stopgap_restriction: true)
    end

    def billing_info_linking_component_wrapper_class(current_user)
      return "" if target_has_saved_trade_screening_record? || current_user.has_saved_trade_screening_record?(skip_validation_errors: true)

      "has-removed-contents"
    end

    def show_org_data_collection_form_switcher?(current_user)
      return false if has_sdn_blocking_restriction?(current_user)
      return true if admin_has_screening_record_but_org_does_not?(current_user)

      !target_has_saved_trade_screening_record?
    end

    def admin_has_screening_record_but_org_does_not?(current_user)
      admin_has_screening_record = current_user.has_saved_trade_screening_record?(skip_validation_errors: true)
      org_has_linked_screening_record = target_has_saved_trade_screening_record?

      !org_has_linked_screening_record && admin_has_screening_record
    end

    def org_has_screening_record_linked_to_another_owner?(current_user)
      !current_user.has_trade_screening_record_linked_to_org?(organization: account) && account.has_linked_trade_screening_record?
    end

    def admin_can_edit_org_screening_record?(current_user)
      return false if has_sdn_blocking_restriction?(current_user, feature_type: :update_info)
      return false unless current_user.has_saved_trade_screening_record?(skip_validation_errors: true)

      current_user.has_trade_screening_record_linked_to_org?(organization: account)
    end

    def has_sdn_blocking_restriction?(current_user, feature_type: :default)
      return true if current_user.has_trade_screening_restriction?(feature_type: feature_type)

      account.has_trade_screening_restriction?(feature_type: feature_type)
    end

    def collect_user_billing_info?
      account.user? && !target_has_saved_trade_screening_record? && needs_valid_payment_method?
    end

    def yearly?
      duration.to_s == User::BillingDependency::YEARLY_PLAN
    end

    def action_text(show_team_as_link: false)
      return "Change how often your #{account.organization? ? "organization" : "account"} is billed" if duration_change_only?

      if account.organization?
        show_team_as_link ? "Buy #{plan_name}" : "Upgrade to #{plan_name}"
      else
        "Upgrade your account from #{old_plan_name} to #{plan_name}"
      end
    end

    def call_to_action_text
      return "Change your #{account.organization? ? "organization's" : "account's"} billing cycle" if duration_change_only?
      return "Upgrade your organization" if account.organization?
      return "Upgrade to GitHub Pro" if account.user?
      "Upgrade your account"
    end

    def duration_options(ignore_duration_change = false)
      if !ignore_duration_change && duration_change_only?
        [duration.to_sym]
      else
        User::BillingDependency::PLAN_DURATIONS.map(&:to_sym)
      end
    end

    def billing_info_linking_action?(current_user)
      return false unless account.org_is_on_standard_tos?
      # org has no linked billing info so admin is linking their own billing information
      admin_has_screening_record_but_org_does_not?(current_user)
    end

    def billing_action_path(current_user)
      return billing_update_path if account.user?

      return org_trade_screening_update_path(account) if duration_change_only?
      org_trade_screening_update_path(account, new_plan: plan)
    end

    def form_method(current_user)
      return :post if account.user?

      :put
    end

    # Public - List price for the new plan.
    # Does not include subscription items
    #
    # Returns Money
    def plan_price(plan: self.plan)
      if yearly?
        Billing::Money.new(plan_yearly_cost_in_cents(plan))
      else
        Billing::Money.new(plan.cost_in_cents)
      end
    end

    # Public - List unit price for the new plan.
    # Does not include subscription items
    #
    # Returns Money
    def plan_unit_price(plan: self.plan)
      if yearly?
        plan_cost_in_cents = account.annual_discount_allowed?(plan: plan, billing_cycle: User::BillingDependency::YEARLY_PLAN) ? plan.yearly_cost_in_cents_with_discount : plan.yearly_cost_in_cents
        Billing::Money.new(plan_cost_in_cents)
      else
        Billing::Money.new(plan.unit_cost_in_cents)
      end
    end

    def pro_plan_price
      plan_price(plan: GitHub::Plan.pro)
    end

    def business_plan_price
      plan_price(plan: GitHub::Plan.business)
    end

    def business_plan_unit_price
      plan_unit_price(plan: GitHub::Plan.business)
    end

    def business_plus_plan_unit_price
      plan_unit_price(plan: GitHub::Plan.business_plus)
    end

    # Public - For displaying price for a duration.
    # Includes subscription items
    #
    # month_or_year - String, 'month' or 'year'
    #
    # Returns Money
    def plan_price_for_duration(month_or_year)
      if month_or_year.to_sym == :year
        plan_change.new_subscription.undiscounted_yearly_price
      else
        plan_change.new_subscription.undiscounted_monthly_price
      end
    end

    def current_plan_cost_per_duration
      return account.plan.yearly_cost if account.yearly_plan?
      account.plan.cost
    end

    def current_plan_unit_cost_per_duration
      return account.plan.yearly_unit_cost if account.yearly_plan?
      account.plan.unit_cost
    end

    def coupon?
      account.has_an_active_coupon? && account.coupon.applicable_to?(plan)
    end

    def coupon_text
      text = "You have an active coupon for #{account.coupon.human_discount} off "
      if account.coupon.duration == 30
        text += "for one month."
      elsif account.coupon.duration < 30
        text += "for #{account.coupon.human_duration}."
      else
        text += "each month for #{account.coupon.human_duration.downcase}."
      end
    end

    # Public - The final discounted price of the plan change being confirmed,
    #          including discount and credit.
    #
    # Returns Money
    def final_price(github_only: false)
      plan_change.final_price(github_only: github_only, use_balance: !account.past_due?)
    end

    def future_balance
      [final_price, Billing::Money.new(0)].min
    end

    # Public - Whether the credit from the old subscription will cover the full cost
    #          of the new subscription (only when there's an amount to be paid before credit).
    #
    #          #payment_amount_without_credit_applied is the price with discount.
    #          #final_price is the price with discount AND credit. Negative when there is a
    #          credit balance after transaction, zero when covered by coupon or credit.
    #
    # Returns Boolean
    def payment_amount_fully_covered_by_credit?
      payment_amount_without_credit_applied.positive? && (final_price.negative? || final_price.zero?)
    end

    # Public - Full credit user would get from this transaction
    #
    # Returns Money
    def credit_for_this_transaction
      plan_change.old_subscription.price_of_remaining_service
    end

    def current_credit
      Billing::Money.new([account.credit, 0].max * 100)
    end

    def next_billed_on
      plan_change.starting_new_subscription? ? account.new_billed_on(GitHub::Billing.today, duration) : account.next_billing_date
    end

    def price_prorated?
      plan_change && account.plan.paid? && plan.paid? && !account.past_due? && effective_immediately?
    end

    def needs_valid_payment_method?
      account.needs_valid_payment_method_to_switch_to_plan?(plan)
    end

    def target_has_saved_trade_screening_record?
      account.has_saved_trade_screening_record?(skip_validation_errors: true)
    end

    # Public - Will the change be applied immediately? (not a pending plan change)
    #
    # Returns Boolean
    def effective_immediately?
      return false if changing_duration?
      price_difference > 0
    end

    # Public - The Price user would pay for the next billing cycle after this change
    # Does not include subscription items
    #
    # Returns Money
    def next_plan_price
      price = if coupon? && !account.will_be_expired?(next_billed_on)
        plan_change.renewal_price(github_only: true)
      else
        renewal_list_price - total_subscription_items_price
      end
      [price + future_balance, Billing::Money.new(0)].max
    end

    # Public - Is the user upgrading to business_plus or not
    # Only returns true if the user was not previously on business_plus
    #
    # Returns Boolean
    def changing_to_business_plus?
      !duration_change_only? && new_subscription.plan.business_plus?
    end

    # Public - number of data packs purchased for this account
    def data_pack_count
      data_pack_change.total_packs
    end

    # Public - the price for each data pack per unit
    #
    # Returns a string
    def human_data_pack_unit_price
      data_pack_change.human_data_pack_unit_price
    end

    # Public - Paid subscription items tied to the account
    #
    #   Rejects any ProductUUID subscription items to avoid counting them
    #   as part of a duration change. Since this view is used when changing duration for a GitHub plan
    #   and Copilot is not tied to the plan's duration, we don't want to account for them here
    #
    # Returns Array of Subscription Items
    def paid_subscription_items
      @paid_subscription_items ||= begin
        sub_items = account.subscription_items
        return [] unless sub_items.any?
        sub_items.active.select(&:paid?).reject(&:subscribable_Billing_ProductUUID?)
      end
    end

    # Public - Is the user upgrading to a plan that has a minimum seat count
    # and their current plan is less than the minimum
    # e.g., Upgrading a free plan with 3 users to a team plan with 5 users
    # (minimum)
    #
    # Returns Boolean
    def using_minimum_seat_count?
      return true if plan.base_units > 1 && plan.base_units == plan_change.seats
    end

    # Public - Billing settings path for the account
    #
    # returns String
    def billing_settings_path
      if account.user?
        settings_user_billing_path
      else
        settings_org_billing_path(account)
      end
    end

    # Public - Is return_to set to create new repository path?
    # Returns true if return_to is a new repository path for an org or user
    #
    # returns Boolean
    def return_to_new_repository?
      return_to == new_org_repository_path(account) ||
      return_to == new_repository_path
    end

    def current_seats
      seats = if account.plan.business?
        account.seats
      else
        account.filled_seats
      end

      pending_seats_change = account.pending_seats_change
      if pending_seats_change && pending_seats_change.seats < seats
        seats = pending_seats_change.seats
      end

      seats
    end

    # Public - Maximum number of seats that can be purchased during a self-serve plan upgrade
    #
    # returns Integer
    def seat_limit_for_upgrades
      account.seat_limit_for_upgrades
    end

    # Public - Returns true when the organization cannot upgrade their plan due to the required seat count
    #          being greater than the allowed number of seats that can be purchased.
    #
    # returns Boolean
    def cannot_upgrade_seats?
      account.organization? && current_seats > seat_limit_for_upgrades
    end

    def duration_change_only?
      plan_change.duration_change_only? && !account.upgrading_from_trial?
    end

    # Public - Returns the use of this view
    # to allow render of some elements in the erb template
    # since it can be called from shared erb templates
    def view_from
      :upgrade
    end

    def show_sales_tax?
      account.display_sales_tax_on_checkout?
    end

    private

    def plan_yearly_cost_in_cents(plan)
      account.annual_discount_allowed?(plan: plan, billing_cycle: ::User::BillingDependency::YEARLY_PLAN) ? plan.yearly_cost_in_cents_with_discount : plan.yearly_cost_in_cents
    end

    # Private: Payment amount for this plan with discount, without credit
    #
    # Returns Money
    def payment_amount_without_credit_applied
      Billing::Money.new(account.payment_amount(plan: plan))
    end

    # Private: The name of the old plan (Free, Pro, etc)
    #
    # Returns String
    def old_plan_name
      branded_plan_name(plan_change.old_subscription.plan)
    end

    # Private: The name of the plan (Free, Pro, etc)
    #
    # Returns String
    def plan_name
      branded_plan_name(plan)
    end
  end
end
