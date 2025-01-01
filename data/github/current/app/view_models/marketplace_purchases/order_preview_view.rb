# typed: true
# frozen_string_literal: true

module MarketplacePurchases
  class OrderPreviewView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include UrlHelpers
    include TradeControlsHelper

    attr_reader :listing, :selected_plan, :account, :quantity, :return_to, :plan_subscription, :plan_subscription_item, :installation_account

    delegate :has_free_trial?, :direct_billing?, :paid?, :per_unit, :name, :unit_name, to: :selected_plan, prefix: true

    def initialize(listing:, selected_plan:, quantity:, account:, installation_account: nil, current_user: nil, user_session: nil, return_to: nil, selected_plan_quantity:)
      @listing = listing
      @selected_plan = selected_plan
      @quantity = quantity
      @current_user = current_user
      @return_to = return_to
      @account = account
      @installation_account = installation_account || account
      @plan_subscription = @account.get_plan_subscription_or_null_plan
      @plan_subscription_item = if @account.business? && @account.self_serve_payment?
        @account.subscription_item_for_marketplace_listing(listing, organization: installation_account)
      else
        @account.subscription_item_for_marketplace_listing(listing)
      end
      @selected_plan_quantity = selected_plan_quantity

      @integration = @listing.listable if @listing.listable_is_integration?
      @listing_installed_for_viewer = logged_in? && @listing.installed_for?(current_user, check_owned_orgs: true)
      @listing_installed_for_target = @listing.installed_for?(@installation_account)
      @viewer_has_purchased = logged_in? && current_user.async_has_purchased_marketplace_listing?(@listing.id).sync
      @viewer_has_organization_subscription_items = logged_in? && current_user.owned_organizations.any? do |org|
        org.subscription_item_for_marketplace_listing(@listing.id)&.adminable_by?(current_user) ||
        (account.business? && account.subscription_item_for_marketplace_listing(@listing.id, organization: org)&.adminable_by?(current_user))
      end
    end

    def show_already_installed_notice?
      return false if @viewer_has_purchased
      return false if @viewer_has_organization_subscription_items

      @listing_installed_for_viewer
    end

    sig { returns(T::Boolean) }
    def show_already_purchased_and_installed_notice?
      current_user.feature_enabled?(:marketplace_purchase_reconciliation) &&
      already_purchased? && !plan_change? && @listing_installed_for_target
    end

    def submit_button_show_billing_modal?
      !account_has_valid_payment_method?
    end

    def account_has_valid_payment_method?
      account.has_valid_payment_method?(check_for_stopgap_restriction: true)
    end

    def submit_button_text
      text = if already_purchased?
        "Issue plan changes"
      else
        "Complete order"
      end

      text += " and begin installation" if !@listing_installed_for_viewer
      text
    end

    def plan_change?
      !current_plan || current_plan.global_relay_id != selected_plan.global_relay_id || plan_subscription_item.quantity != quantity
    end

    def days_left_on_viewer_free_trial
      return @days_left_on_viewer_free_trial if defined? @days_left_on_viewer_free_trial

      @days_left_on_viewer_free_trial = if viewer_has_purchased?
        free_trial_ends_on = current_user.subscription_item_for_marketplace_listing(listing)&.free_trial_ends_on
        free_trial_ends_on.present? ? (free_trial_ends_on - GitHub::Billing.today).to_i : 0
      else
        0
      end
    end

    def viewer_on_free_trial?
      return false unless viewer_has_purchased?
      selected_plan.has_free_trial? && days_left_on_viewer_free_trial.positive?
    end

    def show_pending_cancellation?
      return @show_pending_cancellation if defined? @show_pending_cancellation

      @show_pending_cancellation = account.pending_cycle.
        pending_subscription_item_changes.
        non_free_trial.
        cancellation.
        for_subscribable_listing(listing).
        exists?
    end

    def viewer_has_purchased?
      @viewer_has_purchased
    end

    def invoiced_billing_enabled?
      installation_account.organization? && installation_account.invoiced?
    end

    def business_owner?
      installation_account&.organization? && installation_account&.business&.owner?(current_user)
    end

    def business_owned?
      account.business? || installation_account&.business.present?
    end

    def can_purchase_for_enterprise_owned_self_serve_org?
      enterprise_owned_self_serve_org? && business_owner?
    end

    def enterprise_owned_self_serve_org?
      installation_account&.organization? && installation_account&.business&.self_serve_payment?
    end

    def business_trial?
      installation_account&.organization? && installation_account&.business&.self_serve_payment? && installation_account&.business&.trial?
    end

    def account_name
      account.business? ? account.slug : account.display_login
    end

    def hide_name_address_collection_wrapper?
      return true if business_owned?

      has_saved_billing_info? || account_has_valid_payment_method?
    end

    def has_saved_billing_info?
      return false if business_owned?

      account.has_saved_trade_screening_record?
    end

    def show_billing_info_edit_button?
      return false if business_owned?

      account.is_allowed_to_edit_trade_screening_information?
    end

    def show_payment_form?
      if selected_plan.paid?
        return true if account_has_valid_payment_method?
        return has_saved_billing_info?
      end

      account_has_valid_payment_method?
    end

    def show_linking_billing_information?
      return false if business_owned?

      account.org_is_on_standard_tos?
    end

    def show_order_preview_form?
      return true if business_owned? || invoiced_billing_enabled?

      return false if account.has_commercial_interaction_restriction?
      return account_has_valid_payment_method? if selected_plan.paid?

      has_saved_billing_info? || account_has_valid_payment_method?
    end

    def collect_billing_info?
      return false if business_owned?

      !has_saved_billing_info? && !account_has_valid_payment_method?
    end

    def trade_screening_error_data
      return @trade_screening_error_data if defined?(@trade_screening_error_data)

      @trade_screening_error_data = trade_screening_cannot_proceed_error_data(target: account)
    end

    def form_action_path
      if already_purchased?
        marketplace_order_upgrade_path(listing.slug, plan_id: selected_plan.global_relay_id)
      else
        marketplace_order_purchase_path(listing.slug, plan_id: selected_plan.global_relay_id)
      end
    end

    def plan_change
      return @plan_change if defined? @plan_change

      @plan_change = plan_subscription.plan_change(
        billable_entity: account,
        subscribable: selected_plan,
        subscribable_quantity: @selected_plan_quantity,
      )
    end

    def total_mp_plans_price
      return @total_mp_plans_price if defined? @total_mp_plans_price

      item = plan_change.subscription_item(subscribable: selected_plan)
      @total_mp_plans_price = item.price(trial_price: false)
    end

    def post_trial_prorated_total_price
      return @post_trial_prorated_total_price if defined? @post_trial_prorated_total_price

      @post_trial_prorated_total_price = plan_subscription.post_trial_prorated_total_price(
        listing_plan: selected_plan,
        user: account,
        quantity: @selected_plan_quantity,
      )
    end

    def formatted_prorated_total_price
      prorated_total_price.abs.format
    end

    def prorated_total_price
      plan_change.final_price
    end

    def per_unit_change_price
      return @per_unit_change_price if defined? @per_unit_change_price

      change = plan_subscription.plan_change(billable_entity: account, subscribable: selected_plan)
      item = change.subscription_item(subscribable: selected_plan, quantity: 1)
      @per_unit_change_price = item.price(trial_price: false)
    end

    def update_plan_button_disabled?
      return true if show_oauth_access_checkbox?
      return false if current_user.feature_enabled?(:marketplace_purchase_reconciliation) && !@listing_installed_for_target
      !plan_change?
    end

    def disable_button_for_integration_installation?
      listing.listable_is_integration? && @integration.verified_email_required?(current_user)
    end

    def purchase_plan_button_disabled?
      return true if show_oauth_access_checkbox?
      return true unless can_subscribe_with_current_account?

      already_purchased?
    end

    def selected_plan_can_be_installed?
      return false unless selected_plan.can_be_installed?
      true
    end

    def can_subscribe_with_current_account?
      return false if selected_plan.for_organizations_only? && installation_account.user?
      return false if selected_plan.for_users_only? && installation_account.organization?

      true
    end

    def selected_plan_account_type_text
      return "a personal account" if selected_plan.for_users_only?
      "an organization" if selected_plan.for_organizations_only?
    end

    def show_oauth_access_checkbox?
      installation_account.organization? &&
        installation_account.restricts_oauth_applications? &&
        listing.listable_is_oauth_application? &&
        !installation_account.allows_oauth_application?(listing.listable)
    end

    def current_plan
      plan_subscription_item&.subscribable
    end

    def show_current_plan_price?
      !current_plan.direct_billing?
    end

    def current_plan_description
      description = []
      description << current_plan.name

      if current_plan.per_unit?
        description << "with #{current_plan.unit_name.pluralize(plan_subscription_item.quantity)}"
      end

      if viewer_has_purchased? && days_left_on_viewer_free_trial.positive?
        description << "(Free Trial)"
      end

      description.join(" ")
    end

    def current_plan_formatted_total_price
      return @current_plan_formatted_total_price if defined? @current_plan_formatted_total_price

      @current_plan_formatted_total_price = plan_subscription_item.formatted_total_price
    end

    def show_current_plan?
      already_purchased?
    end

    def already_purchased?
      plan_subscription_item.present?
    end

    def eligible_for_free_trial_on_listing?
      return @eligible_for_free_trial_on_listing if defined? @eligible_for_free_trial_on_listing

      @eligible_for_free_trial_on_listing = plan_subscription.eligible_for_free_trial_on_listing?(listing)
    end

    def eligible_for_free_trial?
      selected_plan.has_free_trial? && eligible_for_free_trial_on_listing?
    end

    def billing_modal_path
      if account.organization?
        return_url = marketplace_order_path(listing_slug: listing.slug, plan_id: selected_plan.global_relay_id, account: account.display_login, quantity: quantity)
        org_payment_modal_path(account.display_login, return_to: return_url)
      else
        return_url = marketplace_order_path(listing_slug: listing.slug, plan_id: selected_plan.global_relay_id, quantity: quantity)
        payment_modal_path(return_to: return_url)
      end
    end

    def formatted_free_trial_end_date
      format_date(account.subscription.free_trial_end_date.to_time(:utc))
    end

    def formatted_day_after_trial_ends
      format_date(account.subscription.free_trial_end_date.to_time(:utc) + 1.day)
    end

    def formatted_post_free_trial_bill_date
      format_date(post_free_trial_bill_date)
    end

    def start_date
      format_date(GitHub::Billing.today)
    end

    def end_date
      format_date(account.subscription.service_ends_on.to_time(:utc))
    end

    def subscription_duration
      plan_subscription.plan_duration
    end

    def post_free_trial_bill_date
      return @post_free_trial_bill_date if defined? @post_free_trial_bill_date

      @post_free_trial_bill_date = account.subscription.next_bill_date_after(date: account.subscription.free_trial_end_date).to_time(:utc)
    end

    private

    # Private: Formats dates for order preview to a consistent format. Example: "Oct 6th"
    def format_date(date)
      date.strftime("%b #{date.day.ordinalize}")
    end

    # Private: Allows the url helpers to work within ViewModel
    def default_url_options
      { host: GitHub.host_name }
    end
  end
end
