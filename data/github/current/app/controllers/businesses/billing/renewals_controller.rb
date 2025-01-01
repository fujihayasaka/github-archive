# typed: strict
# frozen_string_literal: true

# Used for customer-initiated GHE renewals; specifically for sales-serve customers trying to renew GHE on their own.
# https://github.com/github/gitcoin/issues/16386
class Businesses::Billing::RenewalsController < Businesses::BusinessController
  include Billing::ProrationMath
  before_action :ensure_billing_enabled
  before_action :ensure_not_spammy_user
  before_action :business_access_required
  before_action :ensure_renewal, only: [:new]
  before_action :ensure_upgrade, only: [:edit]
  before_action :ensure_no_overdue_invoice
  before_action :ensure_actively_invoiced
  before_action :ensure_self_serve_eligible
  before_action :ensure_contract_not_too_old
  before_action :ensure_not_in_lock_out_period
  before_action :ensure_added_seats, only: [:create]
  before_action only: [:create] do
    T.bind(self, Businesses::Billing::RenewalsController)

    check_trade_compliance(target: this_business, sdn_redirect: true, redirect_url: settings_billing_tab_enterprise_url(tab: :payment_information))
  end
  before_action only: [:new, :edit] do
    T.bind(self, Businesses::Billing::RenewalsController)

    check_trade_compliance(target: this_business)
  end

  include Site::MicrosoftAnalyticsDependency
  before_action :allow_initial_cookie_consent, only: [:new, :edit]
  before_action :enable_microsoft_analytics, only: [:new, :edit]
  before_action :add_microsoft_analytics_csp_exceptions, only: [:new, :edit]
  before_action :require_tos_acceptance, only: [:create]

  layout "enterprise_funnel", only: [:new, :edit]
  javascript_bundle :billing, only: [:new, :edit]
  stylesheet_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    only: [:new, :edit]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:new, :edit],
    optional: true

  sig { void }
  def new
    summary, line_item_detail = get_price_summary
    upgrade_subtotal = summary.fetch(:upgrade_subtotal)
    upgrade_total = summary.fetch(:upgrade_total)
    yearly_subtotal = summary.fetch(:yearly_subtotal)
    yearly_total = summary.fetch(:yearly_total)
    ghas_line_item = line_item_detail.fetch(:ghas_line_item)
    ghe_line_item = line_item_detail.fetch(:ghe_line_item)
    suggested_ghas_seats = this_business.has_active_advanced_security_trial? ? this_business.advanced_security_license.consumed_seats : 0

    min_ghas_seats_error_message = "You can't have a negative number of committers."
    min_ghe_seats_error_message = "You need at least #{pluralize(this_business.total_consumed_licenses, 'seat')} to support your #{pluralize(this_business.total_consumed_licenses, 'existing member')}."

    respond_to do |format|
      format.html do
        render "businesses/billing_settings/renew", locals: {
          this_business: this_business,
          upgrade_ghas_seats_context: ghas_line_item.fetch(:upgrade_seats_context),
          upgrade_ghe_seats_context: ghe_line_item.fetch(:upgrade_seats_context),
          max_new_seats: max_new_seats,
          max_ghas_seats: max_ghas_seats,
          max_ghe_seats: max_ghe_seats,
          min_ghas_seats: min_ghas_seats,
          min_ghas_seats_error_message: min_ghas_seats_error_message,
          min_ghe_seats: min_ghe_seats,
          min_ghe_seats_error_message: min_ghe_seats_error_message,
          ghe_seats: ghe_seats,
          ghas_seats: ghas_seats,
          ghe_price_per_seat: ghe_price_per_seat,
          ghas_price_per_seat: ghas_price_per_seat,
          suggested_ghas_seats: suggested_ghas_seats,
          upgrade_subtotal: upgrade_subtotal.format,
          upgrade_total: upgrade_total.format,
          yearly_subtotal: yearly_subtotal.format,
          yearly_total: yearly_total.format,
          ghas_line_item:,
          ghe_line_item:,
          ghe_list_price: list_price_for_ghe,
          ghas_list_price: list_price_for_ghas,
        }
      end
      format.json do
        upgrade_now = upgrade_total.amount.to_i > 0
        ghas_upgrade_cost = T.let(ghas_line_item.fetch(:upgrade_cost), T.nilable(Billing::Money))
        ghe_upgrade_cost = T.let(ghe_line_item.fetch(:upgrade_cost), T.nilable(Billing::Money))

        render json: {
          selectors: {
            ".js-renewal-upgrade-ghas-seats-context": ghas_line_item.fetch(:upgrade_seats_context),
            ".js-renewal-upgrade-ghe-seats-context": ghe_line_item.fetch(:upgrade_seats_context),
            ".js-renewal-upgrade-ghas-seats": ghas_line_item.fetch(:upgrade_seats),
            ".js-renewal-upgrade-ghe-seats": ghe_line_item.fetch(:upgrade_seats),
            # These two are separate for conditionally showing/hiding the GHE/GHAS line items in the summary
            ".js-renewal-upgrade-ghas-seats-summary": ghas_line_item.fetch(:upgrade_seats_summary),
            ".js-renewal-upgrade-ghe-seats-summary": ghe_line_item.fetch(:upgrade_seats_summary),
            ".js-renewal-upgrade-ghas-cost": ghas_upgrade_cost&.format,
            ".js-renewal-upgrade-ghe-cost": ghe_upgrade_cost&.format,
            ".js-renewal-upgrade-subtotal": upgrade_now ? upgrade_subtotal.format : nil,
            ".js-renewal-upgrade-total": upgrade_now ? upgrade_total.format : nil,
            ".js-renewal-upgrade-total-numeric": upgrade_now ? upgrade_total.amount.to_i : nil,
            ".js-renewal-yearly-ghas-seats": ghas_line_item.fetch(:seats),
            ".js-renewal-yearly-ghas-cost": ghas_line_item.fetch(:cost).format,
            ".js-renewal-yearly-ghe-seats": ghe_line_item.fetch(:seats),
            ".js-renewal-yearly-ghe-cost": ghe_line_item.fetch(:cost).format,
            ".js-renewal-subtotal": yearly_subtotal.format,
            ".js-renewal-total": yearly_total.format,
          },
        }
      end
    end
  end

  sig { void }
  def edit
    summary, line_item_detail = get_price_summary
    upgrade_subtotal = summary.fetch(:upgrade_subtotal)
    upgrade_total = summary.fetch(:upgrade_total)
    ghas_line_item = line_item_detail.fetch(:ghas_line_item)
    ghe_line_item = line_item_detail.fetch(:ghe_line_item)
    suggested_ghas_seats = this_business.has_active_advanced_security_trial? ? this_business.advanced_security_license.consumed_seats : 0

    min_ghas_seats_error_message = "You can't remove committers outside of the renewal period."
    min_ghe_seats_error_message = "You can't remove seats outside of the renewal period."

    respond_to do |format|
      format.html do
        render "businesses/billing_settings/add_seats", locals: {
          this_business: this_business,
          upgrade_ghas_seats_context: ghas_line_item.fetch(:upgrade_seats_context),
          upgrade_ghe_seats_context: ghe_line_item.fetch(:upgrade_seats_context),
          max_new_seats: max_new_seats,
          max_ghas_seats: max_ghas_seats,
          max_ghe_seats: max_ghe_seats,
          min_ghas_seats: min_ghas_seats,
          min_ghas_seats_error_message: min_ghas_seats_error_message,
          min_ghe_seats: min_ghe_seats,
          min_ghe_seats_error_message: min_ghe_seats_error_message,
          ghe_seats: ghe_seats,
          ghas_seats: ghas_seats,
          ghe_price_per_seat: ghe_price_per_seat,
          ghas_price_per_seat: ghas_price_per_seat,
          suggested_ghas_seats: suggested_ghas_seats,
          upgrade_subtotal: upgrade_subtotal.format,
          upgrade_total: upgrade_total.format,
          ghas_line_item:,
          ghe_line_item:,
          ghe_list_price: list_price_for_ghe,
          ghas_list_price: list_price_for_ghas,
        }
      end
      format.json do
        ghas_upgrade_cost = T.let(ghas_line_item.fetch(:upgrade_cost), T.nilable(Billing::Money))
        ghe_upgrade_cost = T.let(ghe_line_item.fetch(:upgrade_cost), T.nilable(Billing::Money))

        render json: {
          selectors: {
            ".js-renewal-upgrade-ghas-seats-context": ghas_line_item.fetch(:upgrade_seats_context),
            ".js-renewal-upgrade-ghe-seats-context": ghe_line_item.fetch(:upgrade_seats_context),
            ".js-renewal-upgrade-ghas-seats-summary": ghas_line_item.fetch(:upgrade_seats_summary),
            ".js-renewal-upgrade-ghe-seats-summary": ghe_line_item.fetch(:upgrade_seats_summary),
            ".js-renewal-upgrade-ghas-cost": ghas_upgrade_cost&.format,
            ".js-renewal-upgrade-ghe-cost": ghe_upgrade_cost&.format,
            ".js-renewal-upgrade-subtotal": upgrade_subtotal.format,
            ".js-renewal-upgrade-total": upgrade_total.format,
          },
        }
      end
    end
  end

  sig { void }
  def create
    new_term_start_date = (this_business.billing_term_ends_on + 1.day).to_datetime
    new_term_end_date = (this_business.billing_term_ends_on + 1.year).to_datetime

    cr = Billing::SalesServeSubscriptionChangeRequest.build(
      customer: this_business.customer,
      actor: current_user,
      zuora_subscription_number: subscription_number,
    )

    # Renewal
    if renewal?
      # GHE Renewal
      cr.items.build(
        change_type: :renewal,
        status: :pending,
        product_rate_plan_charge_id: ghe_rate_plan_charge_id,
        quantity: ghe_seats,
        price: ghe_price_per_seat,
        start_date: new_term_start_date,
        end_date: new_term_end_date
      )

      # GHAS Renewal
      if ghas_seats > 0 || currently_have_ghas?
        cr.items.build(
          change_type: :renewal,
          status: :pending,
          product_rate_plan_charge_id: ghas_rate_plan_charge_id,
          quantity: ghas_seats,
          price: ghas_price_per_seat,
          start_date: new_term_start_date,
          end_date: new_term_end_date
        )
      end
    end

    # GHE Upgrade
    if has_ghe_upgrade?
      cr.items.build(
        change_type: :update,
        status: :pending,
        product_rate_plan_charge_id: ghe_rate_plan_charge_id,
        quantity: ghe_seats,
        price: ghe_price_per_seat,
        start_date: GitHub::Billing.today.to_datetime,
        end_date: this_business.billing_term_ends_on.to_datetime
      )
    end

    # GHAS Upgrade
    if has_ghas_upgrade?
      cr.items.build(
        change_type: :update,
        status: :pending,
        product_rate_plan_charge_id: ghas_rate_plan_charge_id,
        quantity: ghas_seats,
        price: ghas_price_per_seat,
        start_date: GitHub::Billing.today.to_datetime,
        end_date: this_business.billing_term_ends_on.to_datetime
      )
    end

    if success = (cr.save && cr.send_to_salesforce)
      redirect_to enterprise_licensing_path(this_business)
    else
      if cr.valid?
        cr.items.each { |item| item.status = :error }
        cr.save!
        GitHub.logger.info(
          "Failed to emit Billing::SalesServeSubscriptionChangeRequest to salesforce",
          business_id: this_business.id,
          request_id: cr.id,
        )
      else
        GitHub.logger.info(
          "Failed to create Billing::SalesServeSubscriptionChangeRequest",
          business_id: this_business.id,
          messages: cr.errors.full_messages,
        )
      end

      flash[:error] = "Failed to complete GitHub Enterprise purchase. Please try again later or contact support."
      redirect_back(fallback_location: enterprise_licensing_path(this_business))
    end

    action = renewal? ? "renew" : "add_seats"
    analytics_event(
      category: "business_#{action}",
      action: "complete_github_enterprise_#{action}",
      label: "enterprise_id:#{this_business.id};seats:#{ghe_seats};committers:#{ghas_seats};success:#{success};"
    )
    GitHub.dogstats.increment("business.#{action}", tags: ["enterprise", "advanced_security:#{ghas_seats > 0}", "success:#{success}"])
  end

  private

  sig { returns(T.nilable(String)) }
  def ghe_rate_plan_charge_id
    return GitHub.zuora_sales_serve_ghe_product_charge_ids.first if Rails.env.development?

    if GitHub.flipper[:sales_serve_subscription_optimize_scientist].enabled?
      experiment_sales_serve_subscription&.ghe_rate_plan_charge&.product_rate_plan_charge_id
    else
      sales_serve_subscription&.ghe_rate_plan_charge&.product_rate_plan_charge_id
    end
  end

  sig { returns(T.nilable(String)) }
  def ghas_rate_plan_charge_id
    sales_serve_subscription&.ghas_rate_plan_charge&.product_rate_plan_charge_id || GitHub.zuora_sales_serve_ghe_ghas_mapping[ghe_rate_plan_charge_id]
  end

  sig { returns [T::Hash[Symbol, T.untyped], T::Hash[Symbol, T.untyped]] }
  def get_price_summary
    upgrade_subtotal = Billing::Money.zero
    upgrade_tax = Billing::Money.zero
    upgrade_total = Billing::Money.zero

    yearly_subtotal = Billing::Money.zero
    yearly_tax = Billing::Money.zero
    yearly_total = Billing::Money.zero

    ghe_line_item = {
      name: "Enterprise Cloud",
      seats: ghe_seats > 0 ? pluralize(ghe_seats, "seat") : nil,
      cost: ghe_price_per_seat * ghe_seats,
      upgrade_seats: ghe_upgrade_eligible? ? pluralize(net_ghe_seats, "additional seat") : nil,
      upgrade_seats_summary: ghe_upgrade_eligible? ? pluralize(net_ghe_seats, "seat") : nil,
      upgrade_seats_context: upgrade_ghe_seats_context,
      upgrade_cost: nil,
    }
    yearly_subtotal += ghe_line_item.fetch(:cost)

    if has_ghe_upgrade?
      ghe_line_item.merge!(
        upgrade_cost: prorated_price(ghe_price_per_seat, GitHub::Billing.today, this_business.billing_term_ends_on) * net_ghe_seats
      )
      upgrade_subtotal += ghe_line_item.fetch(:upgrade_cost)
    end

    ghas_line_item = {
      name: "Advanced Security",
      seats: ghas_seats > 0 ? pluralize(ghas_seats, "committer") : nil,
      cost: ghas_price_per_seat * ghas_seats,
      upgrade_seats: ghas_upgrade_eligible? ? pluralize(net_ghas_seats, "additional committer") : nil,
      upgrade_seats_summary: ghas_upgrade_eligible? ? pluralize(net_ghas_seats, "committer") : nil,
      upgrade_seats_context: upgrade_ghas_seats_context,
      upgrade_cost: nil,
    }
    yearly_subtotal += ghas_line_item.fetch(:cost)

    if has_ghas_upgrade?
      ghas_line_item.merge!(
        upgrade_cost: prorated_price(ghas_price_per_seat, GitHub::Billing.today, this_business.billing_term_ends_on) * net_ghas_seats
      )
      upgrade_subtotal += ghas_line_item.fetch(:upgrade_cost)
    end

    upgrade_total += upgrade_tax
    upgrade_total += upgrade_subtotal

    yearly_total += yearly_subtotal
    yearly_total += yearly_tax

    [
      {
        upgrade_subtotal: upgrade_subtotal,
        upgrade_tax: upgrade_tax,
        upgrade_total: upgrade_total,
        yearly_subtotal: yearly_subtotal,
        yearly_tax: yearly_tax,
        yearly_total: yearly_total,
      },
      {
        ghas_line_item:,
        ghe_line_item:,
      },
    ]
  end

  sig { returns(T.nilable(String)) }
  def upgrade_ghe_seats_context
    if net_ghe_seats.zero?
      "This is your current number of seats"
    elsif net_ghe_seats.positive?
      if upgrade_has_renewal_already_requested_with_seat_gap?
        safe_join(["You can only add ", content_tag(:strong, pluralize(net_ghe_seats, "seat")), " to match your upcoming renewal"])
      elsif upgrade?
        safe_join(["You are adding ", content_tag(:strong, pluralize(net_ghe_seats, "seat")), " that will be available immediately"])
      else
        safe_join(["You are adding ", content_tag(:strong, pluralize(net_ghe_seats, "seat")), " to your next contract"])
      end
    end
  end

  sig { returns(T.nilable(String)) }
  def upgrade_ghas_seats_context
    if net_ghas_seats.zero? && ghas_seats.positive?
      "This is your current number of committers"
    elsif net_ghas_seats.positive?
      if upgrade_has_renewal_already_requested_with_seat_gap?
        safe_join(["You can only add ", content_tag(:strong, pluralize(net_ghas_seats, "committer")), " to match your upcoming renewal"])
      elsif upgrade?
        safe_join(["You are adding ", content_tag(:strong, pluralize(net_ghas_seats, "committer")), " that will be available immediately"])
      else
        safe_join(["You are adding ", content_tag(:strong, pluralize(net_ghas_seats, "committer")), " to your next contract"])
      end
    end
  end

  sig { returns(T::Boolean) }
  memoize def renewal?
    this_business.eligible_for_renewal?
  end

  sig { returns(T::Boolean) }
  memoize def upgrade?
    this_business.eligible_for_upgrade?
  end

  sig { returns(T::Boolean) }
  def upgrade_has_renewal_already_requested_with_seat_gap?
    upgrade? && this_business.renewal_already_requested? && this_business.renewal_has_seat_gap?
  end

  sig { returns(T.nilable(Billing::Zuora::SalesManagedSubscription)) }
  memoize def sales_serve_subscription
    this_business.sales_managed_subscription
  end

  sig { returns(T.nilable(Billing::SalesServePlanSubscription)) }
  memoize def experiment_sales_serve_subscription
    this_business.customer&.sales_serve_plan_subscription
  end

  sig { returns(Integer) }
  def max_new_seats
    Configurable::SeatLimitForUpgrades::DEFAULT_SEAT_LIMIT_FOR_TRANSACTIONS
  end

  sig { returns(Integer) }
  def max_ghe_seats
    return min_ghe_seats if upgrade_has_renewal_already_requested_with_seat_gap?
    this_business.seats + max_new_seats
  end

  sig { returns(Integer) }
  def max_ghas_seats
    return min_ghas_seats if upgrade_has_renewal_already_requested_with_seat_gap?
    this_business.advanced_security_license.seats + max_new_seats
  end

  sig { returns(Integer) }
  def min_ghe_seats
    min_seats = renewal? ? this_business.total_consumed_licenses : this_business.seats
    min_seats = (this_business.ghe_renewal_seat_quantity || min_seats) if upgrade_has_renewal_already_requested_with_seat_gap?
    [min_seats.to_i, 1].max
  end

  sig { returns(Integer) }
  def min_ghas_seats
    # For renewal, ghas can be deprovisioned
    return 0 if renewal?
    # For upgrade with pending renewal with seat gap, we bring up the seat count to fill the gap
    return this_business.ghas_renewal_seat_quantity || this_business.advanced_security_license.seats if upgrade_has_renewal_already_requested_with_seat_gap?
    this_business.advanced_security_license.seats || 0
  end

  sig { returns(Integer) }
  memoize def ghe_seats
    seats = params[:seats] ? params[:seats].to_i : this_business.seats
    seats = [seats, this_business.seats + max_new_seats].min    # upper limit is current number of seats + 300
    seats = [seats, min_ghe_seats].max                       # lower limit is consumed seat or minimum seats
  end

  sig { returns(Integer) }
  memoize def net_ghe_seats
    ghe_seats - this_business.seats
  end

  sig { returns(Billing::Money) }
  memoize def ghe_price_per_seat
    if GitHub.flipper[:sales_serve_subscription_optimize_scientist].enabled?
      price = experiment_sales_serve_subscription&.ghe_rate_plan_charge&.price

      # Fall back to a default if we get nil
      price ||= list_price_for_ghe

      Billing::Money.parse(price)
    else
      Billing::Money.parse(sales_serve_subscription&.ghe_rate_plan_charge&.price || list_price_for_ghe)
    end
  end

  # Use this to determine if upgrade should be included in change request
  sig { returns(T::Boolean) }
  memoize def has_ghe_upgrade?
    (ActiveRecord::Type::Boolean.new.cast(params[:ghe_upgrade_now]) || upgrade?) && upgrade_ghe?
  end

  # Use this to determine if upgrade option should be shown to the user
  sig { returns(T::Boolean) }
  def ghe_upgrade_eligible?
    upgrade? || upgrade_ghe?
  end

  # Use this to determine if the upgrade is requested by the user (disqualifying expired contract)
  sig { returns(T::Boolean) }
  def upgrade_ghe?
    return false if GitHub::Billing.past?(this_business.billing_term_ends_on)

    net_ghe_seats > 0
  end

  sig { returns(Integer) }
  memoize def ghas_seats
    existing_ghas_seats = this_business.has_active_advanced_security_trial? ? this_business.advanced_security_license.consumed_seats : this_business.advanced_security_license.seats
    committers = params[:committers] ? params[:committers].to_i : existing_ghas_seats
    committers = [committers, existing_ghas_seats + max_new_seats].min
    committers = [committers, min_ghas_seats].max
  end

  sig { returns(Integer) }
  memoize def net_ghas_seats
    ghas_seats - this_business.advanced_security_license.seats
  end

  sig { returns(Billing::Money) }
  memoize def ghas_price_per_seat
    if GitHub.flipper[:sales_serve_subscription_optimize_scientist].enabled?
      price = experiment_sales_serve_subscription&.ghas_rate_plan_charge&.price

      # Fall back to a default if we get nil
      price ||= list_price_for_ghas

      Billing::Money.parse(price)
    else
      Billing::Money.parse(sales_serve_subscription&.ghas_rate_plan_charge&.price || list_price_for_ghas)
    end
  end

  # Use this to determine if upgrade should be included in change request
  sig { returns(T::Boolean) }
  memoize def has_ghas_upgrade?
    (ActiveRecord::Type::Boolean.new.cast(params[:ghas_upgrade_now]) || upgrade?) && upgrade_ghas?
  end

  # Use this to determine if upgrade option should be shown to the user
  sig { returns(T::Boolean) }
  def ghas_upgrade_eligible?
    upgrade? || upgrade_ghas?
  end

  # Use this to determine if the upgrade is requested by the user (disqualifying expired contract)
  sig { returns(T::Boolean) }
  def upgrade_ghas?
    return false if GitHub::Billing.past?(this_business.billing_term_ends_on)

    net_ghas_seats > 0
  end

  # We use this to determine if the renewal should include ghas, even if the count is 0
  sig { returns(T::Boolean) }
  def currently_have_ghas?
    # Not using `advanced_security_purchased?`, cause unlimited seats (0) is a thing
    # and we don't want to accidentally deprovision ghas at renewal.
    # Best we can do is to not include it in the request and let salesforce handle it.
    this_business.advanced_security_license.seats > 0
  end

  sig { params(price: Billing::Money, start_date: Date, end_date: Date).returns(Billing::Money) }
  def prorated_price(price, start_date, end_date)
    # Number of days in the current contract year
    year_in_days = end_date - (end_date - 1.year)
    # Start and end dates inclusive
    prorate(price, (end_date - start_date + 1) / year_in_days)
  end

  sig { returns(Billing::Money) }
  def list_price_for_ghe
    if GitHub.flipper[:sales_serve_subscription_optimize_scientist].enabled?
      sku = experiment_sales_serve_subscription&.ghe_rate_plan_charge&.product_rate_plan_charge_id
    else
      sku = sales_serve_subscription&.ghe_rate_plan_charge&.product_rate_plan_charge_id
    end

    if sku.nil?
      price = 252
    else
      price = Business::BillingContractUpdateDependency.list_price_for_sku(sku)
    end
    Billing::Money.parse(price.to_s)
  end

  sig { returns(Billing::Money) }
  def list_price_for_ghas
    if GitHub.flipper[:sales_serve_subscription_optimize_scientist].enabled?
      sku = experiment_sales_serve_subscription&.ghas_rate_plan_charge&.product_rate_plan_charge_id
    else
      sku = sales_serve_subscription&.ghas_rate_plan_charge&.product_rate_plan_charge_id
    end

    if sku.nil?
      price = 588
    else
      price = Business::BillingContractUpdateDependency.list_price_for_sku(sku)
    end
    Billing::Money.parse(price.to_s)
  end

  sig { returns(T.nilable(String)) }
  def subscription_id
    return "dev-subscription-id" if Rails.env.development?

    if GitHub.flipper[:sales_serve_subscription_optimize_scientist].enabled?
      experiment_sales_serve_subscription&.id
    else
      sales_serve_subscription&.id
    end
  end

  sig { returns(T.nilable(String)) }
  def subscription_number
    return "dev-subscription-number" if Rails.env.development?

    if GitHub.flipper[:sales_serve_subscription_optimize_scientist].enabled?
      experiment_sales_serve_subscription&.zuora_subscription_number
    else
      sales_serve_subscription&.subscription_number
    end
  end

  sig { void }
  def ensure_no_overdue_invoice
    redirect_to(settings_billing_tab_enterprise_path(this_business, :payment_information)) if this_business.past_due_invoice?
  end

  sig { returns(String) }
  def generic_failure_message
    "We were not able to process this transaction. Please contact sales: https://github.com/renewals-help"
  end

  sig { void }
  def ensure_actively_invoiced
    return if Rails.env.development?

    if GitHub.flipper[:sales_serve_subscription_optimize_scientist].enabled?
      has_subscription = experiment_sales_serve_subscription.present?
      return if this_business.invoiced? && has_subscription
    else
      return if this_business.invoiced? && sales_serve_subscription.present?
    end

    flash[:error] = generic_failure_message
    redirect_to enterprise_path(this_business)
  end

  sig { void }
  def ensure_self_serve_eligible
    return if this_business.sales_managed_subscription_self_serve_eligible?
    flash[:error] = generic_failure_message

    redirect_to enterprise_path(this_business)
  end

  sig { void }
  def ensure_contract_not_too_old
    return if this_business.billing_term_ends_on > (GitHub::Billing.today - 1.year)

    flash[:error] = generic_failure_message
    redirect_to enterprise_path(this_business)
  end

  sig { void }
  def ensure_not_in_lock_out_period
    redirect_to settings_billing_enterprise_path(this_business) if this_business.in_lock_out_period?
  end

  sig { void }
  def ensure_renewal
    return if renewal?

    flash[:error] = generic_failure_message
    redirect_to enterprise_path(this_business)
  end

  sig { void }
  def ensure_upgrade
    return if upgrade?

    flash[:error] = generic_failure_message
    redirect_to enterprise_path(this_business)
  end

  sig { void }
  def ensure_added_seats
    # Only upgrades have restriction for removing seats
    return unless upgrade?

    net_seats = [net_ghe_seats, net_ghas_seats]
    if net_seats.any?(&:negative?) || net_seats.all?(&:zero?)
      flash[:error] = "To upgrade you must add at least 1 seat."
      redirect_back(fallback_location: enterprise_licensing_path(this_business))
    end
  end
end
