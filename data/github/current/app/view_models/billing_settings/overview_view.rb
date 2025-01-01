# typed: true
# frozen_string_literal: true

module BillingSettings
  class OverviewView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include PlanHelper
    include MoneyHelper
    include ActionView::Helpers::NumberHelper
    include BillingSettingsHelper
    include CodespacesHelper
    include GitHub::ResilienceMixin
    include BillingContactHelper
    include TradeControlsHelper
    include GitHub::Memoizer
    include EnterpriseManagedUsersHelper

    MUNICH_ACTIONS_MINUTES_CHANGE_DATE = GitHub::Billing.timezone.parse("2020-05-14").to_date
    MUNICH_ACTIONS_MINUTES_TRANSITION_END_DATE = MUNICH_ACTIONS_MINUTES_CHANGE_DATE + 1.month

    include UrlHelpers
    attr_reader :account, :current_user

    delegate :subscription, :pending_cycle, :alternative_plan_duration, :change_billing_duration_message, :plan,
      to: :account

    def manual_bill_pay_path
      if account.organization?
        org_bill_pay_new_path(organization_id: account.display_login)
      else
        bill_pay_new_path
      end
    end

    def manual_payment_due_date
      account.manual_payment_due_date
    end

    def pricing
      @pricing ||= ::Billing::Pricing.new(account: account)
    end

    def is_organization?
      account.organization?
    end

    def is_billing_platform_user?
      account.user? && account.customer&.billed_via_billing_platform?
    end

    def is_billing_platform_organization?
      account.organization? && account.customer&.billed_via_billing_platform?
    end

    def organization_login
      account.display_login
    end

    memoize def account_plan_subscription
      if enterprise_owned_self_serve_org?
        account.business.get_plan_subscription_or_null_plan
      else
        account.get_plan_subscription_or_null_plan
      end
    end

    def copilot_user
      @copilot_user ||= ::Copilot::User.new(account)
    end

    def qualifies_for_free_copilot_usage?
      return @qualifies_for_free_copilot_usage if defined?(@qualifies_for_free_copilot_usage)

      @qualifies_for_free_copilot_usage = copilot_user.has_free_access? && !account_has_screening_restriction?(feature_type: :copilot)
    end

    def eligible_for_copilot_free_trial?
      return @eligible_for_copilot_free_trial if defined?(@eligible_for_copilot_free_trial)

      @eligible_for_copilot_free_trial =
        case
        when account_has_screening_restriction?(feature_type: :copilot) then false
        when qualifies_for_free_copilot_usage? then false
        when copilot_user.is_technical_preview_user? then false
        else
          Billing::Public::SubscriptionItem.eligible_for_free_trial?(
            product: copilot_user.copilot_pro_product_identifier,
            account: account,
          )
        end
    end

    def eligible_for_legacy_upsell?
      account.organization? && account.eligible_for_legacy_upsell?
    end

    sig { returns(T.nilable(Billing::Public::SubscriptionItem)) }
    def copilot_subscription_item
      copilot_type_product_identifier = Billing::Public::Product::ProductIdentifier.new(product_type: Billing::ProductUUID::COPILOT_PRODUCT_TYPE)
      Billing::Public::SubscriptionItem.all_active(account: account, product: copilot_type_product_identifier).value { [] }.first
    end

    sig { returns(T::Array[Billing::SubscriptionItem]) }
    memoize def marketplace_items
      scope = account_plan_subscription.active_marketplace_listing_subscription_items
        .includes(subscribable: :marketplace_listing_plan, marketplace_listing_plan: :listing)

      if enterprise_owned_self_serve_org?
        scope.where(organization_id: account.id)
      else
        scope
      end.to_a
    end

    def next_charge_date
      return @next_charge_date if defined?(@next_charge_date)

      next_charge = next_charges_due.first
      return unless next_charge

      @next_charge_date = next_charge.renewal_date
    end

    def next_charges_due
      return @next_charges_due if defined?(@next_charges_due)

      next_due_date = recurring_charge_item_list.sort_by(&:renewal_date).first&.renewal_date
      return [] unless next_due_date

      @next_charges_due = recurring_charge_item_list.select { |summary| summary.renewal_date == next_due_date }
    end

    def next_payment_amount
      recurring_amount = next_charges_due.sum(Billing::Money.zero, &:renewal_amount)

      if next_charges_due.any?(&:discountable)
        recurring_amount -= pending_cycle.discount
      end

      recurring_amount
    end

    def billing_vnext_docs_url
      "#{GitHub.help_url}/billing/using-the-new-billing-platform"
    end

    def discountable_charges
      return @discountable_charges if defined?(@discountable_charges)

      @discountable_charges = recurring_charge_item_list.select(&:discountable)
    end

    def recurring_charge_item_list
      @recurring_charge_item_list ||= [
        github_plan_charge_summary,
        github_copilot_charge_summary,
        github_marketplace_charge_summary,
        github_lfs_charge_summary,
        github_sponsors_charge_summary,
      ].compact
    end

    class ChargeSummary < T::Struct
      const :display_name, String
      const :renewal_date, Date
      const :renewal_amount, Billing::Money
      const :billing_interval, String
      const :discountable, T::Boolean
    end

    class CouponSummary < T::Struct
      const :display_name, String
      const :expiration_date, Date
      const :billing_interval, String
      const :human_discount, String
      const :human_expiration, String
    end

    def coupon_summary
      return @_coupon_summary if defined?(@_coupon_summary)
      return unless account_has_coupon?

      coupon = account.coupon
      redemption = account.coupon_redemption
      pending_cycle = account.pending_cycle

      human_expiration =
        if coupon.will_expire?
          "Expires #{redemption.expires_at.to_date.strftime("%b %d, %Y")}"
        else
          "No expiration"
        end

      human_discount =
        if coupon.percentage?
          "#{(coupon.discount * 100).to_i}%"
        else
          "$%.02f" % (coupon.discount * account.plan_duration_in_months)
        end

      @_coupon_summary = CouponSummary.new(
        display_name: "GitHub Coupon",
        expiration_date: redemption.expires_at.to_date,
        billing_interval: pending_cycle.billing_interval,
        human_discount: human_discount,
        human_expiration: human_expiration
      )
    end

    def github_plan_charge_summary
      pending_cycle = account.pending_cycle

      plan = pending_cycle.plan
      return if plan.free? || plan.free_with_addons?

      ChargeSummary.new(
        display_name: "GitHub #{plan.titleized_display_name}",
        renewal_date: account.github_plan_next_billing_date,
        renewal_amount: pending_cycle.plan_cost,
        billing_interval: pending_cycle.billing_interval,
        discountable: true
      )
    end

    def github_copilot_charge_summary
      subscription = copilot_subscription_item
      return unless subscription

      display_name = subscription.name
      renewal_amount = subscription.price
      billing_interval = subscription.interval.to_s

      change = Billing::PendingSubscriptionItemChange.find_by(
        id: subscription.pending_product_change_id
      )
      if change
        return if change.cancellation?

        renewal_amount = change.subscribable_base_price
        billing_interval = change.new_billing_cycle
      end

      ChargeSummary.new(
        display_name: display_name,
        renewal_date: subscription.next_billing_date,
        renewal_amount: renewal_amount,
        billing_interval: billing_interval,
        discountable: false
      )
    end

    sig { returns(T.nilable(ChargeSummary)) }
    def github_marketplace_charge_summary
      recurring_items = marketplace_items.select(&:next_billing_date)
      return unless recurring_items.any?

      pending_cycle = account.pending_cycle
      renewal_amount = pending_cycle.marketplace_items_cost
      return if renewal_amount.zero?

      ChargeSummary.new(
        display_name: "GitHub Marketplace",
        renewal_date: T.must(recurring_items.first).next_billing_date,
        renewal_amount: renewal_amount,
        billing_interval: pending_cycle.billing_interval,
        discountable: false
      )
    end

    def github_lfs_charge_summary
      pending_cycle = account.pending_cycle
      return if pending_cycle.data_packs.zero?

      billing_interval = pending_cycle.billing_interval
      renewal_amount = pending_cycle.data_pack_cost
      return if renewal_amount.zero?

      ChargeSummary.new(
        display_name: "GitHub LFS",
        renewal_date: account.next_billing_date,
        renewal_amount: renewal_amount,
        billing_interval: billing_interval,
        discountable: true
      )
    end

    def github_sponsors_charge_summary
      active_sponsorships = account
        .sponsors_and_general_plan_subscription_items
        .active
        .to_a
        .select(&:recurring_sponsorship?)

      return unless active_sponsorships.present?
      pending_cycle = account.pending_cycle

      renewal_amount = pending_cycle.recurring_sponsorable_item_cost
      return if renewal_amount.zero?

      ChargeSummary.new(
        display_name: "GitHub Sponsors",
        renewal_date: account.next_sponsors_billing_date,
        renewal_amount: renewal_amount,
        billing_interval: pending_cycle.billing_interval,
        discountable: false
      )
    end

    def show_expired_cloud_trial?(target)
      return false unless target.plan.name != GitHub::Plan::BUSINESS_PLUS
      trial = Billing::PlanTrial.find_by(user: target, plan: GitHub::Plan::BUSINESS_PLUS)

      trial.present? && trial.expired_within?(Billing::EnterpriseCloudTrial::EXPIRATION_MESSAGE_DURATION)
    end

    def show_invoice_overview?
      account.organization? && account.invoiced? && invoice.present?
    end

    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def payment_method
      @payment_method ||= if account_has_valid_payment_method?
        account.payment_method
      end
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    def account_eligible_for_budget_management?
      (account.organization? && account.invoiced?) || account_has_valid_payment_method?
    end

    def account_has_coupon?
      account.coupon.present?
    end

    def org_is_on_per_seat?
      account.plan.per_seat?
    end

    def enterprise_owned_self_serve_org?
      account.organization? && account.business&.self_serve_payment?
    end

    def change_duration_path
      if account.user?
        upgrade_path(plan_duration: alternative_plan_duration, plan: account.plan)
      elsif !account.plan.per_repository?
        upgrade_path(org: account, target: "organization", plan_duration: alternative_plan_duration,
          plan: account.plan)
      end
    end

    def user_billing_information
      account.billing_contact
    end

    memoize def zuora_maintenance_enabled?
      account.feature_enabled?(:zuora_maintenance)
    end

    def is_pending_cycle_changing_seats?
      pending_cycle = account.pending_cycle
      pending_cycle.plan.per_seat? && pending_cycle.seats && pending_cycle.seats > 0
    end

    def account_has_screening_restriction?(feature_type: :default)
      return false unless account.live_sdn_screening_enabled?

      account_restricted = account.has_commercial_interaction_restriction?(feature_type: feature_type)
      if account.organization?
        return current_user.has_commercial_interaction_restriction?(feature_type: feature_type) || account_restricted
      end

      account_restricted
    end

    def allowed_to_update_spending_limit?
      !account_has_screening_restriction?(feature_type: :cost_management) && account_eligible_for_budget_management?
    end

    def show_billing_extras?
      return false if account.feature_enabled?(:hide_billing_extras)
      account.customer.present?
    end

    def show_sales_tax_box?
      account.is_a?(Organization) && account.customer&.in_taxable_country_with_exemptions?
    end

    def has_billing_extra?
      account.billing_extra.present?
    end

    def has_vat_code?
      account.vat_code.present?
    end

    def last_payment_date
      account.billing_transactions.sales.last&.created_at.to_date
    end

    def last_payment_amount
      if last_sale = account.billing_transactions.sales.last
        last_transaction_amount = if last_sale.was_refunded?
          -last_sale.refund.amount_in_cents
        else
          last_sale.amount_in_cents
        end

        last_transaction_amount / 100.to_f
      end
    end

    def last_payment_status
      if account.billing_transactions.sales.last
        t = account.billing_transactions.sales.last

        if t.voided? || t.was_refunded? || t.charged_back?
          "refunded"
        elsif t.success?
          "successful"
        else
          "failed"
        end
      end
    end

    def repo_usage
      account.plan.repos - account.owned_private_repositories.count
    end

    def repo_usage_percentage
      if account.owned_private_repositories.count == 0
        0
      elsif account.owned_private_repositories.count > account.plan.repos
        100
      else
        (account.owned_private_repositories.count / account.plan.repos.to_f * 100).round 1
      end
    end

    def compare_plans_link
      account.organization? ? settings_org_plans_path(account) : settings_user_plans_path
    end

    def show_marketplace?
      GitHub.marketplace_enabled? && marketplace_items.any?
    end

    def show_sponsors?
      GitHub.sponsors_enabled? && (account.business.blank? || account.sponsors_invoiced?)
    end

    def show_asset_usage?
      account.data_packs > 0 || account.asset_status.try(:used?)
    end

    def show_per_seat_callout?
      !account.invoiced? &&
      account.org_free_plan?
    end

    def show_business_plus_callout?
      account.organization? &&
      !account.invoiced? &&
      !account.plan.business_plus? &&
      !show_per_seat_callout?
    end

    def payment_needs_update?
      account.billing_trouble? || account.card_expired?
    end

    def upsell_message_next
      if pro_upgrade?
        "Get private unlimited repositories"
      elsif team_upgrade?
        "Get private repositories and team permissions"
      elsif business_upgrade?
        "Get SAML single-sign-on, 24/5 support, 99.95% Uptime SLA, and more..."
      end
    end

    def pro_upgrade?
      account.can_change_plan_to?(GitHub::Plan.pro)
    end

    alias team_upgrade? show_per_seat_callout?
    alias business_upgrade? show_business_plus_callout?

    def account_can_upgrade?
      return false if account.archived?
      return true if pro_upgrade?
      return true if team_upgrade?
      return true if business_upgrade?
      false
    end

    def plan_pending_change_indicator
      pending_cycle = account.pending_cycle
      plan_changing = pending_cycle.changing_plan?
      seats_changing = pending_cycle.changing_seats?
      duration_changing = pending_cycle.changing_duration?
      multiple_changes = [plan_changing, seats_changing, duration_changing].count(true) > 1

      if multiple_changes
        "changes pending"
      elsif plan_changing
        "downgrade pending"
      elsif duration_changing
        "duration change pending"
      elsif seats_changing
        "seats change pending"
      end
    end

    def show_lfs_downgrade?
      return false if account.data_packs.zero?

      show_lfs_upgrade?
    end

    def show_lfs_upgrade?
      return false if account.in_a_sales_managed_business?
      return false if account.invoiced? && !account.business
      true
    end

    def lfs_bandwidth_breakdown_path
      account.organization? ? settings_orgs_lfs_bandwidth_breakdown_path(account) : settings_lfs_bandwidth_breakdown_path
    end

    def lfs_storage_breakdown_path
      account.organization? ? settings_orgs_lfs_storage_breakdown_path(account) : settings_lfs_storage_breakdown_path
    end

    def payment_method_action_allowed?
      !account.invoiced? && !account.has_any_trade_restrictions?
    end

    def can_update_payment_method?
      return false unless payment_method_action_allowed?
      return true unless account.org_is_on_standard_tos?

      user_owns_org_billing_info = account.has_linked_billing_contact_to_actor?(actor: current_user)
      return true if !payment_method.present? && user_owns_org_billing_info && has_saved_billing_information?

      user_owns_org_billing_info
    end

    def can_remove_payment_method?
      return false unless payment_method.present?

      account.no_upcoming_charges?
    end

    def update_payment_method_path
      payment_information_path
    end

    def invoices
      @_invoices ||= fetch_invoices
    end

    def invoice
      @_invoice ||= invoices.last
    end

    def spending_limit_enabled?
      Billing::Budget.configurable?(account)
    end

    def metered_billing_enabled?
      actions_enabled? || packages_enabled?
    end
    alias_method :shared_storage_enabled?, :metered_billing_enabled?

    def actions_enabled?
      account.plan_metered_billing_eligible?
    end

    def packages_enabled?
      account.plan_metered_billing_eligible?
    end

    def metered_billing_overage_allowed?
      account.metered_billing_overage_allowed?
    end

    def advanced_security_purchased?
      account.advanced_security_purchased?
    end

    def copilot_for_business_enabled?
      Copilot.copilot_object(account).copilot_for_business_enabled? &&
        account.plan.copilot_for_biz_eligible?
    end

    def show_copilot_for_business_card?
      with_database_error_fallback(fallback: false) do
        return false unless account.organization?

        copilot_organization = Copilot::Organization.new(account)
        copilot_organization.has_copilot_for_business? || (copilot_organization.business_trial && T.must(copilot_organization.business_trial).show_status_notification?)
      end
    end

    def show_buy_copilot_for_business_card?
      account.organization? && !show_copilot_for_business_card?
    end

    class NavigationTab
      attr_reader :name, :path, :visible

      def initialize(name:, path:, visible: true)
        @name = name
        @path = path
        @visible = visible
      end

      def visible?
        visible
      end

      def to_h
        { name: name, path: path, visible: visible }
      end
    end

    def navigation_tabs
      if account.organization?
        tabs = [
          NavigationTab.new(name: "Subscriptions", path: settings_org_billing_path(organization_id: account.display_login)),
          NavigationTab.new(name: "Spending Limit", path: settings_org_billing_tab_path(organization_id: account.display_login, tab: "spending_limit"), visible: spending_limit_enabled?),
          NavigationTab.new(name: "Payment Information", path: settings_org_billing_tab_path(organization_id: account.display_login, tab: "payment_information")),
          NavigationTab.new(name: "Past Invoices", path: settings_org_billing_tab_path(organization_id: account.display_login, tab: "past_invoices"), visible: show_past_invoices?)
        ]
      else
        tabs = [
          NavigationTab.new(name: "Subscriptions", path: settings_user_billing_path),
          NavigationTab.new(name: "Spending Limit", path: settings_user_billing_tab_path(tab: "spending_limit"), visible: spending_limit_enabled?),
          NavigationTab.new(name: "Payment Information", path: settings_user_billing_tab_path(tab: "payment_information"))
        ]
      end

      tabs.select(&:visible?).map(&:to_h)
    end

    def days_to_next_billing_date
      days_to_date(account.next_billing_date.to_date)
    end

    def days_to_next_metered_billing_date
      days_to_time(account.next_metered_billing_cycle_starts_at)
    end

    def days_to_next_lfs_reset_date
      lfs_days_remaining = account.days_remaining_in_lfs_cycle
      if lfs_days_remaining
        pluralize_days_for_display(lfs_days_remaining)
      else
        days_to_next_billing_date
      end
    end

    def days_to_date(date)
      days = (date - GitHub::Billing.timezone.now.to_date).to_i
      pluralize_days_for_display(days)
    end

    def days_to_time(time)
      days = ((time - GitHub::Billing.timezone.now) / 1.day).to_i
      pluralize_days_for_display(days)
    end

    def pluralize_days_for_display(days)
      "#{days} #{"day".pluralize(days)}"
    end

    def next_billing_date_after_munich_limits_change
      if account.next_billing_date.to_date > MUNICH_ACTIONS_MINUTES_TRANSITION_END_DATE
        MUNICH_ACTIONS_MINUTES_TRANSITION_END_DATE
      else
        find_next_billing_date(
          starting_with: account.next_billing_date.to_date,
          after: MUNICH_ACTIONS_MINUTES_CHANGE_DATE
        )
      end
    end

    def find_next_billing_date(starting_with:, after:)
      if starting_with >= after
        starting_with
      else
        find_next_billing_date(
          starting_with: starting_with + 1.month,
          after: after
        )
      end
    end

    def munich_actions_minutes_change_date
      MUNICH_ACTIONS_MINUTES_CHANGE_DATE
    end

    def munich_announcement_url
      "#{GitHub.blog_url}/2020-04-14-github-is-now-free-for-teams/"
    end

    def github_usage_edit_options
      options = []

      if !account.invoiced?
        if account.plan.per_repository?
          options.push("edit-plan")
        end

        if org_is_on_per_seat?
          options.push("seats-add")
          options.push("seats-remove") if account.has_downgradable_seats?
          if account.customer&.billed_via_billing_platform?
            options.push("seats-switch-monthly") if account.plan_duration.downcase == "year"
            options.push("seats-switch-yearly") if account.plan_duration.downcase == "month"
          end
          options.push("seats-details")
          options.push("divider")
        end

        unless account.org_free_plan? || account.personal_plan? || account.plan.per_repository?
          if plan.business_plus?
            options.push("plan-business-plus")
          elsif plan.business?
            options.push("plan-business")
          elsif plan.pro?
            if account.customer&.billed_via_billing_platform?
              options.push("seats-switch-monthly") if account.plan_duration.downcase == "year"
              options.push("seats-switch-yearly") if account.plan_duration.downcase == "month"
            end
            options.push("plan-pro")
          end
        end
      end

      options
    end

    def payment_information_path
      if account.organization?
        settings_org_billing_tab_path(organization_id: account.display_login, tab: "payment_information")
      else
        settings_user_billing_tab_path(tab: "payment_information")
      end
    end

    def spending_limit_path
      if account.organization?
        settings_org_billing_tab_path(organization_id: account.display_login, tab: "spending_limit")
      else
        settings_user_billing_tab_path(tab: "spending_limit")
      end
    end

    sig { returns(T::Boolean) }
    def show_depleted_prepaid_credits_banner?
      has_past_prepaid_credits? && !prepaid_credit_balance.positive?
    end

    def show_past_invoices?
      account.invoiced? && !account.reseller_customer? && invoice.present?
    end

    def path_for_export
      if account.organization?
        org_metered_exports_path(account)
      else
        metered_exports_path
      end
    end

    def add_or_remove_link_text
      account.has_downgradable_seats? ? "Remove unused seats" : "Add seats"
    end

    def manage_seats_path
      account.has_downgradable_seats? ? remove_org_seats_path(account) : org_seats_path(account)
    end

    def apple_iap_subscription?
      account.user? && account.apple_iap_subscription?
    end

    def actions_and_packages_budget
      @_actions_and_packages_budget ||= account.budget_for(group: :shared)
    end

    def codespaces_ui_enabled?
      codespaces_billing_enabled?(account)
    end

    def is_standalone_org?
      account.organization? && !account.delegate_billing_to_business?
    end

    def codespaces_budget
      @_codespaces_budget ||= account.budget_for(group: :codespaces)
    end

    def account_has_valid_payment_method?
      account.has_valid_payment_method?(feature_type: :noncommercial)
    end

    def has_past_prepaid_credits?
      Billing::PrepaidMeteredUsageRefill.where(owner: account).exists?
    end

    sig { returns(Billing::Money) }
    def prepaid_credit_balance
      @prepaid_credit_balance ||= (account&.customer&.credit_balance || Billing::Money.zero)
    end

    def show_prepaid_credits?
      has_past_prepaid_credits? && prepaid_credit_balance
    end

    def banner_test_selector(threshold_text)
      "subscriptions_#{threshold_text}_resources_threshold"
    end

    def usage_notification_form_action_path
      if account.organization?
        settings_org_usage_notification_settings_path(organization_id: account.display_login)
      else
        settings_user_usage_notification_settings_path
      end
    end

    def display_manual_payment_account_overview_header?
      account.autopay_disabled_by_india_rbi?
    end

    def account_payment_history_path
      if account.organization?
        org_payment_history_path(organization_id: account.display_login)
      else
        payment_history_path
      end
    end

    memoize def has_saved_billing_information?
      account.has_saved_billing_information?
    end

    def ctos_organization_with_data_collection_enabled?
      account.organization? && account.org_is_on_business_tos?
    end

    sig { returns(T::Boolean) }
    memoize def has_add_billing_information_restrictions?
      # if the account doesn't have a blank billing info record, we'll let the respective component handle the data
      account_billing_info_blank = !has_saved_billing_information? || !user_billing_information.valid_for_trade_screening?
      return false unless account_billing_info_blank

      return true if account.has_any_trade_restrictions?
      return true if current_user.has_any_trade_restrictions?
      return true if account.trade_compliance_true_match_restricted?
      return true if current_user.trade_compliance_true_match_restricted?
      false
    end

    # Should the view show the new linking billing information component
    def show_linking_billing_information?
      account.org_is_on_standard_tos?
    end

    def show_billing_information_error_notice?
      return false unless has_saved_billing_information?
      !account.is_allowed_to_edit_trade_screening_information?
    end

    private

    def fetch_invoices
      return [] if account.customer&.zuora_account_id.nil?

      Billing::Zuora::Invoice.invoices_for_account(account.customer.zuora_account_id)
        .sort_by(&:invoice_date)
    rescue Zuorest::HttpError => e
      Failbot.report!(e, app: "github-zuora")
      []
    end
  end
end
