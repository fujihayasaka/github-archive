# typed: strict
# frozen_string_literal: true

module Business::BillingDependency
  extend T::Sig
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { Business }

  include Billing::MeteredBillable
  include Billing::Contact::AbstractContactDependency
  include Configurable::SeatLimitForUpgrades
  include Configurable::SelfServeInvoicePreference
  include GitHub::Memoizer
  include Scientist
  include Billing::Interfaces::BillableEntity

  delegate :metered_billing_eligible?, :codespaces_eligible?, to: :plan, prefix: true

  delegate :auto_pay_reasons,
    :reseller_customer?,
    :billing_transactions,
    :zuora_account,
    :payment_method,
    :plan_subscription,
    :subscription_items,
    :active_subscription_items,
    :autopay_disabled_by_india_rbi?,
    :disabled_reasons,
    :billing_disabled_by_authorization_failure?,
    :manual_dunning_period,
    :pending_plan_changes,
    :incomplete_pending_plan_changes,
    :pending_subscription_item_changes,
    :shipping_contact,
    :reload_plan_subscription,
    :billed_via_billing_platform?,
    :eligible_for_sales_tax?,
    :async_plan_subscription, to: :customer, allow_nil: true

  delegate :zuora_account_id, to: :customer, prefix: true, allow_nil: true

  delegate :external_subscription_type, to: :plan_subscription, allow_nil: true

  delegate :education_bundle?, to: :sales_serve_plan_subscription, allow_nil: true

  sig do
    override.params(
      feature: Symbol,
      visibility: T.nilable(T.any(Symbol, String)),
      org: T::Boolean,
      feature_flag: T.nilable(T.any(Symbol, String)),
      fallback_to_free: T::Boolean
    ).returns(T::Boolean)
  end
  def plan_supports?(feature, visibility: nil, org: false, feature_flag: nil, fallback_to_free: false)
    plan.supports?(feature, visibility: visibility, org: false, feature_flag: feature_flag)
  end

  sig { returns(T::Boolean) }
  def over_plan_limit?
    false
  end

  included do
    T.bind(self, T.class_of(Business))

    belongs_to :customer

    has_many :plan_subscriptions, through: :customer, source: :plan_subscriptions

    scope :with_active_azure_subscription, -> {
      business_ids_with_active_enterprise_agreements = Licensing::EnterpriseAgreement.active.pluck("DISTINCT business_id")
      where(
        id: business_ids_with_active_enterprise_agreements,
        customer_id: Customer.where.not(azure_subscription_id: nil).pluck(:id),
      )
    }

    scope :on_paid_plan, -> { GitHub.enterprise? ? none : where(downgraded_at: nil) }

    after_update :update_external_subscription, unless: :skip_update_external_subscription
    attr_accessor  :skip_update_external_subscription

    after_commit :run_scheduled_subscription_synchronization
    before_destroy :destroy_dependent_plan_subscription
    before_destroy :destroy_dependent_manual_dunning_period
  end

  class_methods do
    extend T::Sig
    # Public: Businesses who need to be billed for their services as of today
    sig { returns(ActiveRecord::Relation) }
    def needs_billed
      T.bind(self, T.class_of(Business))

      select("businesses.*").
        joins(<<-SQL).
              LEFT OUTER JOIN customers ON businesses.customer_id = customers.id
              LEFT OUTER JOIN plan_subscriptions ON businesses.customer_id = plan_subscriptions.customer_id
              LEFT OUTER JOIN payment_methods ON payment_methods.customer_id = businesses.customer_id
          SQL
      where(
        "customers.billing_type = 'card'
            AND (customers.billing_end_date IS NULL OR customers.billing_end_date <= ?)
            AND businesses.downgraded_at IS NULL
            AND (plan_subscriptions.zuora_subscription_number IS NULL
              OR plan_subscriptions.zuora_subscription_number IS NOT NULL
              AND (payment_methods.payment_token IS NULL
                OR payment_methods.payment_token = 'payment-token-cleared'))
            AND plan_subscriptions.apple_transaction_id IS NULL",
        GitHub::Billing.today.to_formatted_s(:db),
      )
    end
  end

  # Plan durations. Businesses support both yearly and monthly plans.
  YEARLY_PLAN = "year"
  MONTHLY_PLAN = "month"

  BILLING_ATTEMPTS_LIMIT = 3

  # The maximum number of days passed over all billing attempts.
  #
  # 0th day + 7 days (1st retry) + 7 additional days (2nd retry)
  # = 14 day dunning period.
  DUNNING_DAYS = T.let(14.days, ActiveSupport::Duration)

  sig { returns(String) }
  def billing_account_type
    "Enterprise"
  end

  sig do
    params(
      reason: T.any(String, Symbol),
      actor: T.nilable(User)
    ).returns(T.nilable(GitHub::Billing::Result))
  end
  def disable_auto_pay!(reason, actor: nil)
    T.bind(self, ::Business)

    Billing::AutoPay.disable! \
      account: self,
      actor: actor,
      reason: reason
  end

  # Public: Checks if the given user can administer subscription items owned by this account.
  # This includes cancelling and editing subscription items.
  sig { params(user: T.nilable(User), subscribable_type: T.untyped, is_stafftools_action: T::Boolean).returns(T::Boolean) }
  def subscription_items_adminable_by?(user, subscribable_type: nil, is_stafftools_action: false)
    T.bind(self, Business)
    adminable_by?(user) || (is_stafftools_action && user&.site_admin?)
  end

  # Public: Returns whether a user is eligible to use/sign up for a free trial on a product_uuid.
  #
  # An optional subscription item can be provided to exclude the item from the checks. For example, when the
  # subscription item is first created, we don't want to check against it since it may be the first subscription item
  # and in that case the user is eligible for the free trial.
  sig do
    params(
      product: T.any(Billing::ProductUUID, T.nilable(Marketplace::Listing), SponsorsTier),
      excluded_subscription_item: T.nilable(Billing::SubscriptionItem)
    ).returns(T::Boolean)
  end
  def eligible_for_free_trial_on?(product:, excluded_subscription_item: nil)
    subscription_items = async_plan_subscription.sync.try(:async_subscription_items)&.sync || []
    return true if subscription_items.empty?

    if product.is_a?(Billing::ProductUUID)
      product.eligible_for_free_trial?(subscription_items: subscription_items, excluded_subscription_item: excluded_subscription_item)
    elsif product.is_a?(Marketplace::Listing)
      # At this point, subscription_items is an array. We prefill the association to grab its subscribables to avoid an N+1 query.
      GitHub::PrefillAssociations.prefill_associations(subscription_items, :subscribable)
      items = subscription_items.select do |item|
        item.subscribable_Marketplace_ListingPlan? && item.subscribable.marketplace_listing_id == product.id
      end
      items = items.reject { |item| item == excluded_subscription_item } if excluded_subscription_item
      items.none?(&:disqualifies_for_free_trial?)
    else # SponsorsTier
      false
    end
  end

  sig { returns(T::Boolean) }
  def business_entity?
    true
  end

  # Public: Enable or disable based on billing state.
  sig { void }
  def enable_or_disable!
    should_disable? ? disable! : enable!
  end

  # Should the Business be disabled if it's not already?
  sig { returns(T::Boolean) }
  def should_disable?
    return false if never_disable?
    return true if trial_expired?
    (over_billing_attempts_limit? && dunning_period_expired?) || !!(disabled_reasons&.any?)
  end

  # Public: Fetch the constant BILLING_ATTEMPTS_LIMIT
  sig { returns(Integer) }
  def billing_attempts_limit
    BILLING_ATTEMPTS_LIMIT
  end

  # Public: Returns true when a user has exceeded the billing attempts limit
  sig { returns(T::Boolean) }
  def over_billing_attempts_limit?
    # NB: Prevents first time payers from getting 2 grace period
    if never_successfully_billed?
      billing_attempts > 0
    else
      billing_attempts >= BILLING_ATTEMPTS_LIMIT
    end
  end

  sig { returns(T::Boolean) }
  def under_billing_attempts_limit?
    billing_attempts < BILLING_ATTEMPTS_LIMIT
  end

  # Has the Business never successfully been billed?
  sig { returns(T::Boolean) }
  def never_successfully_billed?
    billed_on.nil? || billing_transactions.successful.paid.count.zero?
  end

  # Internal: Has the 2-week dunning period for the Business elapsed?
  sig { returns(T::Boolean) }
  def dunning_period_expired?
    return true if never_successfully_billed?
    GitHub::Billing.today >= T.must(billed_on) + T.unsafe(DUNNING_DAYS)
  end

  # Should the Business never be disabled?
  sig { returns(T::Boolean) }
  def never_disable?
    invoiced? || trial_conversion_initiated?
  end

  # Public: Enables the Business.
  #
  # Currently this upgrades the Business to the business_plus plan
  # and sets the business to be billed via Azure if metered.
  sig { void }
  def enable!
    upgrade_to_business_plus_plan if disabled?
  end

  # Public: Enables billing for the Business.
  #
  # If no plan subscription is created, we update the billing end date to be either:
  # 1. The day before the next billing date
  # 2. The day before the next lock date
  sig { void }
  def unlock_billing!
    customer = self.customer
    return unless customer

    unless plan_subscription
      customer.update \
        billing_end_date: [T.must(next_billing_date) - 1.day, relock_on - 1.day].max
    end

    customer.update!(billing_attempts: 0)
    enable! unless trial?
  end

  # Public: Will this business be relocked if unlocked with unlock_billing!
  sig { returns(T::Boolean) }
  def will_relock?
    return false unless billed_on = self.billed_on

    billed_on < relock_on && over_billing_attempts_limit?
  end

  # Public: Date this business will be relocked if unlocked with unlock_billing!
  sig { returns(Date) }
  def relock_on
    GitHub::Billing.today + 2.days
  end

  # Public: Is the Business considered to be enabled?
  sig { returns(T::Boolean) }
  def enabled?
    !downgraded_to_free_plan?
  end

  # Public: Disables the Business.
  #
  # Currently this just downgrades the Business to the free plan.
  sig { params(reason: T.nilable(Billing::Public::BillingDisabledReasons)).void }
  def disable!(reason: nil)
    if enabled?
      downgrade_to_free_plan

      if reason.present?
        customer&.update_disabled_reasons(reason)
      end
    end
  end

  # Public: Schedules cancellation of all associated subscription items.
  #
  # force - Boolean indicating whether to cancel the subscription items
  #         immediately. Defaults to false.
  # skip_sync - Boolean indicating whether to skip synchronizing with the billing system.
  # subscribable_type - String class name of the subscribable, if any
  #
  # Returns an Array of Billing::Public::SubscriptionItems::ResultStruct
  sig { params(force: T::Boolean, skip_sync: T::Boolean, subscribable_type: T.nilable(String)).returns(T::Array[Billing::Public::SubscriptionItems::ResultStruct]) }
  def cancel_subscription_items!(force: false, skip_sync: false, subscribable_type: nil)
    active_paid_subscription_items = active_subscription_items.select(&:subscribable_paid?)
    return [] unless active_paid_subscription_items.any?

    actor = User.find_by(id: GitHub.context[:actor_id]) || User.ghost
    active_paid_subscription_items.map do |item|
      next if subscribable_type && item.subscribable_type != subscribable_type
      item.cancel!(force: force, skip_sync: skip_sync, actor: actor)
    end.compact
  end

  # Public: Schedules cancellation of all paid subscription items associated with a business owned organization.
  #         This is only used for Marketplace subscription items for now.
  #
  # organization - Organization to cancel subscription items for.
  # actor - (Optional) User responsible for the cancellation, if relevant.
  #
  # Returns an Array of Billing::Public::SubscriptionItems::ResultStruct
  sig { params(organization: Organization, actor: T.nilable(User)).returns(T::Array[Billing::Public::SubscriptionItems::ResultStruct]) }
  def cancel_member_organization_subscription_items!(organization, actor: nil)
    subscription_items = active_subscription_items&.where(organization_id: organization.id) || []

    actor = actor || User.ghost
    results = subscription_items.map do |item|
      item.cancel!(force: true, skip_sync: true, actor: actor)
    end.compact

    GitHub::PrefillAssociations.prefill_associations(subscription_items, :plan_subscription)
    plan_subscriptions = subscription_items.filter_map(&:plan_subscription).uniq
    plan_subscriptions.each { |plan_sub| plan_sub.synchronize_later }

    results
  end

  # Public: Is the subscription a Zuora subscription?
  sig { returns(T::Boolean) }
  def zuora_subscription?
    plan_subscription.present? && plan_subscription.zuora_subscription_number?
  end

  # Public: Returns the Self-serve or Sales-serve plan subscription depending
  # on which is used for the Business
  sig { returns(T.nilable(T.any(Billing::PlanSubscription, Billing::SalesServePlanSubscription))) }
  def active_plan_subscription
    if self_serve_payment?
      plan_subscription
    else
      sales_serve_plan_subscription
    end
  end

  # Public: Returns the plan subscription for this business or creates a new one in the event
  # the customer hasn't entered their payment details during the trial period.
  sig { returns(T.any(Billing::PlanSubscription, Billing::SalesServePlanSubscription)) }
  def get_plan_subscription_or_null_plan
    active_plan_subscription || ::Billing::PlanSubscription.new(customer: self.customer)
  end

  # Public: Returns this User's active SubscriptionItem for a Marketplace listing.
  #
  # marketplace_listing_or_id - a Marketplace::Listing or its ID
  # organization - an Organization
  sig do
    params(
      marketplace_listing_or_id: T.any(Marketplace::Listing, Integer),
      organization: T.nilable(Organization)
    ).returns(T.nilable(Billing::SubscriptionItem))
  end
  def subscription_item_for_marketplace_listing(marketplace_listing_or_id, organization: nil)
    return unless self_serve_payment?

    active_subscription_items.for_marketplace_listing(marketplace_listing_or_id).where(organization_id: organization&.id).first
  end

  # Public: Returns a list of Organizations that have an active subscription to the Marketplace
  # listing with the given ID, and for which this User can administer those subscriptions.
  sig { params(listing_id: Integer, user: User).returns(T::Array[Organization]) }
  def organizations_for_marketplace_listing(listing_id, user)
    return [] unless owner?(user)
    return [] unless self_serve_payment?

    subscription_items_by_org_id = Billing::SubscriptionItem.joins(:plan_subscription)
      .merge(Billing::PlanSubscription.for_business(self)).active.for_marketplace_listing(listing_id)
      .includes(:plan_subscription)
      .each_with_object({}) do |item, hash|
        org_id = item.organization_id
        hash[org_id] = item
      end

    promises = subscription_items_by_org_id.values.map { |item| item.async_adminable_by?(user) }
    Promise.all(promises).sync

    self.organizations.select do |org|
      item = subscription_items_by_org_id[org.id]
      item&.adminable_by?(user)
    end.to_a
  end

  # Public: Is the Business considered to be disabled?
  sig { returns(T::Boolean) }
  def disabled?
    downgraded_to_free_plan?
  end

  sig { returns(Integer) }
  def billing_attempts
    customer&.billing_attempts || 0
  end

  # Public: Reset user's billing attempts to 0.
  sig { void }
  def reset_billing_attempts
    customer&.update!(billing_attempts: 0)
  end

  # Public: Increment the billing attempts for the Business' Customer.
  sig { void }
  def increment_billing_attempts
    customer&.increment!(:billing_attempts)
  end

  # Public: Set the billing attempts for the User.
  sig { params(attempts: Integer).void }
  def set_billing_attempts(attempts)
    customer&.update_column(:billing_attempts, attempts)
  end

  # Public: Returns true if we have attempted billing on the account but
  # failed, otherwise false.
  sig { returns(T::Boolean) }
  def dunning?
    billing_attempts > 0
  end

  # Public: Returns true if the Business has 3 or more billing attempts,
  # otherwise false.
  sig { returns(T::Boolean) }
  def unable_to_bill?
    billing_attempts >= BILLING_ATTEMPTS_LIMIT
  end

  # Public: Is the Business in billing trouble?
  sig { returns(T::Boolean) }
  def billing_trouble?
    unable_to_bill? && payment_amount > 0
  end

  # Public: The manual payment due date for the Business.
  #
  # Currently only applies to Businesses that have been placed in manual dunning.
  sig { returns(T.nilable(Date)) }
  def manual_payment_due_date
    manual_dunning_period&.due_date&.to_date
  end

  # Public: Returns true if the Business is in manual dunning, otherwise false.
  sig { returns(T::Boolean) }
  def manual_dunning?
    !!(manual_dunning_period.present? && balance.positive?)
  end

  # Public: Is this business billed by invoice?
  sig { override.returns(T::Boolean) }
  def invoiced?
    async_invoiced?.sync
  end

  sig { returns(Promise[T::Boolean]) }
  def async_invoiced?
    return Promise.resolve(T.let(false, T::Boolean)) if GitHub.single_business_environment?
    async_customer.then do |customer|
      !!customer&.invoiced?
    end
  end

  # Public: Is this business billed by a self-serve payment method?
  sig { returns(T::Boolean) }
  def self_serve_payment?
    async_self_serve_payment?.sync
  end

  sig { returns(Promise[T::Boolean]) }
  def async_self_serve_payment?
    return Promise.resolve(T.let(false, T::Boolean)) unless GitHub.billing_enabled?
    async_customer.then do |customer|
      !!customer&.self_serve_payment?
    end
  end

  # Public: Is this business sales managed?
  sig { returns(T::Boolean) }
  memoize def sales_managed?
    invoiced?
  end

  # Public: Enable self-serve payments on a business. For a business with a Zuora account already,
  # update the Zuora account details to make sure that the Zuora account handles self-serve payments
  # appropriately. Also, create its Zuora subscription in the process.
  sig { params(skip_billing: T::Boolean, plan_duration: String).void }
  def enable_self_serve_payments(skip_billing: false, plan_duration: "year")
    return unless GitHub.billing_enabled?
    return unless customer = self.customer
    return if has_commercial_interaction_restriction?
    update!(plan_duration: plan_duration)

    old_billing_type = customer.billing_type
    customer.update!(billing_type: Customer::BILLING_TYPE_CARD)
    billing_type_changed = billing_type_changed?(old_billing_type: old_billing_type.to_s)

    create_billing_customer_and_plan_subscription(billing_type_changed: billing_type_changed) unless skip_billing
    sync_all_organization_billing_settings

    instrument_change_billing_type({ old_billing_type: old_billing_type }) if billing_type_changed
  end

  # Public: Creates Zuora customer and subscription.
  sig { params(billing_type_changed: T::Boolean).void }
  def create_billing_customer_and_plan_subscription(billing_type_changed: false)
    T.bind(self, Business)

    if billing_type_changed || customer&.zuora_account_id.blank?
      ::Billing::CreateCustomer.perform(self, details: { omit_billing_info: true })
    end

    if customer&.plan_subscription.blank?
      customer&.create_plan_subscription!
    end
  end

  # Public: Switches billing of a business from self-serve to invoiced payments. Also, updates plan duration, and
  # syncs billing settings for all organizations owned by the business, switching them from self-serve to invoiced
  # payments in the process.
  sig { void }
  def switch_to_invoiced_payments
    return unless GitHub.billing_enabled?
    return unless customer = self.customer
    return if has_commercial_interaction_restriction?

    transaction do
      old_billing_type = customer.billing_type
      customer.update!(billing_type: Customer::BILLING_TYPE_INVOICE, billing_attempts: 0)
      update!(plan_duration: YEARLY_PLAN) unless yearly_plan?
      sync_all_organization_billing_settings(switch_org_billing_to_invoice: true)

      instrument_change_billing_type({ old_billing_type: old_billing_type })
    end
  end

  # Public: The billing type of a business.
  sig { returns(T.nilable(String)) }
  def billing_type
    async_billing_type.sync
  end

  sig { returns(Promise[T.nilable(String)]) }
  def async_billing_type
    return Promise.resolve(T.let(nil, T.nilable(String))) unless GitHub.billing_enabled?
    async_customer.then do |customer|
      customer&.billing_type
    end
  end

  # Public: Are decisions about this business's plan and settings made by a
  #         business owner? If not, the business is managed by our sales team.
  sig { returns(T::Boolean) }
  def can_self_serve?
    return false if GitHub.single_business_environment?
    can_self_serve
  end

  sig { returns(T::Boolean) }
  def bill_cycle_day_editable_in_stafftools?
    eligible_for_self_serve_payment?
  end

  # Public: Check if a business is eligible to use the self-serve payment feature. Returns false on
  # environment where billing is disabled, or if the business is not set to use a self-serve
  # payment method. Otherwise, returns true.
  sig { returns(T::Boolean) }
  def eligible_for_self_serve_payment?
    return false unless GitHub.billing_enabled?
    return true if metered_plan?
    return false unless self_serve_payment?
    true
  end

  sig { returns(T::Boolean) }
  def eligible_for_nonmetered_github_plan?
    !(organization_upgrade_initiated? || creation_initiated_from_coupon? || metered_ghe?)
  end

  sig { returns(T::Boolean) }
  def has_self_serve_advanced_security?
    advanced_security_purchased_for_entity? && potentially_trial_or_purchase_advanced_security? && advanced_security_subscription_item.present?
  end

  # Public: Schedule and immediately run a job to synchronize this user's plan
  # information with the third party provider if there are changes that need to be synchronized
  sig { params(kwargs: T.untyped).void }
  def update_external_subscription!(**kwargs)
    update_external_subscription(**kwargs)
    run_scheduled_subscription_synchronization
  end

  # Public: Schedule and immediately run a job to synchronize this user's plan
  #         creates an external subscription if not present
  # See User#create_or_update_external_subscription for more information
  sig { params(kwargs: T.untyped).void }
  def create_or_update_external_subscription!(**kwargs)
    create_or_update_external_subscription(**kwargs)
    run_scheduled_subscription_synchronization
  end


  # Public: Schedule and immediately run a job to synchronize this user's plan
  #         creates an external subscription if not present
  #         This method will not enqueue more synchronization jobs on subsequent updates
  #         unless one of the update_external_subscription methods are explicitly invoked.
  sig { params(kwargs: T.untyped).void }
  def create_or_update_external_subscription_once!(**kwargs)
    create_or_update_external_subscription(**kwargs)
    run_scheduled_subscription_synchronization(one_time_only: true)
  end

  # Public: Returns whether the business has been downgraded to a free plan.
  sig { returns(T::Boolean) }
  def downgraded_to_free_plan?
    return false unless GitHub.billing_enabled?
    downgraded_at.present?
  end

  # Public: Downgrade a dotcom business account to a free plan. This changes the plan of the
  # business to free, and also changes the plan of all organizations in the business to free too.
  # Also disables SAML for the Business if it was downgraded due to an expired or cancelled trial.
  sig { void }
  def downgrade_to_free_plan
    return unless GitHub.billing_enabled?
    return if downgraded_to_free_plan?  # Don't downgrade if already downgraded
    update_attribute :downgraded_at, GitHub::Billing.now
    saml_provider = self.saml_provider
    saml_provider.destroy if saml_provider.present? && (trial_expired? || trial_cancelled?)

    # Disable SSH CA requirements for all organizations that lose access to the feature
    orgs_with_requirement = organizations.where(id: SshCertificateAuthority.cert_required_org_ids(T.cast(self, Business)))
    orgs_with_requirement.each do |org|
      org.disable_ssh_certificate_requirement(nil) if !SshCertificateAuthority.eligible_for_feature?(org)
    end
  end

  # Public: Upgrade a dotcom business account to a business plus plan. This changes the plan of a
  # business and all organizations in the business, that had initially been downgraded to free,
  # back to the business plus plan.
  sig { void }
  def upgrade_to_business_plus_plan
    return unless GitHub.billing_enabled?
    return unless downgraded_to_free_plan?  # Don't upgrade if it was never downgraded
    update_attribute :downgraded_at, nil
    restore_deleted_pages
  end

  # Public: Checks if this Business is currently in the process of being upgraded from an organization.
  # This returns true if the Business has been created from a self-serve Free/Team organization, and payment
  # is not yet processed.
  sig { returns(T::Boolean) }
  def upgrading_from_organization?
    organization_upgrade_initiated? || organization_upgrade_purchase_initiated?
  end

  # Public: Checks if this Business is currently in the process of being created from a coupon.
  # This returns true if the Business is being created from a coupon, and the redemption/payment is not yet complete.
  sig { returns(T::Boolean) }
  def being_created_from_coupon?
    creation_initiated_from_coupon? || creation_from_coupon_purchase_initiated?
  end

  # Public: Instrument change of billing plan for an enterprise account.
  sig { params(payload: T::Hash[T.untyped, T.untyped]).void }
  def instrument_change_billing_plan(payload = {})
    payload = payload.presence || plan_change_payload
    GitHub.instrument("account.plan_change", payload)
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def plan_change_payload
    actor = User.find_by(id: GitHub.context[:actor_id]) || User.ghost

    old_plan = if saved_change_to_downgraded_at?
      downgraded_to_free_plan? ? GitHub::Plan.business_plus(account: self).name : GitHub::Plan.free.name
    else
      plan_name
    end

    payload = { business: self }
    payload.update \
      old_plan: old_plan,
      plan: downgraded_to_free_plan? ? GitHub::Plan.free.name : GitHub::Plan.business_plus(account: self).name,
      old_plan_duration: plan_duration_before_last_save,
      plan_duration: plan_duration,
      old_seats: seats,
      seats: seats,
      old_data_packs: data_packs,
      asset_packs: data_packs,
      tos_sha: TosAcceptance.current_sha

    if actor&.site_admin?
      payload.update GitHub.guarded_audit_log_staff_actor_entry(actor)
    else
      payload.update actor: actor
    end

    payload
  end

  # Public: Which plan the business is on.
  #
  # - On GitHub Enterprise the global business is on the Enterprise plan.
  # - On GitHub.com all businesses are on the Business Plus plan, except for downgraded
  #   business accounts, which are on a free plan.
  #
  sig { returns(GitHub::Plan) }
  def plan
    @plan ||= T.let(
      if GitHub.enterprise?
        GitHub::Plan.default_plan account: self
      else
        downgraded_to_free_plan? ? GitHub::Plan.free(account: self) : GitHub::Plan.business_plus(account: self)
      end, T.nilable(GitHub::Plan)
    )
  end

  # Public
  sig { override.returns(T::Boolean) }
  def free_plan?
    plan.free? && !plan.coupon?
  end

  sig { override.returns(T::Boolean) }
  def paid_plan?
    plan.paid?
  end

  # Public: Which plan the business is on.
  #
  # Exists to keep parity with User and Organization having #async_plan, for use loading relations efficiently.
  sig { returns(Promise[GitHub::Plan]) }
  def async_plan
    Promise.resolve(plan)
  end

  sig { returns(String) }
  def plan_name
    plan.name
  end

  # Public: The DateTime the business signed up for their current plan
  sig { returns(T.nilable(ActiveSupport::TimeWithZone)) }
  def plan_effective_at
    return enterprise_agreement_effective_at if billed_through_azure_subscription?
    zuora_billing_start_datetime || GitHub::Billing.now
  end

  # Public: When will this business be invoiced next.
  sig { returns(T.nilable(Date)) }
  def billed_on
    return unless billing_term_ends_on
    billing_term_ends_on + 1.day
  end

  sig { params(user: User).returns(T::Boolean) }
  def direct_or_team_member?(user)
    organizations.any? { |org| org.direct_or_team_member?(user) }
  end

  # Public: Returns the aggregated asset status across all owned organizations.
  #
  # The resulting Hash looks like this:
  #
  # {
  #   asset_packs: 1,
  #   bandwidth_usage: 15.2,
  #   bandwidth_quota: 50.0,
  #   storage_usage: 36.4,
  #   storage_quota: 50.0
  # }
  sig { returns(T::Hash[Symbol, Billing::Types::Numeric]) }
  def aggregated_asset_status
    @aggregated_asset_status ||= T.let(
      begin
        status = {
          asset_packs: 0,
          bandwidth_usage: 0.0,
          bandwidth_quota: 0.0,
          storage_usage: 0.0,
          storage_quota: 0.0,
        }
        async_organizations.then do |organizations|
          organizations.to_a.each do |org|
            org_asset_status = org.async_asset_status.sync || org.build_asset_status
            if org_asset_status
              status[:asset_packs] += org_asset_status.asset_packs
              status[:bandwidth_usage] += org_asset_status.bandwidth_usage
              status[:bandwidth_quota] += org_asset_status.bandwidth_quota
              status[:storage_usage] += org_asset_status.storage_usage
              status[:storage_quota] += org_asset_status.storage_quota
            end
          end
          status
        end.sync
      end, T.nilable(T::Hash[Symbol, Billing::Types::Numeric])
    )
  end

  # Public: Returns bandwidth usage as a percentage.
  sig { returns(Integer) }
  def bandwidth_usage_percentage
    return 0 if aggregated_asset_status[:bandwidth_quota] == 0
    percent = (aggregated_asset_status[:bandwidth_usage].to_f / aggregated_asset_status[:bandwidth_quota].to_f).round(2)
    (percent * 100).to_i
  end

  # Public: Returns storage usage as a percentage.
  sig { returns(Integer) }
  def storage_usage_percentage
    return 0 if aggregated_asset_status[:storage_quota] == 0
    percent = (aggregated_asset_status[:storage_usage].to_f / aggregated_asset_status[:storage_quota].to_f).round(2)
    (percent * 100).to_i
  end

  # Public: Sets up an organization to have it billing managed by a business.
  sig { params(organization: Organization).void }
  def migrate_organization_to_business_billing(organization)
    T.bind(self, Business)

    ::Billing::BusinessOrganizationBillingConverter.perform \
      business: self,
      organization: organization
  end

  # Public: Have any of the synced billing settings changed?
  sig { returns(T::Boolean) }
  def synced_billing_settings_changed?
    watched = %w(downgraded_at seats billing_term_ends_at terms_of_service_type terms_of_service_company_name)
    (saved_changes.keys & watched).any?
  end

  # Public: Sync the billing settings of all member orgs within the enterprise.
  #
  # Enqueues SyncBusinessOrganizationBillingSettingsJob to perform the
  # billing settings sync in the background.
  sig { params(enterprise_purchase: T::Boolean, switch_org_billing_to_invoice: T::Boolean).void }
  def sync_all_organization_billing_settings(enterprise_purchase: false, switch_org_billing_to_invoice: false)
    T.bind(self, Business)

    return unless GitHub.billing_enabled?
    return if self.organizations.empty?
    return if trial? || trial_cancelled?

    if orphaned_org = orphaned_organizations.first
      raise Business::NoOrganizationOwnerError.new(
        "The #{orphaned_org} organization has no owners. At least one owner must be added to the organization."
      )
    end

    SyncBusinessOrganizationBillingSettingsJob.perform_later(
      self,
      enterprise_purchase: enterprise_purchase,
      switch_org_billing_to_invoice: switch_org_billing_to_invoice
    )

    SponsorsBusinessOrgOnboardingJob.perform_later(
      organization: self.upgraded_from, actor: self.actor
    ) if enterprise_purchase
  end

  # Public: Sync the billing settings for the given organization.
  sig { params(organization: Organization).void }
  def sync_organization_billing_settings(organization)
    return unless GitHub.billing_enabled?
    return if trial? || trial_cancelled?

    if organization.admins.empty?
      raise Business::NoOrganizationOwnerError.new(
        "The #{organization} organization has no owners. At least one owner must be added to the organization."
      )
    end

    track_billing_changes(organization, reason: "Synced with parent business billing settings") do |org|
      org.update! \
        plan: self.plan.name,
        plan_duration: self.plan_duration,
        seats: self.seats,
        billed_on: self.billed_on
    end

    sync_organization_terms_of_service(organization)
  end

  sig { params(organization: Organization).returns(T::Boolean) }
  def sync_organization_terms_of_service(organization)
    terms_of_service = organization.terms_of_service
    terms_of_service.update \
      type: terms_of_service_type,
      actor: organization,
      company_name: terms_of_service_company_name
  end

  sig do
    params(
      organization: Organization,
      actor: T.nilable(User),
      reason: T.nilable(String),
      block: T.proc.params(x: Organization).void
    ).void
  end
  def track_billing_changes(organization, actor: nil, reason: nil, &block)
    actor ||= (User.find_by(id: GitHub.context[:actor_id]) || User.ghost)

    # This is necessary since organization attributes now delegate to the business
    plan_name_was = organization.read_attribute(:plan) || GitHub.default_plan_name
    plan_was = GitHub::Plan.find(plan_name_was, effective_at: organization.plan_effective_at, account: organization)
    seats_were = organization.read_attribute(:seats)

    yield organization

    organization.track_plan_change(actor, plan_was, reason: reason)
    organization.track_seat_change(actor, old_seats: seats_were, reason: reason)
  end

  # Public: Return true if the business pays for GHE through Azure
  # This check encompasses both metered and volume licenses
  #
  # If you want to check whether the business uses Azure to pay for metered services, please use `customer.metered_via_azure?`
  # TODO: Remove the `copilot_standalone?` check once they accept Zuora payments
  sig { returns(T::Boolean) }
  memoize def billed_through_azure_subscription?
    T.bind(self, Business)
    enterprise_agreements.active.any? || Copilot::Business.new(self).copilot_standalone?
  end

  sig { returns(T::Boolean) }
  def linked_azure_subscription?
    customer&.azure_subscription_id.present?
  end

  sig { params(old_seats: Integer).void }
  def track_seat_change(old_seats)
    return if old_seats == seats

    actor = User.find_by(id: GitHub.context[:actor_id]) || User.ghost

    instrument(
      "seat_change",
      old_seats: old_seats,
      seats: seats,
      actor: actor,
      actor_id: actor.id,
    )
  end

  # Public: The previous billed_on date, based on the cycles.
  sig { params(cycles: Integer).returns(Date) }
  def previous_billing_date(cycles: 1)
    billing_date = billed_on || GitHub::Billing.today

    if monthly_plan?
      billing_date - cycles.month
    else
      billing_date - cycles.year
    end
  end

  sig { returns(ActiveSupport::TimeWithZone) }
  def current_metered_billing_cycle_starts_at
    if billed_through_azure_subscription? || metered_via_azure? || customer&.billed_via_billing_platform?
      Time.now.utc.beginning_of_month.in_time_zone
    else
      today = GitHub::Billing.today
      bcd = metered_cycle_day

      cycle_date = today
      current_day = today.day
      if current_day < bcd && current_day < cycle_date.end_of_month.day
        # If current_day is less than bill cycle day then we have gone into the next month
        # this means the cycle_date is in the previous month
        cycle_date = today.prev_month
      end

      # This prevents cases where bill cycle day is greater than the number of days in the current month
      bcd = [bcd, cycle_date.end_of_month.day].min

      GitHub::Billing.date_in_timezone(cycle_date.change(day: bcd))
    end
  end

  sig { returns(ActiveSupport::TimeWithZone) }
  def next_metered_billing_cycle_starts_at
    if billed_through_azure_subscription? || metered_via_azure? || customer&.billed_via_billing_platform?
      (current_metered_billing_cycle_starts_at + 1.month).in_time_zone
    else
      end_of_cycle = current_metered_billing_cycle_starts_at.next_month
      bcd = metered_cycle_day

      if end_of_cycle.day != bcd
        # This means the prior month had less days than the BCD
        # We use that information to advance the date to the the lowest between the BCD or the end of month day
        bcd = [bcd, end_of_cycle.end_of_month.day].min
        end_of_cycle = end_of_cycle.change(day: bcd)
      end

      end_of_cycle.in_billing_timezone
    end
  end

  # Public: Checks whether or not they pay GitHub directly for their service. Businesses with
  # enterprise agreements pay Microsoft, not GitHub directly, so we handle some billing related
  # situations differently for them.
  sig { returns(T::Boolean) }
  def pays_github_directly?
    enterprise_agreements.active.empty?
  end

  # Businesses are always the owner of their billing
  sig { returns(Business) }
  def billable_owner
    T.bind(self, Business)

    self
  end

  sig { returns(T::Boolean) }
  def is_organization_billed_through_business?
    false
  end

  sig { returns(T::Boolean) }
  def delegate_billing_to_business?
    false
  end

  sig { returns(Integer) }
  def customer_bill_cycle_day
    if billed_through_azure_subscription?
      1
    else
      customer&.bill_cycle_day.to_i
    end
  end

  sig { returns(T.nilable(ActiveSupport::TimeWithZone)) }
  def zuora_billing_start_datetime
    if date = self.zuora_billing_start_date
      GitHub::Billing.date_in_timezone(date)
    end
  end

  sig { returns(T.nilable(Date)) }
  def zuora_billing_start_date
    active_plan_subscription&.billing_start_date
  end

  sig { returns(T.nilable(ActiveSupport::TimeWithZone)) }
  def enterprise_agreement_effective_at
    enterprise_agreements.active.is_active
      .where.not(starts_at: nil)
      .order(:starts_at).pick(:starts_at)
  end

  sig { returns(Integer) }
  def metered_cycle_day
    return 1 if metered_via_azure?

    [customer_bill_cycle_day.to_i, 1].max
  end

  sig { returns(T.nilable(::Billing::SalesServePlanSubscription)) }
  memoize def sales_serve_plan_subscription
    async_customer.sync&.async_sales_serve_plan_subscription&.sync
  end

  # Public: Add a billing email to the Business.
  sig { params(email: String).returns(T::Array[String]) }
  def add_billing_email(email)
    errors = []

    if billing_email.blank? && billing_external_emails.empty?
      unless update(billing_email: email)
        errors = self.errors.full_messages
      end
    else
      new_email = billing_external_emails.create(email: email)
      unless new_email.save
        errors = new_email.errors.full_messages
      end
    end

    errors
  end

  # Public: Mark a billing email belonging to the Business as primary.
  #
  # Returns an array containing any errors that occurred.
  sig { params(email: T.nilable(BillingExternalEmail)).returns(T::Array[String]) }
  def mark_billing_email_primary(email)
    return ["Email not found"] unless email
    return ["Email not found"] unless email.owner == self
    return email.errors.full_messages unless email.valid?

    errors = T.let([], T::Array[String])

    billing_primary_old = self.billing_email
    self.transaction do
      self.billing_email = email.email
      email.destroy
      billing_external_emails.create(email: billing_primary_old) if billing_primary_old.present?
      unless self.save
        errors = self.errors.full_messages
      end
    end

    errors
  end

  sig { params(old_billing_type: String).returns(T::Boolean) }
  def billing_type_changed?(old_billing_type:)
    customer&.billing_type != old_billing_type
  end

  # Public: Instrument change of billing type for an enterprise account.
  sig { params(payload: T::Hash[T.untyped, T.untyped]).void }
  def instrument_change_billing_type(payload = {})
    payload.merge!(
      business: self,
      billing_type: billing_type
    )

    GitHub.instrument("billing.change_billing_type", payload)
  end

  # Public: Check if a business is billable. Returns true for environment where billing enabled.
  sig { returns(T::Boolean) }
  def billable?
    GitHub.billing_enabled?
  end

  # Public: Applies the dunning rules to the Business and performs the necessary actions
  # like sending notifications or disabling the account.
  sig { params(message: String).void }
  def dun_subscription(message)
    T.bind(self, Business)
    Billing::DunSubscription.perform self, message: message
  end

  # Public: Cancels the account's billing
  # Closes all external subscriptions for the account and zeroes out all invoices and balances.
  # Does not remove paid products from the account, but any previous payments made will be forfeited.
  # External subscriptions can be recreated unless the account is in a state which prevents subscription creation.
  sig { void }
  def cancel_billing
    plan_subscriptions.each { |plan_sub| plan_sub.cancel_external_subscription(force: true) }
  end

  # Public: Suspends the account's billing.
  # Pauses all external subscriptions for the account and zeroes out all invoices and balances.
  # Does not remove paid products from the account, and any previous payments made will be honored upon resumption.
  # Prefer cancelling the account if there are no plans to resume billing in the future.
  sig { void }
  def suspend_billing
    plan_subscriptions.each { |plan_sub| SuspendPlanSubscriptionJob.perform_later(plan_sub) }
  end

  # Public: Resumes the account's billing.
  # Resumes all external subscriptions for the account that were suspended.
  # The customer will not be charged for the service period while the subscriptions were suspended.
  sig { void }
  def resume_billing
    plan_subscriptions.each { |plan_sub| ResumePlanSubscriptionJob.perform_later(plan_sub) }
  end

  # Public: Should the Business be reminded that their credit card is expiring?
  sig { returns(T::Boolean) }
  def should_remind_about_expiring_card?
    has_credit_card? &&
      card_expiring_in_less_than_three_weeks? &&
      payment_method&.expiration_reminders == 0
  end

  # Public: Is the credit card on file going to expire in the next three
  # weeks?
  sig { returns(T::Boolean) }
  def card_expiring_in_less_than_three_weeks?
    has_credit_card? && payment_method&.expiring_in_less_than_three_weeks?
  end

  # Public: Check if a business has a credit card linked to their enterprise account.
  sig { returns(T::Boolean) }
  def has_credit_card?
    return false unless billable?
    !!payment_method&.credit_card?
  end

  # Public: Check if a business has a PayPal account linked to their enterprise account.
  sig { returns(T::Boolean) }
  def has_paypal_account?
    return false unless billable?
    !!payment_method&.paypal?
  end

  # Public: Check if a business has an Azure subscription linked to their enterprise account.
  sig { returns(T::Boolean) }
  memoize def has_valid_azure_subscription?
    return false unless billable?
    !!linked_azure_subscription && !invalid_azure_subscription_detected?
  end

  # Public: Check if a business has a valid payment method linked to their enterprise account.
  sig { params(check_for_stopgap_restriction: T::Boolean).returns(T::Boolean) }
  def has_valid_payment_method?(check_for_stopgap_restriction: true)
    return false unless billable?
    return true if metered_plan? && has_valid_azure_subscription?
    return false unless payment_method.present?
    payment_method.valid_payment_token?
  end

  # Public: Friendly name for the payment method on file.
  sig { params(none_text: T.nilable(String)).returns(String) }
  def friendly_payment_method_name(none_text = nil)
    if has_credit_card?
      "credit card"
    elsif has_paypal_account?
      "PayPal account"
    else
      none_text || "payment information"
    end
  end

  # Public: Has the credit card on file expired?
  sig { returns(T::Boolean) }
  def card_expired?
    return false unless has_credit_card?

    today = GitHub::Billing.today
    payment_method.expiration_year < today.year || (
      payment_method.expiration_year == today.year &&
      payment_method.expiration_month < today.month
    )
  end

  # Public: Check if a business has an external subscription associated with their enterprise account.
  sig { returns(T::Boolean) }
  def external_subscription?
    return false unless billable?
    return !!@external_subscription if defined? @external_subscription
    !!@external_subscription = T.let(!!(plan_subscription&.present? && plan_subscription&.has_external_subscription?), T.nilable(T::Boolean))
  end

  sig { returns(T::Boolean) }
  def any_external_subscriptions?
    external_subscription?
  end

  sig do
    params(
      plan: T.nilable(GitHub::Plan),
      billing_cycle: T.nilable(String),
      target_date: T.nilable(Date)
    ).returns(T::Boolean)
  end
  def annual_discount_allowed?(plan: self.plan, billing_cycle: plan_duration, target_date: GitHub::Billing.today)
    return false unless billing_cycle == YEARLY_PLAN
    return false unless plan
    return false unless plan.business_plus?
    first_transaction = T.must(customer).billing_transactions.paid.yearly.first
    return true unless first_transaction
    # we may apply the discount for seat additions in the same year
    (T.cast(T.must(target_date) - first_transaction.created_at.in_time_zone(GitHub::Billing.timezone).to_date, Rational)).to_i < 365
  end

  sig { returns(Integer) }
  def data_packs
    0
  end

  sig { returns(T.nilable(Coupon)) }
  def coupon
    nil
  end

  sig { returns(Integer) }
  def discount
    0
  end

  sig { override.returns(T::Boolean) }
  def has_billing_record?
    zuora_account?
  end

  sig { returns(T::Boolean) }
  def zuora_account?
    !!customer&.zuora?
  end

  sig { returns(T.nilable(String)) }
  memoize def linked_azure_subscription
    customer&.azure_subscription_id
  end

  sig { returns(String) }
  memoize def linked_azure_subscription_name
    customer&.azure_subscription_name.presence || "Subscription"
  end

  sig { returns(T::Boolean) }
  def invalid_azure_subscription_detected?
    customer&.invalid_azure_subscription_detected? || false
  end

  sig do
    params(
      explicit_tenant_selected: T::Boolean,
      tenant: String,
      redirect_path: T.nilable(String)
    ).returns(URI)
  end
  def azure_subscription_uri(explicit_tenant_selected: false, tenant: "common", redirect_path: nil)
    uri = URI("https://login.microsoftonline.com/#{tenant}/oauth2/v2.0/authorize")
    state_hash = {
      business_slug: self.slug,
      explicit_tenant_selected: explicit_tenant_selected
    }

    if GitHub.multi_tenant_enterprise?
      # We pass the host name with tenant so the Azure redirects will work Proxima where customers have custom subdomains
      state_hash[:host_name] = GitHub.host_name_with_tenant
    end

    state_encoded = Base64.encode64(state_hash.to_json)

    uri.query = URI.encode_www_form({
      client_id: GitHub.azure_oauth_app_id,
      redirect_uri: GitHub.azure_oauth_app_redirect_uri_for_businesses,
      scope: "https://management.azure.com/user_impersonation",
      response_type: "code",
      state: state_encoded,
      response_mode: "query",
      prompt: "select_account"
    })
    uri
  end

  # Public: Returns true if the business has a payment count greater than `minimum_payment_count`
  #
  # minimum_payment_count - the number of payments required to be considered successful
  sig { params(start_date: T.nilable(Date), minimum_payment_count: Integer).returns(T::Boolean) }
  def successful_paid_payments?(start_date: nil, minimum_payment_count: 1)
    transactions = billing_transactions.successful.paid
    transactions = transactions.created_at_or_after(start_date) unless start_date.nil?
    transactions.count >= minimum_payment_count
  end

  # Public: The customer of a business, based on the billing purpose. Can only be the associated
  # customer for a business currently.
  sig { params(_purpose: T.any(String, Symbol)).returns(T.nilable(Customer)) }
  def customer_for(_purpose)
    customer
  end

  sig { returns(T.nilable(Customer)) }
  def billing_customer
    customer
  end

  # Public: The payment processor email address to use for businesses.
  sig { returns(T.nilable(String)) }
  def payment_processor_email
    billing_email
  end

  # Public: The payment processor account name to use for businesses.
  sig { returns(String) }
  def payment_processor_account_name
    slug
  end

  # TODO: Remove or update this method once we handle trade compliance checks for enterprises.
  sig { returns(T.nilable(String)) }
  def billing_extra
    nil
  end

  # TODO: Remove or update this method once we handle trade compliance checks for enterprises.
  sig { returns(T.nilable(String)) }
  def vat_code
    nil
  end

  # Public: Tells if this business is being billed on a yearly basis.
  sig { returns(T::Boolean) }
  def yearly_plan?
    plan_duration == YEARLY_PLAN
  end

  # Public: Tells if this business is being billed on a monthly basis.
  sig { returns(T::Boolean) }
  def monthly_plan?
    plan_duration == MONTHLY_PLAN
  end

  sig { returns(Integer) }
  def plan_duration_in_months
    yearly_plan? ? 12 : 1
  end

  sig { returns(T::Boolean) }
  def first_time_charge?
    billing_transactions.first_time_charge.blank?
  end

  sig { returns(T::Boolean) }
  def requires_invoice_by_email?
    customer = self.customer
    return false if customer.nil?
    customer.requires_invoice_by_email?
  end

  # Checks whether we should immediately attempt to collect payment for plan or seat changes.
  sig { returns(T::Boolean) }
  def collect_payment_immediately_for_plan_or_seat_changes?
    return false if customer&.requires_manual_transactions? || invoiced?
    return false unless plan_subscription.present? && zuora_account? &&
      payment_amount(plan: plan, duration: plan_duration) > 0
    !self.feature_enabled?(:skip_immediate_payment_collection_for_plan_or_seat_changes, memoize: false)
  end

  # Public: Checks if business meets requirements for auth
  #
  # check_payment_method - boolean used to skip payment method check
  # useful in situations like the credit card form that informs business of auth & capture
  # while they are filling in their new credit card payment method
  #
  # Returns Boolean
  sig { params(check_payment_method: T::Boolean, check_overage: T::Boolean).returns(T::Boolean) }
  def can_be_authorized?(check_payment_method: true, check_overage: true)
    # Do not perform auth & capture on invoiced businesses or invoices billed via Azure subscription
    return false if invoiced?
    return false if metered_via_azure?

    if check_payment_method
      # Only works for users with a credit card payment method
      return false unless self.payment_supports_authorization?
    end

    # Only target non tier 1 businesses
    # Currently tier 1 only include businesses invoiced or with established billing history
    trust_tier = TrustTiers::Tier.for_billable_owner(self).tier
    return false if trust_tier == 1

    # Skip users in dunning that have a paid plan and a recent history of successful payments.
    # This prevents prematurely locking the account and zeroing out of their invoices which is a bad experience
    # for the users and also causes unnecessary losses for us.
    #
    # TODO: Remove this once we have a way to collect outstanding invoices for locked accounts
    return false if self.dunning? && successful_paid_payments?(
      start_date: GitHub::Billing.today - 4.months, minimum_payment_count: 3)

    # metered_billing_overage_allowed? always returns nil for Copilot, but we still want to
    # auth and capture
    # metered_billing_overage_allowed? is only relevant to meuse customers on the business side,
    # excluding that check here
    if check_overage && !customer&.billed_via_billing_platform?
      return false unless self.metered_billing_overage_allowed?
    end

    true
  end

  # Public: Charge type label for a recurring charge
  sig { returns(String) }
  def recurring_charge_type
    first_time_charge? ? "first-time-paid-upgrade" : "recurring-charge"
  end

  # Public: Charge this business for the current recurring payment amount.
  #
  # Returns GitHub::Billing::Result object indicating the success or
  # failure of the recurring charge
  sig { returns(T.nilable(GitHub::Billing::Result)) }
  def recurring_charge
    T.bind(self, Business)

    GitHub.logger.info(
      "code.namespace" => self.class.name,
      "code.function" => "recurring_charge",
      "gh.business.slug" => slug,
      "gh.billing.plan_subscription.zuora_subscription_number" => plan_subscription&.zuora_subscription_number,
    )

    if external_subscription?
      plan_subscription.retry_charge
    elsif should_transition_to_external_subscription?
      # Invoices generated after creation of an external subscription will be
      # collected by the CollectZuoraInvoiceJob.
      result = GitHub::Billing.transition_to_external_subscription(
        self,
        purpose: plan_subscription&.purpose&.to_sym,
        skip_sync: !!T.unsafe(self).skip_update_external_subscription
      )
      GitHub::Billing::Result.new(result)
    else
      GitHub::Billing::Result.success
    end
  end

  # Public: Should this business be charged?
  sig { returns(T::Boolean) }
  def past_due?
    return false if downgraded_to_free_plan?
    billed_on = self.billed_on

    billed_on.nil? || billed_on <= GitHub::Billing.today
  end

  # Public: Is this business currently past due on their invoice?
  #
  # Returns Boolean
  sig { returns(T::Boolean) }
  def past_due_invoice?
    return false if GitHub.single_business_environment?
    return false if customer&.zuora_account_id.nil?
    return false if self_serve_payment?
    return false if next_billing_date.nil?
    return false if sales_serve_plan_subscription.nil?
    return false unless payment_amount > 0
    return false unless GitHub::Billing.today >= T.must(next_billing_date)

    GitHub.dogstats.increment("billing.zuora.past_due_invoice_api_check")
    Billing::Zuora::Invoice.past_due(account_id: T.must(T.must(customer).zuora_account_id)).any?
  end

  # Is this business getting service that they should be paying for, but aren't?
  sig { returns(T::Boolean) }
  def beneficiary?
    past_due? && !has_valid_payment_method? &&
      payment_amount > 0
  end

  # Public: How much should they actually be paying? Takes into account any discounts
  # their account currently has and any differing plan durations.
  #
  # options - Hash of options
  #        :plan               - GitHub::Plan object. Defaults to the current plan.
  #        :duration           - Symbol representing duration (e.g. :month or :year)
  #        :duration_in_months - Duration of requested plan. Defaults to current plan duration in months
  #        :type               - Price type to return as a Symbol. Optional. Defaults to :final
  #        :plan_seats         - Integer representing the number of seats. Default delegates to #seats
  #        :include_metered_usage - Whether or not to include metered usage in the amount. Defaults to true.
  #        :plan_annual_discount - Whether or not to deduct one month free for customers on the yearly duration. Defaults to false.
  sig do
    params(
      plan: T.nilable(GitHub::Plan),
      duration: T.nilable(T.any(Symbol, String)),
      duration_in_months: T.nilable(Integer),
      type: Symbol,
      plan_seats: T.nilable(Integer),
      include_metered_usage: T::Boolean,
      plan_annual_discount: T::Boolean,
    ).returns(BigDecimal)
  end
  def payment_amount(plan: nil, duration: nil, duration_in_months: nil, type: :final, plan_seats: seats, include_metered_usage: true, plan_annual_discount: false)
    period = \
      if duration
        duration
      elsif duration_in_months
        duration_in_months == 1 ? :month : :year
      end

    Billing::Pricing.new(
      account: T.cast(self, Business),
      plan: plan,
      plan_duration: period,
      plan_annual_discount: plan_annual_discount,
      seats: plan_seats,
      include_metered_usage: include_metered_usage,
    ).discounted.dollars
  end

  # Public: How much is this business paying not accounting for discounts
  #
  # Returns BigDecimal of dollars
  sig { params(plan: T.nilable(GitHub::Plan), duration: T.nilable(Symbol), plan_seats: Integer).returns(BigDecimal) }
  def undiscounted_payment_amount(plan: nil, duration: nil, plan_seats: seats)
    Billing::Pricing.new(
      account: T.cast(self, Business),
      plan: plan,
      plan_duration: duration,
      seats: plan_seats,
    ).undiscounted.dollars
  end

  # Public: Default seats for a business. Method was created to add consistency between billing account types.
  # Users/orgs currently have an implementation for this that checks how many seats should be included when starting a new plan.
  # Since Enterprise accounts only have one paid plan, this should just return the amount of seats they currently have.
  #
  # Returns Int seats
  sig { returns(Integer) }
  def default_seats
    seats
  end

  # Public: Return a Billing::Subscription to model this business's plan subscription
  #
  # plan_subscription - Billing::PlanSubscription to use for this business; optional, defaults to
  #                     general-purpose plan subscription for the business
  sig { params(plan_subscription: T.nilable(Billing::PlanSubscription)).returns(Billing::Subscription) }
  def subscription(plan_subscription: nil)
    Billing::Subscription.for_account(self, plan_subscription: plan_subscription)
  end

  # Public: The balance on the customer's specified subscription. Negative means they have a
  # credit.
  #
  # purpose - Symbol indicating the billing purpose of the subscription to look up for this Business,
  #           either :general or :sponsors
  sig { params(purpose: Symbol).returns(BigDecimal) }
  def balance(purpose: Customer::DEFAULT_PURPOSE)
    plan_sub = ::Billing::PlanSubscription.where(purpose: purpose).find_by(customer_id: customer_id)
    plan_sub&.balance.to_d
  end

  sig { void }
  def destroy_dependent_plan_subscription
    plan_subscription&.destroy
  end

  sig { void }
  def destroy_dependent_manual_dunning_period
    manual_dunning_period&.destroy
  end

  # Internal: Schedule a job to synchronize this business's plan information
  # if there are changes that need to be synchronized.
  #
  # The job will be run after all database changes are committed. To run the
  # job immediately, use User#update_external_subscription!
  sig { params(force: T::Boolean).void }
  def update_external_subscription(force: false)
    if external_subscription?
      if force || remote_subscription_needs_update?
        schedule_subscription_synchronization
      end
    end
  end

  # Internal: Schdule a job to create an external subscription if it does not
  #           present, or update an existing one.
  # See #update_external_subscription for update behavior
  sig { params(kwargs: T.untyped).void }
  def create_or_update_external_subscription(**kwargs)
    return update_external_subscription(**kwargs) if external_subscription?
    schedule_subscription_synchronization
  end

  # Internal: Enqueues an UpdateExternalCustomer job to update the customer
  # record in Braintree or Zuora.
  #
  # This happens after commit to ensure that when the job is picked up by the
  # worker, all of the changes processed in the enqueuing thread are saved.
  sig { void }
  def run_scheduled_external_customer_update
    return unless eligible_for_self_serve_payment?
    UpdateExternalCustomerJob.perform_later(T.must(self.customer)) if @needs_external_customer_update
  end

  # Internal: Enqueues a SynchronizePlanSubscription job to synchronize the
  # customer's plan subscription with Braintree or Zuora.
  #
  # This happens after commit to ensure that when the job is picked up by the
  # worker, all of the changes processed in the enqueuing thread are saved.
  sig { params(one_time_only: T::Boolean).void }
  def run_scheduled_subscription_synchronization(one_time_only: false)
    return unless eligible_for_self_serve_payment?
    return unless @needs_subscription_synchronization
    synchronize_general_purpose_subscription_later
    sponsors_plan_subscription = self.sponsors_plan_subscription
    sponsors_plan_subscription.synchronize_later if sponsors_plan_subscription

    # Set the flag to false to prevent subsequent synchronization jobs from firing off
    # on future updates
    if one_time_only
      @needs_subscription_synchronization = false
    end
  end

  sig { void }
  def synchronize_general_purpose_subscription_later
    T.bind(self, Business)
    SynchronizePlanSubscriptionJob.perform_later({ business_id: id, plan_name: plan.name }, business: self)
  end

  sig { params(collect: T.nilable(T::Boolean)).void }
  def synchronize_all_plan_subscriptions(collect: nil)
    plan_subscriptions.each { |plan_sub| plan_sub.synchronize_later(collect: collect) }
  end

  # Internal: Mark the record as requiring a Braintree customer update, which
  # is handled in the UpdateExternalCustomer job
  sig { returns(T::Boolean) }
  def schedule_external_customer_update
    !!(@needs_external_customer_update = T.let(true, T.nilable(T::Boolean)))
  end

  # Internal: Mark the record as requiring a subscription synchronization,
  # which is handled by the SynchronizePlanSubscription job
  sig { returns(T::Boolean) }
  def schedule_subscription_synchronization
    !!(@needs_subscription_synchronization = T.let(true, T.nilable(T::Boolean)))
  end

  # Public: Transfers an organization's marketplace items to a business. Will be called when an organization is upgrading
  # or has been invited into a business.
  # The business must be self-serve payment enabled, and the organization must have marketplace items.
  sig { params(organization: Organization, actor: User).void }
  def transfer_marketplace_purchases_from_org_to_business(organization, actor)
    return unless self.self_serve_payment? && organization.subscription_items.with_marketplace_listing_plans_type.any?

    organization.subscription_items.with_marketplace_listing_plans_type.each do |subscription_item|
      # Create a new subscription item for the business
      new_subscription_item = Billing::SubscriptionItem.new(subscription_item.attributes.except("id", "created_at", "updated_at", "plan_subscription_id"))
      new_subscription_item.organization = organization
      new_subscription_item.plan_subscription = self.plan_subscription
      new_subscription_item.save

      if subscription_item.has_pending_cycle_change?
        new_pending_plan_change = Billing::PendingPlanChange.new
        new_pending_plan_change.actor_id = actor.id
        new_pending_plan_change.active_on = subscription_item.pending_subscription_item_change.pending_plan_change.active_on
        new_pending_plan_change.customer = self.customer
        new_pending_plan_change.save

        subscription_item.pending_subscription_item_change.update(
          plan_subscription_id: self.plan_subscription.id,
          pending_plan_change_id: new_pending_plan_change.id,
          organization_id: organization.id
        )
      end

      # Cancel the old subscription item if it's still active
      subscription_item.cancel!(force: true) if subscription_item.active?
    end
  end

  # Public: Transfers an organization's sponsorships to a business. Will be called when an organization is upgrading
  # or has been invited into a business.
  sig { params(organization: Organization, actor: User, bill_on: T.nilable(Date)).void }
  def transfer_sponsors_purchases_from_org_to_business(organization, actor, bill_on: nil)
    Sponsors::TransferOrgSponsorshipsToEnterprise.call(organization: organization, actor: actor, bill_on: bill_on)
  end

  # Public: Transfers the Zuora account Customer and Subscription from an Organization to this Business.
  # This is used for direct upgrades from an Enterprise-plan Organization to a Business.
  # All billing settings should be directly copied over to avoid any interruption in billing.
  sig { params(organization: Organization, actor: User).void }
  def transfer_billing_from_organization(organization, actor)
    return if organization.invoiced?
    return unless organization.customer.present?
    return unless organization.plan.business_plus?

    if organization.plan_subscription.nil?
      return unless organization.has_an_active_coupon?
    end

    coupon_to_transfer = organization.coupon_redemption
    transfer_customer(organization)
    transfer_trade_screening_record(organization)
    if coupon_to_transfer.present?
      self.apply_coupon_from_upgrading_org(org_coupon_redemption: coupon_to_transfer)
    end

    self.synchronize_general_purpose_subscription_later

    organization.customer_account&.destroy!  # Destroy the organization -> customer relationship
    organization.plan_subscriptions.each do |subscription|
      subscription.update!(user_id: nil) # Destroy all organization -> plan subscription relationships
    end
    organization.reload

    update_customer_name
  end

  # Internal: Are there plan changes that need to be synchronized
  sig { returns(T::Boolean) }
  def remote_subscription_needs_update?
    saved_change_to_seats? || saved_change_to_plan_duration?
  end

  sig { returns(T::Boolean) }
  def changing_seats?
    organization? && will_save_change_to_seats? && plan && plan.per_seat?
  end

  sig { params(next_billing_date: Date, billing_attempts: Integer).returns(T::Boolean) }
  def update_billing_date(next_billing_date:, billing_attempts:)
    billing_end_date = next_billing_date - 1.day
    customer&.update_columns(billing_end_date: billing_end_date, billing_attempts: billing_attempts)
    update!(billing_term_ends_at: billing_end_date)
  end

  # Public: The latest bill balance of the business, as obtained from the Zuora account of the
  # business. For business without a Zuora account, returns a balance of 0.
  sig { returns(BigDecimal) }
  memoize def latest_bill_balance
    account = zuora_account
    if account.nil? || account[:metrics].nil?
      BigDecimal(0)
    else
      account[:metrics][:balance].to_d
    end
  end

  # Public: The latest bill of the business, as obtained from the due date of Zuora
  # invoices of the business with a positive balance. The due date of all unpaid invoices should be
  # the same. However, in the unexpected circumstance that the due date of are all unpaid invoices
  # isn't the same, take the due date of the invoice with the earliest due date.
  sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  memoize def latest_bill
    zuora_account_id = customer&.zuora_account_id
    return nil unless zuora_account_id.present?

    bills = Billing::Zuora::Invoice.open_invoices_for_account(zuora_account_id).map do |invoice|
      item = invoice.invoice_items.find { |item| item.unit == "Seats" }
      {
        id: invoice.id,
        due_date: Date.parse(invoice.due_date),
        start_date: item ? Date.parse(item.service_start_date) : nil,
        end_date: item ? Date.parse(item.service_end_date) : nil
      }
    end

    bills.empty? ? nil : bills.min { |a, b| a[:due_date] <=> b[:due_date] }
  end

  # Public: Check if the customer has a bill present
  sig { returns(T::Boolean) }
  def has_bill?
    latest_bill.present?
  end

  # Public: Check if the latest bill is overdue for payment
  sig { returns(T::Boolean) }
  def bill_overdue?
    has_bill? ? GitHub::Billing.today > T.must(latest_bill)[:due_date] : false
  end

  # Check if the active coupon will already be expired on the next_billing_date. Businesses
  # currently don't support coupons. Hence, his always returns false for now.
  sig { returns(T::Boolean) }
  def will_be_expired?
    false
  end

  # Public: The first date of the next billing cycle. For an enterprise account with a good
  # standing, this is the next day the account will automatically be billed on.
  #
  # with_dunning - Boolean. Whether to consider our dunning process when calculating the date for
  # a past due account. When false, returns today's date for past due accounts (this is used in
  # billing calculations when renewing an account to determine when the next cycle should begin).
  # When true, returns the next day we will automatically attempt to charge the account's stored
  # payment method, assuming that the account takes no action. Defaults to false.
  sig { params(with_dunning: T::Boolean).returns(T.nilable(Date)) }
  def next_billing_date(with_dunning: false)
    today = GitHub::Billing.today
    year = today.year
    month = today.month
    day = today.day

    if customer&.billed_via_billing_platform?
      bill_cycle_day = [customer&.bill_cycle_day.to_i, 1].max
      if bill_cycle_day <= day
        year = month == 12 ? year + 1 : year
        month = month == 12 ? 1 : month + 1
      end
      next_billing_date = Date.new(year, month, bill_cycle_day)
    else
      next_billing_date = billed_on || today
    end

    if with_dunning
      next_dunning_day = [0, 7, 15][billing_attempts]
      return unless next_dunning_day
      next_billing_date + next_dunning_day.days
    else
      [next_billing_date, GitHub::Billing.today].max
    end
  end

  # Public: Upgrades a trial business account that is eligible for self-serve payments, and with
  # valid payment method to a fully paying business account, through the following process:
  #
  # 1) Initiates conversion of the trial account to a paying account.
  # 2) Updates the account's billing cycle day to today.
  # 3) Enqueues job to synchronize the account's plan subscription.
  sig { params(current_user: User, skip_sync: T::Boolean).returns(T::Boolean) }
  def upgrade_from_trial(current_user, skip_sync: false)
    return false unless eligible_for_self_serve_payment?
    return false unless can_enable_automatic_self_serve_payment?
    return false unless has_valid_payment_method?

    initiate_trial_conversion
    return false unless trial_conversion_initiated?

    result = update_billing_and_sync_subscription(current_user: current_user, skip_sync: skip_sync)
    return false unless result

    # Once a trial business account is upgraded, it's converted through a Zuora webhook after
    # confirmation of a successful initial payment. However, Zuora webhooks don't work seamlessly
    # in local development. Hence, a trial business account is converted when this method runs in
    # local development, to make it easier for anyone to test the upgrade process.
    # Metered accounts are converted during the upgrade process, so this step is skipped for metered plans
    restore_deleted_pages
    (Rails.env.development? && !metered_plan?) ? convert_trial : true
  end

  sig { params(actor: User, enterprise_seats: Integer, enterprise_plan_duration: String, ghas_committers: Integer).returns(GitHub::Result) }
  def purchase_enterprise_and_ghas(actor:, enterprise_seats:, enterprise_plan_duration:, ghas_committers:)
    return GitHub::Result.error("Cannot complete purchase because your account has been flagged. If you believe this is a mistake, contact support.") if actor.spammy?

    seat_limit = seat_limit_for_upgrades
    consumed_licenses = total_consumed_licenses
    return GitHub::Result.error("You can only add up to #{seat_limit} seats when upgrading.") if enterprise_seats > seat_limit
    return GitHub::Result.error("You must purchase at least #{pluralize(consumed_licenses, "seat")} to support your #{pluralize(consumed_licenses, "existing member")}.") if enterprise_seats < consumed_licenses
    return GitHub::Result.error("Duration must be either 'month' or 'year'.") if enterprise_plan_duration != MONTHLY_PLAN && enterprise_plan_duration != YEARLY_PLAN

    unless update(seats: enterprise_seats, plan_duration: enterprise_plan_duration) && upgrade_from_trial(actor, skip_sync: true)
      return GitHub::Result.error("Failed to complete GitHub Enterprise purchase. Please try again later or contact support.")
    end

    if ghas_committers > 0
      subscribe_to_advanced_security_result = subscribe_to_advanced_security(
        actor: actor,
        seats: ghas_committers,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month,
        skip_sync: true,
      )

      return GitHub::Result.error(subscribe_to_advanced_security_result.error.message) unless subscribe_to_advanced_security_result.ok?
    end

    synchronize_general_purpose_subscription_later
    instrument :multi_checkout, {
      actor:,
      enterprise_seats:,
      advanced_security_seats: ghas_committers,
      advanced_security_plan_duration: "month",
      enterprise_plan_duration:,
    }
    GitHub::Result.new { self }
  end

  # Public: Updates a business account that is eligible for self-serve payments, and with
  # valid payment method to the organization_upgrade_purchase_initiated state. This method is
  # only called when a user chooses to upgrade their free- or-teams-plan org to an Enterprise
  # Account. It kicks off a sync job with Zuora to process payment, and the EA is locked down
  # until payment is processed.
  sig { params(current_user: User).returns(T::Boolean) }
  def upgrade_from_free_or_business_plan_org(current_user)
    return false unless eligible_for_self_serve_payment?
    return false unless has_valid_payment_method?

    initiate_organization_upgrade_purchase(current_user)
    return false unless organization_upgrade_purchase_initiated?

    result = update_billing_and_sync_subscription(current_user: current_user, trial_business: false)
    return false unless result
    restore_deleted_pages
    Rails.env.development? ? upgrade_from_organization : true
  end

  # Public: Redeems a coupon and handles associated business logic.
  # If the account was created from a coupon and the coupon doesn't cover the full subscription cost,
  # it triggers asynchronous payment collection. After redeeming the coupon, it synchronizes the Zuora subscription.
  # If the coupon covers the full plan cost, it immediately upgrades the business and attaches the organization (if present).
  sig { params(coupon: Coupon, current_user: User).returns(GitHub::Billing::Result) }
  def schedule_async_coupon_payment_collection(coupon, current_user)
    result = GitHub::Billing::Result.failure("Unable to redeem a coupon on this account.")
    return result unless current_user.can_apply_coupon_to_self_serve_enterprise_account?

    if self.redeem_coupon(coupon, actor: current_user, instrument: false)
      if creation_initiated_from_coupon?
        # Check the payment amount required after applying the coupon, considering the annual discount may apply if on the yearly cadence (one month free)
        result = if payment_amount(plan_annual_discount: annual_discount_allowed?).zero?
          # Skip the payment initiation and complete the creation, attaching the organization if needed
          complete_creation_from_coupon ? GitHub::Billing::Result.success : GitHub::Billing::Result.failure(self.errors.full_messages.first)
        else
          upgrade_from_coupon_redemption(current_user) ? GitHub::Billing::Result.success : GitHub::Billing::Result.failure(self.errors.full_messages.first)
        end
      else
        result = GitHub::Billing::Result.success
      end
    else
      result = GitHub::Billing::Result.failure(self.errors.full_messages.first)
    end

    if result.failed?
      result.error_message = "Failed to complete GitHub Enterprise purchase. Please try again later or contact support." if result.error_message.nil?
      # Get out of the purchase state if required.
      initiate_creation_from_coupon(current_user) if creation_from_coupon_purchase_initiated?
      # Remove the coupon and reset its limit
      coupon = self.coupon
      if coupon.present?
        coupon.increment!(:limit)
        expire_active_coupon(quiet: true)
      end
    end

    result
  end

  sig { params(current_user: User).returns(T::Boolean) }
  def upgrade_from_coupon_redemption(current_user)
    return false unless eligible_for_self_serve_payment?
    return false unless has_valid_payment_method?

    initiate_creation_purchase_from_coupon(current_user)
    return false unless creation_from_coupon_purchase_initiated?

    result = update_billing_and_sync_subscription(current_user: current_user, trial_business: false)
    return false unless result
    restore_deleted_pages

    Rails.env.development? ? complete_creation_from_coupon : true
  end

  # Public: helper method that returns businesses created from a coupon redemption
  # that initiated a payment (because coupon did not cover total cost)
  # back to their initial state. This method is called either when the payment fails
  # or when it's been processing for > 24 hours.
  sig { returns(T::Boolean) }
  def reset_coupon_purchase_status
    return false unless self.creation_from_coupon_purchase_initiated?
    active_coupon = self.coupon

    # Using the force: true flag here because we still want
    # this business returned to its original state even if the feature flag has been disabled
    self.initiate_creation_from_coupon(self.owners.first, coupon_code: active_coupon&.code, force: true)
    self.update! upgrade_purchase_initiated_at: nil

    self.disable_automatic_self_serve_payment(User.ghost)

    # Reset the coupon's ability to be redeemed, since this purchase failed
    if active_coupon.present?
      active_coupon.increment!(:limit)
      self.expire_active_coupon(quiet: true)
      self.expired_coupons.where(coupon_id: active_coupon.id).order(created_at: :asc).last&.destroy
    end

    BusinessMailer.creation_from_coupon_purchase_failure(self.owners.first, self, coupon: active_coupon&.code).deliver_later

    true
  end

  sig do
    params(
      current_user: User,
      bill_cycle_day: T.nilable(Integer),
      trial_business: T::Boolean,
      skip_sync: T::Boolean
    ).returns(T::Boolean)
  end
  def update_billing_and_sync_subscription(
    current_user:,
    bill_cycle_day: GitHub::Billing.today.strftime("%d").to_i,
    trial_business: true,
    skip_sync: false
  )
    T.bind(self, Business)

    if metered_ghec_trial?
      return false unless trial_conversion_initiated?

      # Metered GHE is charged at the end of the billing period, so we need to convert the trial now.
      # CheckBillableEntitiesMeteredUsageForAuthorizationThresholdsJob will be used to validate the payment method.
      convert_trial
      return true if has_valid_azure_subscription? # No need to syncronize with Zuora
    end

    result = ::Billing::UpdateCustomerBillCycleDay.new(self, bill_cycle_day).call
    return false unless result.success?

    enable! if trial_business

    synchronize_general_purpose_subscription_later unless skip_sync
    enable_automatic_self_serve_payment(current_user)

    true
  end

  sig { returns(Billing::PendingCycle) }
  def pending_cycle
    T.bind(self, Business)

    Billing::PendingCycle.new(self)
  end

  # The changes that will occur on the business's next billing date,
  # not including free trial changes
  sig { returns(T.nilable(::Billing::PendingPlanChange)) }
  def pending_cycle_change
    @pending_cycle_change ||= T.let(pending_plan_changes.incomplete.not_past.where(active_on: next_billing_date).first, T.nilable(::Billing::PendingPlanChange))
  end

  sig { returns(T.nilable(Billing::Money)) }
  def pending_cycle_new_price
    seats = pending_cycle_change&.seats
    return nil unless seats.present?

    plan_cost = pending_cycle.plan_duration == User::BillingDependency::YEARLY_PLAN ? plan.yearly_cost : plan.cost
    value_in_cents = seats * plan_cost * 100
    Billing::Money.new(value_in_cents)
  end

  sig { returns(T.nilable(String)) }
  def education_bundle_slug
    return unless education_bundle?
    "education_#{T.must(sales_serve_plan_subscription).education_bundle}"
  end


  sig { returns(T::Boolean) }
  memoize def only_for_copilot?
    sales_serve_plan_subscription&.has_ghec_for_copilot? || false
  end

  # Internal: Determine if this business should be transitioned to an external subscription.
  # A subscription is required to bill for any paid products and metered usage.
  sig { returns(T::Boolean) }
  def should_transition_to_external_subscription?
    !external_subscription? && has_valid_payment_method?
  end

  # Internal: Determine if this business has been disabled due to failed recurring charge. Only
  # returns true for non-trial business disabled, that has exceeded the billing attempts limit and
  # got its dunning period expired.
  sig { returns(T::Boolean) }
  def disabled_due_to_failed_recurring_charge?
    return false if trial?
    return false if trial_cancelled?
    return false unless disabled?
    over_billing_attempts_limit? && dunning_period_expired?
  end

  sig { void }
  def soft_delete_pages
    # Prior to this commit we would not disable any private pages when a business was downgraded.
    # Even though DestroyPrivatePagesJob uses this feature flag, use it here as well to avoid
    # destroying pages when the feature flag is disabled, as it would be a destructive change in
    # behavior.
    if downgraded_to_free_plan? && self.feature_enabled?(:pages_soft_deletion, memoize: false)
      self.organizations.each { |org| DestroyPrivatePageJob.perform_later(org) }
    end
  end

  # Internal: Restore deleted pages within all organizations in the business
  sig { void }
  def restore_deleted_pages
    self.organizations.each { |org| RestoreSoftDeletedPagesJob.perform_later(org) }
  end

  # Public: Updates the billing name fields for a Business' customer object.
  # Sets the name, bill_to, and sold_to values based on the Business name.
  sig { void }
  def update_customer_name
    return unless self.customer

    customer = T.must(self.customer)
    customer.name = self.name # Update the customer name
    customer.save!
    UpdateExternalCustomerJob.perform_later(customer)
  end

  sig { params(user: User).returns(T::Boolean) }
  def has_azure_token?(user:)
    T.bind(self, Business)
    client = Billing::Azure::BusinessSubscriptionClient.new(user, self)
    client.has_token?
  end

  sig {  params(current_user: User).returns(T::Boolean) }
  def show_payment_due_tile?(current_user)
    return false unless billing_manager?(current_user) || owner?(current_user)

    can_self_serve? && !invoiced? && !trial?
  end

  sig {  params(current_user: User).returns(T::Boolean) }
  def show_past_invoices_tab?(current_user)
    return false unless billing_manager?(current_user) || owner?(current_user)
    return false unless pays_github_directly?
    return false if reseller_customer?

    invoiced?
  end

  sig { params(current_user: User).returns(T::Boolean) }
  def show_volume_license_spend_tile?(current_user)
    return false unless billing_manager?(current_user) || owner?(current_user)
    return false if metered_ghe?
    !trial?
  end

  sig { returns(T::Boolean) }
  def remove_azure_subscription_on_adding_cc_paypal?
    return false if GitHub.single_business_environment?
    return false unless metered_ghe?
    return false unless self.feature_enabled?(:metered_ghe_cc_paypal_payments)
    linked_azure_subscription?
  end

  sig { void }
  def clear_azure_subscription_references!
    customer = self.customer
    return unless customer

    customer.update!(azure_subscription_id: nil, azure_subscription_name: nil)
  end

  sig { returns(T.nilable(T::Boolean)) }
  def metered_ghe_with_azure_subscription?
    metered_ghe? && has_valid_azure_subscription?
  end

  sig { returns(T::Boolean) }
  def display_sales_tax_on_checkout?
    return false unless self.feature_enabled?(:billing_checkout_sales_tax)
    eligible_for_sales_tax?
  end

  # Public: Checks if the account is allowed to have new paid products added to it.
  #         This should be called prior to adding new paid products to the account.
  #
  # actor                    - When provided, checks that the actor is allowed to add new paid products to the account
  # check_disabled           - Whether or not to consider the billing lock status of the account. Defaults to true.
  # check_dunning            - Whether or not to consider the dunning status of the account. Defaults to false.
  # check_trade_restrictions - Whether or not to consider the trade restrictions status of the account. Defaults to false.
  sig do
    params(
      actor: T.nilable(User),
      check_disabled: T::Boolean,
      check_dunning: T::Boolean,
      check_trade_restrictions: T::Boolean
    ).returns(GitHub::Billing::Result)
  end
  def validate_purchases_allowed(actor: nil, check_disabled: true, check_dunning: false,
    check_trade_restrictions: self.feature_enabled?(:always_check_trade_restrictions_for_purchases))
    if self.spammy? || actor&.spammy?
      GitHub::Billing::Result.failure("Your account is flagged and unable to make purchases. " \
        "Please contact support to have your account reviewed.")
    elsif (check_disabled && self.disabled?) || (check_dunning && self.dunning?)
      GitHub::Billing::Result.failure("Your account is currently locked from purchases. " \
        "Please update your payment information.")
    elsif check_trade_restrictions && self.has_any_trade_restrictions?
      GitHub::Billing::Result.failure(TradeControls::Notices.notice_as_plaintext(:user_account_restricted))
    else
      GitHub::Billing::Result.success
    end
  end

  sig { returns(T::Boolean) }
  memoize def shipping_information_required?
    return false unless GitHub.billing_enabled?
    return false unless metered_ghe?
    return false unless self.feature_enabled?(:metered_ghe_shipping_information)
    true
  end

  sig { returns(T::Boolean) }
  memoize def hide_non_azure_payment_methods?
    !!(GitHub.multi_tenant_enterprise? && self.feature_enabled?(:hide_non_azure_payment_methods))
  end

  sig { params(organization: Organization).returns(String) }
  def business_organization_billing_sync_key(organization)
    "business_#{id}_organization_#{organization.id}_billing_sync"
  end

  private

  # Private: Helper method for Enterprise-plan Organization to Enterprise Account upgrade flow.
  # Transfers subscription items and copies the Zuora account from Organization to Business
  sig { params(organization: Organization).void }
  def transfer_customer(organization)
    pending_subscription_item_changes = []
    organization_transferrable_subscription_items(organization).each do |subscription_item|
      subscription_item.organization = organization
      subscription_item.save

      # Save pending subscription item changes to be applied afterwards
      if subscription_item.has_pending_cycle_change?
        pending_subscription_item_changes.append(subscription_item.pending_subscription_item_change)
      end
    end

    self.customer = T.must(organization.customer)   # Assign the upgrading organization's customer to the business
    T.must(self.customer).billing_transactions.push(organization.billing_transactions).distinct
    T.must(self.customer).update!(billing_type: Customer::BILLING_TYPE_CARD)
    self.update!(plan_duration: organization.plan_duration)
    self.update_billing_date(next_billing_date: T.must(organization.billed_on), billing_attempts: T.must(organization.billing_attempts)) if organization.billed_on.present?
    self.save!

    # Apply pending plan changes now that customer is linked to the Business
    pending_subscription_item_changes.each do |pending_subscription_item_change|
      new_pending_plan_change = Billing::PendingPlanChange.new(
        actor_id: actor.id,
        active_on: pending_subscription_item_change.pending_plan_change.active_on,
        customer: self.customer,
      )
      new_pending_plan_change.save

      plan_subscription = pending_subscription_item_change.subscribable_type == "SponsorsTier" ? self.sponsors_plan_subscription : self.plan_subscription
      pending_subscription_item_change.update(
        plan_subscription_id: plan_subscription.id,
        pending_plan_change_id: new_pending_plan_change.id,
        organization_id: organization.id
      )
    end
  end

  # Private: Helper method for Enterprise-plan Organization to Enterprise Account upgrade flow.
  # Builds and returns a list of subscription items that need to have their ownership updated in order to be usable on the EA level.
  # Currently includes marketplace and sponsors subscription items.
  sig { params(organization: Organization).returns(T::Array[Billing::SubscriptionItem]) }
  def organization_transferrable_subscription_items(organization)
    return [] if organization.subscription_items.empty?

    marketplace_items = organization.subscription_items.with_marketplace_listing_plans_type
    sponsorship_items = organization.subscription_items.for_sponsors_tiers

    marketplace_items + sponsorship_items
  end

  # Private: Returns whether payment method supports authorization. Currently credit card and paypal.
  sig { returns(T::Boolean) }
  def payment_supports_authorization?
    return false if self.payment_method.nil?
    return true if self.payment_method.credit_card?
    return true if self.payment_method.paypal?
    false
  end
end
