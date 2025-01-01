# typed: strict
# frozen_string_literal: true

module BillingSettingsHelper

  include FeatureFlagHelper
  include GitHub::Memoizer

  MUNICH_FEATURE_LISTS = T.let({
    pro: [
      "Required reviewers in private repos",
      "Protected branches in private repos",
      "Repository insights in private repos",
      "Wikis in private repos",
      "Pages in private repos",
      "Code owners in private repos",
      "3,000 minutes for GitHub Actions",
      "2GB of GitHub Packages storage",
      "180 core-hours of Codespaces compute",
      "20GB of Codespaces storage"
    ],
    team: [
      "Required reviewers in private repos",
      "Protected branches in private repos",
      "Multiple issue assignees in private repos",
      "Multiple PR assignees in private repos",
      "Repository insights in private repos",
      "Pages in private repos",
      "Code owners in private repos",
      "3,000 minutes for GitHub Actions",
      "2GB of GitHub Packages storage",
      "Standard support"
    ],
    enterprise: [
      "SAML single sign-on",
      "Enterprise support",
      "Advanced auditing",
      "99.95 uptime SLA",
      "50,000 minutes for GitHub Actions",
      "50GB of GitHub Packages storage"
    ]
  }, { pro: T::Array[String], team: T::Array[String], enterprise: T::Array[String] })

  LFS_REPOSITORY_LIMIT = 5

  # Controls the maximum number of pending invitations that we will display in a popup dialog.
  PENDING_INVITATION_DIALOG_LIST_LIMIT = 99

  USAGE_PERIOD = T.let({
    this_hour: 1,
    today: 2,
    this_month: 3,
    this_year: 4,
    last_month: 5,
    last_year: 6,
  }, T::Hash[Symbol, T.untyped])

  sig do
    params(entity: ::Billing::Types::Account)
      .returns(T::Array[{ id: String, displayText: String }])
  end
  def usage_customer_selections(entity)
    customer = T.must(entity.customer)
    response = Billing::Platform::Api::Client.new.get_all_cost_centers(customer_id: customer.id.to_s, use_cache: true)
    selections = [{ id: customer.id.to_s, displayText: "None" }]

    unless response.is_a?(Billing::Platform::Api::Error)
      cost_centers = response[:costCenters].map { |cc| { id: cc[:costCenterKey][:uuid], displayText: cc[:name] } }
      selections = cost_centers + selections
    end

    selections
  end

  sig do
    params(entity: ::Billing::Types::Account)
      .returns({ billingTarget: Integer, customerId: Integer, customerType: String, displayId: String, name: String,
                isVNextNative: T::Boolean, plan: String, planDuration: String, seats: Integer, pricePerSeat: BigDecimal, paymentAmount: BigDecimal, hasPendingPlanChange: T::Boolean, })
  end
  def customer_payload(entity)
    customer = T.must(entity.customer)

    pending_cycle =
      case entity
      when Organization, User
        entity.pending_cycle(include_addons: false)
      when Business
        entity.pending_cycle
      end

    pending_plan = pending_cycle.plan
    pending_cycle_plan_name = pending_plan.entitlement_plan_name || pending_plan.name

    current_plan = entity.plan
    current_plan_name = current_plan.entitlement_plan_name || current_plan.name

    has_pending_plan_change = current_plan_name != pending_cycle_plan_name
    plan_duration = entity.plan_duration.downcase

    price_per_seat = case plan_duration
    when User::BillingDependency::YEARLY_PLAN
      current_plan.yearly_unit_cost
    else
      current_plan.unit_cost
    end

    {
      billingTarget: customer.billing_platform_billing_target,
      customerId: customer.id.to_i,
      customerType: entity.class.name.to_s,
      displayId: entity.display_login.to_s,
      name: entity.safe_profile_name.to_s,
      isVNextNative: customer.is_vnext_native?,
      plan: current_plan_name,
      planDuration: plan_duration,
      seats: pending_cycle.seats,
      pricePerSeat: BigDecimal(price_per_seat, 2),
      paymentAmount: BigDecimal(pending_cycle.payment_amount(use_balance: false).dollars),
      hasPendingPlanChange: has_pending_plan_change
    }
  end

  sig { params(entity: T.nilable(::Billing::Types::Account)).returns(T::Array[String]) }
  def admin_roles(entity)
    roles = []
    return roles unless entity

    current_user = T.cast(T.unsafe(self).current_user, User)

    roles << "billing_manager" if (entity.is_a?(Organization) || entity.is_a?(Business)) && entity.billing_manager?(current_user)
    roles << "member" if entity.is_a?(Organization) && entity.member?(current_user)
    roles << "owner" if entity.is_a?(Business) && entity.owner?(current_user)
    roles << "owner" if entity.is_a?(Organization) && current_user.owned_organizations.include?(entity)
    roles << "owner" if entity.is_a?(User) && current_user == entity
    roles << "enterprise_org_owner" if entity.is_a?(Business) && entity.user_is_owner_of_owned_org?(current_user)

    roles
  end

  sig { returns(T::Array[{ type: Integer, displayText: String }]) }
  def usage_period_selections
    [
      { type: USAGE_PERIOD[:today], displayText: "Today" },
      { type: USAGE_PERIOD[:this_month], displayText: "Current month" },
      { type: USAGE_PERIOD[:last_month], displayText: "Last month" },
      { type: USAGE_PERIOD[:this_year], displayText: "This year (#{Time.now.utc.year})" },
      { type: USAGE_PERIOD[:last_year], displayText: "Last year (#{Time.now.utc.year - 1})" },
    ]
  end

  sig { params(this_entity: ::Billing::Types::Account).returns(T::Array[{ type: Integer, displayText: String }]) }
  def usage_group_selections(this_entity)
    selections = [
      { type: BillingPlatform::Base::UsageGroupBy::NoGroupBy, displayText: "None" },
      { type: BillingPlatform::Base::UsageGroupBy::GroupByProduct, displayText: "Product" },
      { type: BillingPlatform::Base::UsageGroupBy::GroupBySku, displayText: "SKU" },
      { type: BillingPlatform::Base::UsageGroupBy::GroupByRepository, displayText: "Repository" }]
    if this_entity.is_a?(Business)
      selections.push({ type: BillingPlatform::Base::UsageGroupBy::GroupByOrganization, displayText: "Organization" }, { type: BillingPlatform::Base::UsageGroupBy::GroupByCostCenter, displayText: "Cost Center" })
    end
    selections
  end

  sig do
    params(target: ::Billing::Types::Account, actor: T.nilable(User))
      .returns(T::Array[GitHub::Plan])
  end
  def available_plans(target, actor: nil)
    plans = if target.organization?
      GitHub::Plan.org_plans
    elsif target.billable?
      GitHub::Plan.user_plans
    else
      []
    end

    upgrade_restriction = ::Billing::PlanChange::LegacyUpgradeRestriction.new(target: target, actor: (actor || target))
    plans = plans.select { |plan| upgrade_restriction.allow_plan?(plan) }

    @plan ||= T.let(nil, T.nilable(GitHub::Plan))
    plans += [@plan] if @plan

    # Add the user's current plan to the list of available plans (if it's a
    # hidden plan that's not already in there). The free_with_addons plan is a
    # special case — don't display that one because users believe they're on
    # the free plan.

    if !plans.include?(target.plan) && !target.plan.free_with_addons?
      plans += [target.plan]
    end

    plans.sort_by { |plan| -plan.cost }
  end

  sig { params(target: User, plan: GitHub::Plan).returns(T::Boolean) }
  def show_downgrade_survey?(target, plan)
    return false unless target.organization?
    return false if target.plan.cost < plan.cost
    true
  end

  sig { params(target: User, plan: GitHub::Plan).returns(String) }
  def upgrade_downgrade_form_action_path(target, plan)
    if target.plan.cost < plan.cost
      target_cc_update_path(target)
    else
      target_downgrade_with_exit_survey_path(target)
    end
  end

  sig { params(target: User).returns(String) }
  def target_downgrade_with_exit_survey_path(target)
    if target.organization?
      T.unsafe(self).org_downgrade_with_exit_survey_path
    else
      T.unsafe(self).downgrade_with_exit_survey_path
    end
  end

  sig { params(target: User).returns(String) }
  def target_cycle_update_path(target)
    if target.organization?
      T.unsafe(self).org_cycle_update_path
    else
      T.unsafe(self).cycle_update_path
    end
  end

  sig { params(target: User).returns(String) }
  def target_cc_update_path(target)
    if target.organization?
      T.unsafe(self).org_cc_update_path
    else
      T.unsafe(self).cc_update_path
    end
  end

  sig { params(target: ::Billing::Types::Account).returns(String) }
  def target_update_credit_card_path(target)
    if target.organization?
      T.unsafe(self).org_update_credit_card_path(target.display_login)
    elsif target.is_a?(Business)
      T.unsafe(self).billing_settings_update_payment_method_enterprise_path(target)
    else
      T.unsafe(self).update_credit_card_path
    end
  end

  sig { params(target: ::Billing::Types::Account, query_params: T.untyped).returns(String) }
  def target_billing_path(target, query_params = nil)
    if target.is_a?(Business)
      T.unsafe(self).settings_billing_enterprise_path(target, query_params)
    elsif target.organization? && target.business.present?
      T.unsafe(self).settings_billing_enterprise_path(target.business, query_params)
    elsif target.organization?
      T.unsafe(self).settings_org_billing_path(target, query_params)
    else
      T.unsafe(self).settings_user_billing_path(query_params)
    end
  end

  # Public: Billing settings url for a given actor
  sig { params(target: ::Billing::Types::Account, tab: T.nilable(T.any(String, Symbol))).returns(String) }
  def target_billing_url(target, tab: nil)
    if target.is_a?(Business)
      # billing platform customers should be directed to the billing platform overview page
      if target.customer&.billed_via_billing_platform?
        T.unsafe(self).enterprise_billing_url(target)
      else
        tab ? T.unsafe(self).settings_billing_tab_enterprise_url(target, tab: tab) : T.unsafe(self).settings_billing_enterprise_url(target)
      end
    elsif target.organization?
      tab ? T.unsafe(self).settings_org_billing_tab_url(target, tab: tab) : T.unsafe(self).settings_org_billing_url(target)
    else
      tab ? T.unsafe(self).settings_user_billing_tab_url(tab: tab) : T.unsafe(self).settings_user_billing_url
    end
  end

  sig { params(target: ::Billing::Types::Account, invoice_number: String).returns(String) }
  def target_show_invoice_path(target, invoice_number)
    if target.is_a?(Business)
      T.unsafe(self).show_invoice_enterprise_path(target, invoice_number)
    elsif target.is_a?(Organization)
      T.unsafe(self).show_invoice_org_path(target, invoice_number)
    else
      T.unsafe(self).show_invoice_path(target, invoice_number)
    end
  end

  sig { params(target: ::Billing::Types::Account, invoice_number: String).returns(String) }
  def target_invoice_signature_path(target, invoice_number)
    if target.is_a?(Business)
      T.unsafe(self).invoice_signature_enterprise_path(target, invoice_number)
    else
      T.unsafe(self).invoice_signature_path(target, invoice_number)
    end
  end

  # Public: Return the path for updating payment method for a target
  sig { params(target: ::Billing::Types::Account, arg: T::Hash[Symbol, T.untyped]).returns(String) }
  def target_payment_method_path(target, arg = {})
    if target.is_a?(Business)
      T.unsafe(self).settings_billing_enterprise_path(target, arg)
    elsif target.is_a?(Organization)
      target_org_payment_method_path(target, arg)
    else
      T.unsafe(self).settings_user_billing_tab_path(tab: "payment_information")
    end
  end

  # Public: Return the path for updating an organizations payment method
  sig { params(target: Organization, arg: T::Hash[Symbol, T.untyped]).returns(String) }
  def target_org_payment_method_path(target, arg)
    return T.unsafe(self).settings_billing_enterprise_path(target.business, arg) if target.business.present?

    T.unsafe(self).settings_org_billing_tab_path(organization_id: target.display_login, tab: "payment_information")
  end

  sig { params(target: User, options: T::Hash[Symbol, T.untyped]).returns(String) }
  def target_billing_data_plan_path(target, options = {})
    if target.organization?
      T.unsafe(self).org_billing_data_plan_path(target, options)
    else
      T.unsafe(self).billing_data_plan_path(options)
    end
  end

  sig { params(target: User, options: T::Hash[Symbol, T.untyped]).returns(String) }
  def target_billing_upgrade_data_plan_path(target, options = {})
    if target.organization?
      T.unsafe(self).org_billing_upgrade_data_plan_path(target, options)
    else
      T.unsafe(self).billing_upgrade_data_plan_path(options)
    end
  end

  sig { params(target: User, options: T::Hash[Symbol, T.untyped]).returns(String) }
  def target_billing_downgrade_data_plan_path(target, options = {})
    if target.organization?
      T.unsafe(self).org_billing_downgrade_data_plan_path(target, options)
    else
      T.unsafe(self).billing_downgrade_data_plan_path(options)
    end
  end

  sig { params(target: User).returns(String) }
  def target_self_serve_invoicing_path(target)
    if target.organization?
      T.unsafe(self).org_self_serve_invoicing_path(target)
    else
      T.unsafe(self).billing_self_serve_invoicing_path(target)
    end
  end

  sig { params(tab: T.nilable(String)).returns(String) }
  def billing_page_title(tab)
    case tab
    when "payment_information"
      "Payment Information"
    when "spending_limit"
      "Spending Limit"
    when "marketplace_apps"
      "Marketplace Apps"
    when "budgets"
      "Budgets"
    when "past_invoices"
      "Past Invoices"
    when "billing_emails"
      "Billing Emails"
    when "sponsorships"
      "Sponsorships"
    else
      "Billing"
    end
  end

  # Public: Boolean if this is an organization is on per-seat pricing and has limited seats
  sig { params(target: Organization).returns(T::Boolean) }
  def on_per_seat_pricing?(target)
    !!(target.organization? && target.plan.per_seat? && !target.has_unlimited_seats?)
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  memoize def payment_details
    parse_payment_details
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def parse_payment_details
    params = T.unsafe(self).params
    current_user = T.unsafe(self).current_user
    return HashWithIndifferentAccess.new unless billing = params[:billing]

    hash = HashWithIndifferentAccess.new \
      actor: current_user

    hash[:billing_extra] = billing[:billing_extra] unless billing[:billing_extra].nil?
    hash[:vat_code] = billing[:vat_code] unless billing[:vat_code].nil?

    if address = billing[:billing_address]
      hash[:billing_address] = {
        country_code_alpha3: address[:country_code_alpha3],
        region: address[:region],
        postal_code: address[:postal_code],
        address1: address[:address1],
        address2: address[:address2],
        city: address[:city],
      }
    end

    if address.nil?
      billing_address_owner =
        if defined?(this_business)
          T.unsafe(self).this_business
        elsif params[:target] == "organization"
          org_login_param = T.unsafe(self).org_login_param
          Organization.find_by(login: org_login_param)
        else
          current_user
        end

      if billing_address_owner&.billing_contact&.persisted?
        billing_address = billing_address_owner.billing_contact
        hash[:billing_address] = {
          country_code_alpha3: billing_address.country.alpha3,
          region: billing_address.region,
          postal_code: billing_address.postal_code,
          address1: billing_address.address1,
          address2: billing_address.address2,
          city: billing_address.city,
        }
      end
    end

    if payment_method_id = billing[:zuora_payment_method_id]
      hash[:zuora_payment_method_id] = payment_method_id
    elsif paypal_nonce = billing[:paypal_nonce]
      hash[:paypal_nonce] = paypal_nonce
    elsif credit_card = billing[:credit_card]
      hash[:credit_card] = {
        number: credit_card[:number],
        expiration_month: credit_card[:expiration_month],
        expiration_year: credit_card[:expiration_year],
        cvv: credit_card[:cvv],
      }
    else
      return HashWithIndifferentAccess.new # No valid payment method included.
    end

    hash
  end

  sig { returns(Billing::PaymentDetails) }
  memoize def payment_details_object
    Billing::PaymentDetails.new(payment_details)
  end

  sig { returns(T::Boolean) }
  def has_payment_details?
    payment_details_object.valid?
  end

  sig { returns(T::Boolean) }
  def no_payment_details?
    !has_payment_details?
  end

  sig { returns(T::Boolean) }
  def payment_details_includes_paypal?
    payment_details_object.paypal_details?
  end

  sig { params(target: User).returns(String) }
  def purchase_button_aria_label(target)
    if can_purchase_data_packs?(target)
      "Purchase"
    else
      "Add a payment method to purchase"
    end
  end

  sig { params(target: T.any(User, Organization)).returns(T::Boolean) }
  def can_purchase_data_packs?(target)
    target.has_valid_payment_method?(should_delegate_billing_to_business: true) || !!target.coupon&.one_hundred_percent_discount?
  end

  sig { returns(String) }
  def sanctioned_by_ofac_message
    return "" unless T.unsafe(self).current_user.ofac_sanctioned?

    TradeControls::Notices.notice_as_plaintext(:user_account_restricted)
  end

  sig { params(plan: GitHub::Plan, account_type: T.nilable(String)).returns(String) }
  def short_plan_name(plan, account_type: nil)
    plan.display_name(account_type).titleize
  end

  sig { params(plan: GitHub::Plan, account_type: T.nilable(String)).returns(String) }
  def branded_plan_name(plan, account_type: nil)
    "GitHub #{short_plan_name(plan, account_type: account_type)}"
  end

  sig { returns(T.nilable(Survey)) }
  def downgrade_survey
    Survey.find_by(slug: "per_seat_org_downgrade_text_only")
  end

  sig { params(survey: Survey).returns(T.nilable(SurveyQuestion)) }
  def downgrade_reason_survey_question(survey)
    survey.questions.visible.find_by(short_text: "downgrade_reason")
  end

  sig { params(survey: Survey).returns(T.nilable(SurveyQuestion)) }
  def contact_opt_in_survey_question(survey)
    survey.questions.visible.find_by(short_text: "contact_opt_in")
  end

  sig { params(question: SurveyQuestion).returns([T.nilable(SurveyChoice), T.nilable(SurveyChoice)]) }
  def yes_no_opt_in_choices(question)
    yes = question.choices.find_by(short_text: "yes")
    no = question.choices.find_by(short_text: "no")
    [yes, no]
  end

  # Public: The formatted active_on of a pending change
  # Examples
  #
  #   pending_change_active_on(user_or_org_instance)
  #   # => "Apr 21, 2020"
  sig { params(target: ::Billing::Types::Account).returns(String) }
  def pending_change_active_on(target)
    pending_cycle(target).active_on.strftime("%b %d, %Y")
  end

  # Public: The pending cycle associated with the passed account
  sig { params(target: ::Billing::Types::Account).returns(::Billing::PendingCycle) }
  def pending_cycle(target)
    @_pending_cycle ||= T.let({}, T.nilable(T::Hash[Integer, ::Billing::PendingCycle]))
    @_pending_cycle[T.cast(target.id, Integer)] ||= target.pending_cycle
  end

  sig { params(business: Business).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def pending_cycle_seat_change_payload(business)
    return nil unless business.pending_cycle_change&.changing_seats?

    {
      changeType: business.pending_cycle.downgrading? && business.seats > business.pending_cycle.seats ? "downgrade" : "upgrade",
      effectiveDate: business.pending_cycle.active_on&.as_json,
      isChangingDuration: business.pending_cycle.changing_duration?,
      isChangingSeats: business.pending_cycle.plan.per_seat? && business.pending_cycle.seats && business.pending_cycle.seats > 0,
      newPrice: business.pending_cycle_new_price&.format(no_cents_if_whole: true),
      newSeatCount: business.pending_cycle.seats,
      planDisplayName: business.pending_cycle.plan.display_name.humanize,
      planDuration: business.pending_cycle.plan_duration.downcase,
    }
  end

  sig { params(business: Business).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def ghas_pending_plan_change_payload(business)
    return nil unless pending_change = business.advanced_security_subscription_change
    {
      changeType: pending_change.quantity > business.advanced_security_seats_for_entity ? "change" : "downgrade",
      effectiveDate: pending_change.active_on.in_time_zone(GitHub::Billing.timezone).as_json,
      id: pending_change.id,
      isCancellation: pending_change.cancellation?,
      isChangingDuration: false,
      isChangingSeats: true,
      newPrice: business.advanced_security_price(seats: pending_change.quantity).format(no_cents_if_whole: true),
      newSeatCount: pending_change.quantity,
      planDuration: pending_change.subscribable&.billing_cycle,
      planDisplayName: pending_change.subscribable&.name,
    }
  end

  sig { params(type: Symbol, actor: User).returns(T::Array[String]) }
  def feature_list(type, actor)
    MUNICH_FEATURE_LISTS[type].uniq
  end

  sig { params(target: User).returns(T::Boolean) }
  def can_manage_munich_seats?(target)
    target.munich_seats_manageable_by?(T.unsafe(self).current_user)
  end

  sig { params(target: User, seat_change: ::Billing::PlanChange::SeatChange).returns(T::Boolean) }
  def can_purchase_seats?(target, seat_change)
    target.has_valid_payment_method? || seat_change_covered_by_coupon?(target, seat_change)
  end

  sig { params(target: ::Billing::Types::Account).returns(T::Boolean) }
  def can_manage_seats?(target)
    return false unless target.is_a?(Business)
    return false if target.downgraded_to_free_plan? ||
      target.dunning? ||
      target.has_unlimited_seats?

    !!target.eligible_for_self_serve_payment?
  end

  sig { params(target: User, seat_change: ::Billing::PlanChange::SeatChange).returns(T::Boolean) }
  def seat_change_covered_by_coupon?(target, seat_change)
    target.has_an_active_coupon? &&
      seat_change.payment_amount == Billing::Money.new(0)
  end

  sig { params(target: User).returns(T::Array[Repository]) }
  def lfs_repository_list(target)
    @lfs_repository_list ||= T.let(Platform::Loaders::LfsRepositories.load(target.id).sync, T.nilable(T::Array[Repository]))
  end

  sig { params(target: User).returns(T::Array[{ repo: Repository, bandwidth_b: Integer }]) }
  def lfs_bandwidth_breakdown(target)
    repository_list = lfs_repository_list(target)
    lfs_networks = Platform::Loaders::LfsNetworksByUsage.load(target.id).sync
    mapped = repository_list.map do |repo|
      bw = lfs_networks && lfs_networks[repo.network_id]
      {
        repo: repo,
        bandwidth_b: (bw&.dig(:bandwidth_down) || 0) * 1.gigabyte
      }
    end
    mapped.sort_by! { |item| item[:bandwidth_b] }.last(LFS_REPOSITORY_LIMIT).reverse
  end

  sig { params(target: User).returns(T::Array[{ repo: Repository, disk_usage_b: Integer }]) }
  def lfs_storage_breakdown(target)
    repository_list = lfs_repository_list(target)
    lfs_disk_usage = Platform::Loaders::NetworkLfsDiskUsage.new.fetch(repository_list.map(&:network_id))
    mapped = repository_list.map do |repo|
      {
        repo: repo,
        disk_usage_b: lfs_disk_usage[repo.network_id] || 0
      }
    end
    mapped.sort_by! { |item| item[:disk_usage_b] }.last(LFS_REPOSITORY_LIMIT).reverse
  end

  # Public: Boolean if this is an organization is on per-seat pricing and has limited seats
  # TODO: We will need to change this to support CFB
  sig { params(target: ::Billing::Types::Account).returns(T::Boolean) }
  def copilot_enabled_for_user?(target)
    !GitHub.enterprise? && target.user?
  end

  # Public: Returns true if we should link to the pending invitations page instead of showing them in a dialog
  sig { params(target: Organization).returns(T::Boolean) }
  def use_pending_invitations_link_instead_of_dialog?(target)
    pending_non_manager_invitations_count(target) > PENDING_INVITATION_DIALOG_LIST_LIMIT
  end

  # Public: Returns the number of pending non-manager invitations for the target
  sig { params(target: Organization).returns(Integer) }
  def pending_non_manager_invitations_count(target)
    @_pending_non_manager_invitations ||= T.let({}, T.nilable(T::Hash[Integer, Integer]))
    @_pending_non_manager_invitations[target.id] ||= target.pending_non_manager_invitations.size
  end

  # Internal: Whether or not we should show the synchronous payment collection upgrade page.
  sig { returns(T::Boolean) }
  def should_show_synchronous_payment_collection_upgrading_page?
    !Billing::JobStatus.find(synchronous_payment_collection_job_status.id)&.pending?
  end

  # Internal: The JobStatus used to track the synchronous payment collection upgrade progress.
  sig { returns(JobStatus) }
  def synchronous_payment_collection_job_status
    prefix = Billing::JobStatus::SYNCHRONOUS_PAYMENT_COLLECTION_JOB_STATUS_PREFIX
    id = "#{prefix}:#{SecureRandom.uuid}"
    @_synchronous_payment_collection_job_status ||= T.let(Billing::JobStatus.create(id:), T.nilable(JobStatus))
  end

  # Internal: Whether or not we show a warning message about the payment form in a dev environment.
  sig { params(request_url: String).returns(T::Boolean) }
  def show_development_payment_form_warning?(request_url)
    return false if !(Rails.env.development? || Rails.env.test?)

    # check if the request url does not start with "admin." or end with ":".
    # if it does, then the payment form will fail to load as it can only load on
    # http://github.localhost/*
    is_github_localhost = request_url.match(/(?<!admin\.)github.localhost(?!:)/)

    is_preview_host = request_url.include?("preview.app.github.dev")

    !is_github_localhost && !is_preview_host
  end

  # Public: Returns whether the data packs of a given user or org can be changed through Stafftools.
  sig { params(target: User).returns(T::Boolean) }
  def subscription_data_packs_can_be_changed?(target)
    return true unless target.delegate_billing_to_business?
    return true if target.business.invoiced?
    false
  end

  sig { params(target: ::Billing::Types::Account, product: Symbol).returns(T::Boolean) }
  def product_moved_to_vnext?(target, product)
    config = BillingPlatformEnabledProduct.find_by(customer_id: target.customer&.id)
    return false if config.nil?

    product_moved = case product
    when :actions
      config.actions?
    when :lfs
      config.git_lfs?
    when :copilot_for_business
      config.copilot?
    else
      false
    end

    return !!(target.customer&.billed_via_billing_platform? && product_moved) if target.business?
    false
  end

  sig { returns(String) }
  def apple_app_store_subscriptions_url
    "https://apps.apple.com/account/subscriptions"
  end

  sig { returns(String) }
  def google_app_store_subscriptions_url
    "https://play.google.com/store/account/subscriptions"
  end

  sig { params(entity: ::Billing::Types::Account).returns(String) }
  def tax_disclaimer(entity)
    customer = entity.customer
    return "" unless customer&.in_taxable_country?

    disclaimers = {
      "US" => "U.S. Sales tax is not included in the amounts shown above.",
      "JP" => "Japanese consumption tax (JCT) is not included in the amounts shown above.",
    }
    tax_country = customer.country_code_for_tax_purposes

    disclaimers[tax_country] || ""
  end

  sig { params(this_business: Business).returns(Float) }
  def ghe_volume_license_spend(this_business)
    seats = this_business.purchased_enterprise_licenses
    manage_seats = ::Business::ManageSeats.new(business: this_business, new_seats: seats)

    # return the float representation of the seat price instead of returning a formatted currency
    # so we can align with our front-end money formatter
    manage_seats.current_price.to_f
  end

  sig { params(this_business: Business). returns(Float) }
  def ghas_volume_license_spend(this_business)
    if !this_business.advanced_security_purchased?
      return 0.0
    end
    ghas_seats = this_business.advanced_security_license.seats
    if ghas_seats.zero?
      return 0.0
    end

    monthly_ghas_base_price = 49.0
    formatted_base_price = Billing::Money.new((monthly_ghas_base_price * 100).to_d).to_f # is this ok ?
    (ghas_seats * formatted_base_price).to_f
  end

  sig { params(this_business: Business).returns(Float) }
  def ghas_volume_license_spend_yearly(this_business)
    ghas_volume_license_spend(this_business) * 12
  end

  class VolumeLicenseData < T::Struct
    prop :IsSeparateDisplayCard, T::Boolean
    prop :gheAndGhas, T::Hash[Symbol, T.untyped]
    prop :ghe, T::Hash[Symbol, T.untyped]
    prop :ghas, T::Hash[Symbol, T.untyped]
    prop :IsInvoiced, T::Boolean
  end

  sig { params(this_business: Business).returns(BillingSettingsHelper::VolumeLicenseData) }
  def volume_license_spend(this_business)
    data = VolumeLicenseData.new(IsSeparateDisplayCard: false, gheAndGhas: { period: "", spend: 0.0 }, ghe: { period: "", spend: 0.0 }, ghas: { period: "", spend: 0.0 }, IsInvoiced: this_business.invoiced?)
    if this_business.advanced_security_purchased?
      if this_business.invoiced?
        data.gheAndGhas = { period: "per year", spend: ghe_volume_license_spend(this_business) + ghas_volume_license_spend_yearly(this_business) }
      else
        # self-serve businesses
        if this_business.monthly_plan?
          data.gheAndGhas = { period: "per month", spend: ghe_volume_license_spend(this_business) + ghas_volume_license_spend(this_business) }
        else
          data.IsSeparateDisplayCard = true
          data.ghe = { period: "per year", spend: ghe_volume_license_spend(this_business) }
          data.ghas = { period: "per month", spend: ghas_volume_license_spend(this_business) }
        end
      end
    else
      data.gheAndGhas = { period: this_business.monthly_plan? ? "per month" : "per year", spend: ghe_volume_license_spend(this_business) }
    end
    data
  end

  sig { params(entity: ::Billing::Types::Account).returns(T::Boolean) }
  def billing_coding_agent_enabled?(entity)
    return false unless entity.feature_enabled?(:billing_coding_agent_enabled)

    if entity.is_a?(Business)
      return Copilot::Business.new(entity).copilot_plan_enterprise?
    end

    if entity.is_a?(User)
      return Copilot::User.new(entity).has_pro_plus_subscription?
    end
    false
  end

  sig { params(entity: ::Billing::Types::Account).returns(T::Boolean) }
  def billing_spark_enabled?(entity)
    entity.feature_enabled?(:copilot_workbench_user_limits)
  end
end
