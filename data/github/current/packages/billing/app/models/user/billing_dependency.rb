# typed: true
# frozen_string_literal: true

require "github/billing"

module User::BillingDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { ::User }

  include Billing::Interfaces::BillableEntity

  include Billing::MeteredBillable
  include Billing::ContactDependency
  include Configurable::SelfServeInvoicePreference
  include Configurable::SeatLimitForUpgrades
  include Scientist
  include GitHub::Memoizer

  INVOICE_BILLING_TYPE = "invoice".freeze
  CARD_BILLING_TYPE = "card".freeze
  BILLING_TYPES = %w( card gift teacher invoice )
  BILLING_ATTEMPTS_LIMIT = 3
  BATCH_SIZE = 1_000
  MYSQL_MAX_ROWS_LIMIT = 250_000

  delegate :zuora_account,
    :reseller_customer?,
    :autopay_disabled_by_trade_controls?,
    :disabled_reasons,
    :billing_disabled_by_authorization_failure?,
    :auto_pay_reasons,
    :billed_via_billing_platform?,
    :was_invoiced?,
    to: :customer, allow_nil: true
  delegate :zuora_account_id, to: :customer, prefix: true, allow_nil: true

  delegate :supports_authorization?, to: :payment_method, prefix: true, allow_nil: true

  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def munich_seats_manageable_by?(actor)
    return false unless organization?
    T.bind(self, ::Organization)

    !delegate_billing_to_business? && plan.per_seat? && billing_manageable_by?(actor)
  end

  sig { returns(String) }
  def billing_account_type
    type
  end

  # The max amount of days passed over all billing attempts
  #
  # 0th day + 7 days (1st retry) + 7 additional days (2nd retry)
  # = 14 day dunning period.
  #
  # https://www.braintreegateway.com/merchants/yrvvxhf7w35y8v9f/processing
  DUNNING_DAYS = 14.days

  # Plan durations. We offer monthly and yearly plans.
  YEARLY_PLAN = "year"
  MONTHLY_PLAN = "month"
  PLAN_DURATIONS = [YEARLY_PLAN, MONTHLY_PLAN]

  module ClassMethods
    # Public: Users who need to be billed for their services as of today
    sig { returns(ActiveRecord::Relation) }
    def needs_billed
      T.bind(self, T.class_of(User))

      unless GitHub.flipper[:use_billing_locked_rather_than_disabled].enabled?
        return deprecated_needs_billed
      end

      select("users.*").
        joins(<<-SQL).
            LEFT OUTER JOIN plan_subscriptions ON users.id = user_id
            LEFT OUTER JOIN payment_methods ON payment_methods.user_id = users.id
            LEFT OUTER JOIN soft_deleted_organizations on soft_deleted_organizations.organization_id = users.id
            LEFT OUTER JOIN customer_accounts ON customer_accounts.user_id = users.id
            LEFT OUTER JOIN customers ON customers.id = customer_accounts.customer_id
        SQL
        where(
          "users.billing_type = 'card'
          AND users.plan IS NOT NULL
          AND users.plan NOT IN (?)
          AND (users.billed_on IS NULL OR users.billed_on <= ?)
          AND users.suspended_at IS NULL
          AND customers.locked_at IS NULL
          AND soft_deleted_organizations.organization_id IS NULL
          AND (plan_subscriptions.zuora_subscription_number IS NULL
            OR plan_subscriptions.zuora_subscription_number IS NOT NULL
            AND (payment_methods.payment_token IS NULL
              OR payment_methods.payment_token = 'payment-token-cleared'))
          AND plan_subscriptions.apple_transaction_id IS NULL",
          GitHub::Plan.free_names,
          GitHub::Billing.today.to_formatted_s(:db),
        )
    end

    # Delete deprecated_needs_billed once use_billing_locked_rather_than_disabled is fully enabled
    sig { returns(::ActiveRecord::Relation) }
    def deprecated_needs_billed
      T.bind(self, T.class_of(User))

      self.select("users.*").
        joins(<<-SQL).
            LEFT OUTER JOIN plan_subscriptions ON users.id = user_id
            LEFT OUTER JOIN payment_methods ON payment_methods.user_id = users.id
            LEFT OUTER JOIN soft_deleted_organizations on soft_deleted_organizations.organization_id = users.id
        SQL
        where(
          "users.billing_type = 'card'
          AND users.plan IS NOT NULL
          AND users.plan NOT IN (?)
          AND (users.billed_on IS NULL OR users.billed_on <= ?)
          AND (users.disabled IS NULL OR users.disabled = ?)
          AND users.suspended_at IS NULL
          AND soft_deleted_organizations.organization_id IS NULL
          AND (plan_subscriptions.zuora_subscription_number IS NULL
            OR plan_subscriptions.zuora_subscription_number IS NOT NULL
            AND (payment_methods.payment_token IS NULL
              OR payment_methods.payment_token = 'payment-token-cleared'))
          AND plan_subscriptions.apple_transaction_id IS NULL",
          GitHub::Plan.free_names,
          GitHub::Billing.today.to_formatted_s(:db),
          false,
        )
    end
  end

  included do
    T.bind(self, T.class_of(User))

    has_many :billing_transactions, class_name: "Billing::BillingTransaction", inverse_of: :live_user
    has_many :billing_transactions_sales, -> { T.unsafe(self).sales },
      class_name: "Billing::BillingTransaction", inverse_of: :live_user
    has_many :line_items, through: :billing_transactions, class_name: "Billing::BillingTransaction::LineItem"
    has_many :billing_disputes, class_name: "Billing::Dispute"

    has_many :pending_plan_changes, class_name: "Billing::PendingPlanChange",
      dependent: :destroy

    has_many :plan_trials, class_name: "Billing::PlanTrial", inverse_of: :user

    has_many :incomplete_pending_plan_changes, -> { T.unsafe(self).incomplete }, class_name: "Billing::PendingPlanChange"
    has_many :pending_subscription_item_changes,
      class_name: "Billing::PendingSubscriptionItemChange",
      through: :incomplete_pending_plan_changes

    has_many :customer_accounts, class_name: "CustomerAccount"
    has_many :customers, class_name: "Customer", through: :customer_accounts
    has_many :plan_subscriptions, class_name: "Billing::PlanSubscription"

    has_one :plan_subscription, -> { T.unsafe(self).general_purpose },
      class_name: "Billing::PlanSubscription",
      dependent: :destroy

    has_many :active_subscription_items, through: :plan_subscriptions,
      source: :active_subscription_items

    has_many :active_marketplace_listing_subscription_items, through: :plan_subscriptions,
      source: :active_marketplace_listing_subscription_items

    has_many :past_subscription_items, through: :plan_subscriptions,
      source: :past_subscription_items

    has_many :subscription_items, through: :plan_subscriptions

    has_one :manual_dunning_period, class_name: "Billing::ManualDunningPeriod",
      dependent: :destroy

    # Some named scopes to make things easier on the nightly billing batch
    # and to provide various user lists under /admin

    # Public: Paying users are trying to give us money
    #
    # Returns iterable User objects
    scope :paying, -> {
      where(
        "plan IS NOT NULL
        AND plan NOT IN (?)
        AND users.billing_type IN (?)", # specifying users column here since customers also has a billing_type column
        GitHub::Plan.free_names,
        %w[card],
      )
    }

    # TODO: Delete second part of ternary once use_billing_locked_rather_than_disabled is fully enabled
    scope :disabled, -> {
      GitHub.flipper[:use_billing_locked_rather_than_disabled].enabled? ? joins(:customers).where.not(customers: { locked_at: nil }) : where(disabled: true)
    }
    # TODO: Delete second part of ternary once use_billing_locked_rather_than_disabled is fully enabled
    scope :not_disabled, -> {
      GitHub.flipper[:use_billing_locked_rather_than_disabled].enabled? ? left_joins(:customers).where(customers: { locked_at: nil }) : where(disabled: false).or(where(disabled: nil))
    }

    # Public: Users who expire in 2 weeks
    #
    # Returns iterable User objects
    scope :expiring_soon, -> {
      if GitHub.flipper[:use_billing_locked_rather_than_disabled].enabled?
        joins(:customers)
        .where(customers: { locked_at: nil })
        .where(
          "(billed_on IS NOT NULL AND billed_on = ?)",
          (GitHub::Billing.today + 2.weeks).to_formatted_s(:db)
        )
      else
        where(
          "(billed_on IS NOT NULL AND billed_on = ?) AND disabled = ?",
          (GitHub::Billing.today + 2.weeks).to_formatted_s(:db),
          false
        )
      end
    }

    scope :yearly, -> { where(plan_duration: YEARLY_PLAN) }

    # Named scopes for the various billing types
    scope :carded,   -> { where(billing_type: CARD_BILLING_TYPE) }
    scope :gift,     -> { where(billing_type: "gift") }
    scope :teacher,  -> { where(billing_type: "teacher") }
    scope :invoiced, -> { where(billing_type: INVOICE_BILLING_TYPE) }

    scope :without_billing_email, -> do
      where(organization_billing_email: nil).or(where(organization_billing_email: ""))
    end

    scope :delegates_billing_to_business, -> do
      if GitHub.single_business_environment?
        none
      else
        users = arel_table
        business_memberships = Business::OrganizationMembership.arel_table
        businesses = Business.arel_table
        business_join = users
          .join(business_memberships).on(users[:id].eq(business_memberships[:organization_id]))
          .join(businesses).on(businesses[:id].eq(business_memberships[:business_id]))
        joins(business_join.join_sources).where(type: "Organization")
      end
    end

    scope :on_paid_plan, -> do
      users = arel_table
      business_memberships = Business::OrganizationMembership.arel_table
      businesses = Business.arel_table
      business_join = users
        .join(business_memberships, Arel::Nodes::OuterJoin).on(users[:id].eq(business_memberships[:organization_id]))
        .join(businesses, Arel::Nodes::OuterJoin).on(businesses[:id].eq(business_memberships[:business_id]))

      paid_plan_names = GitHub::Plan.all.select(&:paid?).map(&:name)
      base_query = joins(business_join.join_sources)
      user_on_paid_plan_not_delegated_to_business = base_query.where(plan: paid_plan_names)
        .where(businesses[:id].eq(nil))
      delegated_to_business_on_paid_plan = base_query.where(businesses[:id].not_eq(nil)).merge(Business.on_paid_plan)

      user_on_paid_plan_not_delegated_to_business.or(delegated_to_business_on_paid_plan)
    end

    after_create   :signup_transaction
    after_update   :update_plan_if_addons_changed, if: :saved_change_to_plan?
    after_update   :cancel_advanced_security_on_downgrade, if: :saved_change_to_plan?
    after_update   :update_external_customer
    after_update   :update_external_subscription, unless: :skip_update_external_subscription

    after_commit   :run_scheduled_external_customer_update, :run_scheduled_subscription_synchronization
    before_destroy :delete_transaction
    has_many       :transactions, after_add: :clear_signup_transaction

    after_commit   :set_billing_email_notice, on: [:create, :update]
    after_commit   :set_org_billing_trouble_notice, on: [:create, :update]
    after_commit   :delete_or_restore_pages_on_plan_change, on: :update
    after_commit   :set_personal_billing_trouble_notice, on: [:create, :update]

    validates_inclusion_of :plan_duration, in: PLAN_DURATIONS
    validates_inclusion_of :billing_type,  in: BILLING_TYPES

    validate :seat_count_greater_than_member_count
    validate :seat_count_greater_than_base_units
    validate :seat_count_no_greater_than_world_population

    # Public: Does this user have a trial active?
    #
    # plan_name - String plan name to check, e.g., "business_plus"; if omitted, the user's current plan is checked
    #
    # Examples
    #
    #   # To prevent N+1s when this method is called on a list of User records, prefill it this way:
    #
    #   # Execute queries to preload, such as in a controller action:
    #   GitHub::PrefillAssociations.prefill_batch_method(users, :plan_trial_active?)
    #   GitHub::PrefillAssociations.prefill_batch_method(users, :plan_trial_active?, "business_plus")
    #
    #   users.each do |user|
    #     # Methods are preloaded and memoized -- no queries are executed here!
    #     user.plan_trial_active?
    #     user.plan_trial_active?("business_plus")
    #   end
    #
    # Returns a Boolean.
    batch_method(:plan_trial_active?, T::Boolean) do |users, plan_name|
      users = Array.wrap(users)
      user = users.first
      base_plan_trial_query = Billing::PlanTrial
      base_plan_trial_query = base_plan_trial_query.for_plan(plan_name) if plan_name

      plan_trials = base_plan_trial_query.for_user(user)
      plan_trials = plan_trials.for_plan(user.plan&.name) unless plan_name
      users.drop(1).each do |user|
        condition_for_user = base_plan_trial_query.for_user(user)
        condition_for_user = condition_for_user.for_plan(user.plan&.name) unless plan_name
        plan_trials = plan_trials.or(condition_for_user)
      end

      plan_trials_by_user_id = plan_trials.includes(:pending_plan_change).index_by(&:user_id)

      users.each_with_object({}) do |user, hash|
        hash[user] = !!plan_trials_by_user_id[user.id]&.active?
      end
    end

    batch_method :billing_locked? do |users|
      GitHub::PrefillAssociations.prefill_associations(users, :customer)

      users.index_with do |user|
        user.customer&.billing_locked?
      end
    end
  end

  sig { returns(T.nilable(T::Boolean)) }
  attr_accessor :skip_update_external_subscription

  delegate \
    :data_packs,
    :payment_amount,
    :plan,
    :plan_duration,
    :billing_interval,
    :seats,
    :has_plan_changes?,
    :changing_plan?,
    :changing_seats?,
    :changing_duration?,
    to: :pending_cycle, prefix: true

  delegate :external_subscription_type, to: :plan_subscription, allow_nil: true

  delegate :metered_billing_eligible?, to: :plan, prefix: true
  delegate :codespaces_eligible?, to: :plan, prefix: true
  delegate :metered_via_azure?, to: :customer, allow_nil: true

  # Public: Users and Organizations are not billed through Azure
  # This method is purely to interface with Business so we don't have to
  # check
  sig { returns(T::Boolean) }
  def billed_through_azure_subscription?
    false
  end

  sig { returns(T::Boolean) }
  def linked_azure_subscription?
    false
  end

  sig { void }
  def synchronize_general_purpose_subscription_later
    get_plan_subscription_or_null_plan.synchronize_later
  end

  sig { params(collect: T.nilable(T::Boolean), wait: T.nilable(ActiveSupport::Duration)).void }
  def synchronize_all_plan_subscriptions(collect: nil, wait: nil)
    plan_subscriptions.each { |plan_sub| plan_sub.synchronize_later(collect:, wait:) }
  end

  sig { returns(::Billing::PlanSubscription) }
  def get_plan_subscription_or_null_plan
    plan_subscription || ::Billing::PlanSubscription.new(user: self)
  end

  sig { returns(T::Boolean) }
  def self_serve_payment?
    !!customer&.self_serve_payment?
  end

  sig { returns(T::Boolean) }
  def business_entity?
    # org_is_on_business_tos? is always defined as false for the User model, but may be true in Organization model
    self.org_is_on_business_tos?
  end

  # Public: Get the user's general-purpose plan subscription
  sig { returns(T.nilable(Billing::PlanSubscription)) }
  def active_plan_subscription
    plan_subscription
  end

  def update_billing_date(next_billing_date:, billing_attempts:)
    update_columns(billed_on: next_billing_date, billing_attempts: billing_attempts)
  end

  # Public: Get the appropriate customer for the specified purpose. Will not fall back to the general-purpose customer
  # if no customer for the specified purpose exists.
  #
  # purpose - :general or :sponsors; treats nil as :general
  # delegate_to_business - whether the customer from the business association should be preferred
  #                        if it exists. When true, will fall back to user's customer if no business exists.
  sig do
    params(
      purpose: T.nilable(T.any(Symbol, String)),
      delegate_to_business: T::Boolean
    ).returns(T.nilable(Customer))
  end
  def customer_for(purpose, delegate_to_business: false)
    if purpose && purpose.to_sym == :sponsors
      return sponsors_customer
    end

    if delegate_to_business
      business&.customer || customer
    else
      customer
    end
  end

  sig { returns(T.nilable(Customer)) }
  def billing_customer
    customer_for(:general, delegate_to_business: delegate_billing_to_business?)
  end

  # Public: Get the appropriate plan subscription for the specified purpose. Will not fall back to the general-purpose
  # plan subscription if no plan subscription for the specified purpose exists.
  sig do
    params(purpose: T.nilable(T.any(Symbol, String))).returns(T.nilable(Billing::PlanSubscription))
  end
  def plan_subscription_for(purpose)
    is_sponsors_purpose = purpose && purpose.to_sym == :sponsors

    if association(:plan_subscriptions).loaded?
      return plan_subscriptions.detect { |plan_sub| plan_sub.sponsors_purpose? == is_sponsors_purpose }
    end

    is_sponsors_purpose ? sponsors_plan_subscription : plan_subscription
  end

  sig { returns(T::Array[Stafftools::User::DisputeRecord]) }
  def billing_dispute_records
    billing_disputes.order(created_at: :desc).map do |dispute|
      Stafftools::User::DisputeRecord.new(dispute)
    end
  end

  # Public: Returns whether a user is eligible to use/sign up for a free trial on a product_uuid or a specific
  # marketplace listing. A user is eligible for marketplace free trial if:
  #  - They have not paid for a plan on this listing in the past
  #  - They have not used a free trial for the listing
  #
  # An optional subscription item can be provided to exclude the item from the checks. For example, when the
  # subscription item is first created, we don't want to check against it since it may be the first subscription item
  # and in that case the user is eligible for the free trial.
  sig do
    params(
      product: T.untyped,
      excluded_subscription_item: T.nilable(Billing::SubscriptionItem)
    ).returns(T::Boolean)
  end
  def eligible_for_free_trial_on?(product:, excluded_subscription_item: nil)
    subscription_items = plan_subscription&.reload&.subscription_items || []
    return true if subscription_items.empty?

    if product.is_a?(Billing::ProductUUID)
      product.eligible_for_free_trial?(subscription_items: subscription_items, excluded_subscription_item: excluded_subscription_item)
    elsif product.is_a?(Marketplace::Listing)
      items = subscription_items.includes(:subscribable).select do |item|
        item.subscribable_Marketplace_ListingPlan? && item.subscribable.marketplace_listing_id == product.id
      end
      items = items.reject { |item| item == excluded_subscription_item } if excluded_subscription_item
      items.none?(&:disqualifies_for_free_trial?)
    else
      false
    end
  end

  sig { void }
  def update_external_customer
    if saved_change_to_login? && self.customer
      schedule_external_customer_update
    end
  end

  # Public: Schedule and immediately run a job to synchronize this user's plan
  # information with the third party provider if there are changes that need to be synchronized
  #
  # See User#update_external_subscription for more information
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
  # See User#create_or_update_external_subscription for more information
  sig { params(kwargs: T.untyped).void }
  def create_or_update_external_subscription_once!(**kwargs)
    create_or_update_external_subscription(**kwargs)
    run_scheduled_subscription_synchronization(one_time_only: true)
  end

  # Public: Create or update external subscription and add data packs to plan.
  sig { void }
  def update_plan_with_data_packs
    update_plan_if_addons_changed

    if external_subscription?
      update_external_subscription!(force: true)
    elsif upcoming_charges?
      T.bind(self, User)
      Billing::PlanSubscription::Transition.activate(self, purpose: :general)
    end
  end

  # Public: If there are billable addons (datapacks or subscription items) and the plan is
  # `free` we should change the plan to `free_with_addons`. The opposite is true when there
  # are no billable addons.
  sig { returns(T.nilable(T::Boolean)) }
  def update_plan_if_addons_changed
    return if destroyed? # Can't update fields on a User that was deleted

    billable_addons = data_packs > 0 || active_subscription_items.exists?
    if plan.free? && billable_addons
      update_column(:plan, GitHub::Plan::FREE_WITH_ADDONS)
    elsif plan.free_with_addons? && !billable_addons
      update_column(:plan, GitHub::Plan::FREE)
    end
  end

  # Public: Reset user's data packs to 0. Used for cleaning up after we've
  # downgraded a user's plan and disabled their repos due to failed billing, etc.
  sig { params(actor: User).void }
  def reset_data_packs(actor: T.cast(self, User))
    old_lfs_count = data_packs

    if asset_status = self.asset_status
      asset_status.update!(data_packs: 0, asset_packs: 0)
    end

    GlobalInstrumenter.instrument(
      "billing.lfs_change",
      actor_id: actor.id,
      user_id: id,
      old_lfs_count: old_lfs_count,
      new_lfs_count: 0,
    )
  end

  sig { returns(T.nilable(GitHub::Result)) }
  def cancel_advanced_security_on_downgrade
    T.bind(self, User)
    return unless self.is_a?(Organization)
    return if delegate_billing_to_business?
    return if self.plan.business_plus?
    return unless self.has_active_advanced_security_subscription?

    cancel_advanced_security_subscription(actor: self, force: true)
  end

  # Public: Reset user's billing attempts to 0. Used for cleaning up after we've
  # downgraded a user's plan.
  sig { returns(T::Boolean) }
  def reset_billing_attempts
    set_billing_attempts(0)
  end

  # Public: Increment the billing attempts for the User.
  sig { returns(User) }
  def increment_billing_attempts
    increment!(:billing_attempts)
  end

  # Public: Set the billing attempts for the User.
  sig { params(attempts: Integer).returns(T::Boolean) }
  def set_billing_attempts(attempts)
    update_column(:billing_attempts, attempts)
  end

  # Public: Reset user's billing date. Used for cleaning up after we've
  # downgraded a user to free.
  sig { returns(T::Boolean) }
  def reset_billed_on
    update!(billed_on: nil)
  end

  # Public: Actions to take after a user is downgraded to free.
  #
  # It is expected that the user does not or will not have an external
  # subscription if this is called.
  sig { void }
  def on_downgrade_to_free
    remove_all_payment_methods(self)
    reset_data_packs
    reset_billing_attempts
    enable_or_disable!
    reset_billed_on
  end

  # Public: Should the user be reminded that their credit card is expiring?
  sig { returns(T::Boolean) }
  def should_remind_about_expiring_card?
    has_credit_card? &&
      card_expiring_in_less_than_three_weeks? &&
      T.must(payment_method).expiration_reminders == 0
  end

  # Public: Has the credit card on file expired?
  sig { returns(T::Boolean) }
  def card_expired?
    return false unless has_credit_card?
    payment_method = T.must(self.payment_method)

    today = GitHub::Billing.today
    T.must(payment_method.expiration_year) < today.year ||
      (payment_method.expiration_year == today.year &&
       T.must(payment_method.expiration_month) < today.month)
  end

  # Public: Is the credit card on file going to expire in the next three
  # weeks?
  sig { returns(T::Boolean) }
  def card_expiring_in_less_than_three_weeks?
    has_credit_card? && T.must(payment_method).expiring_in_less_than_three_weeks?
  end

  # Public: The billing email address for this user.  If not billing_email address
  # is specified, then return the user's default email address
  sig { returns(T.nilable(String)) }
  def billing_email
    organization_billing_email || email
  end

  sig { params(s: T.nilable(String)).returns(T.nilable(String)) }
  def billing_email=(s)
    self.organization_billing_email = s
  end

  sig { returns(T.nilable(T::Boolean)) }
  def billing_email_invalid?
    !billing_email.blank? && billing_email !~ User::EMAIL_REGEX
  end

  sig { void }
  def set_billing_email_notice
    return unless billing_email_invalid?

    Billing::BillingEmailCheckJob.perform_later(self)
  end

  # Public: The user and the organizations owned by the user
  sig { returns(T::Array[T.any(User, Organization)]) }
  def owned_accounts
    owned_organizations + [self]
  end

  # Public: Checks if the given user or any of the user's adminable organizations has an
  # active or canceled subscription item for the given OAuth application or
  # integration, if it is listed in GitHub Marketplace.
  sig { params(app: T.untyped).returns(Promise[T::Boolean]) }
  def async_adminable_account_has_purchased_app?(app)
    app.async_marketplace_listing.then do |listing|
      next false if listing.blank?

      adminable_account_has_purchased_listing?(listing)
    end
  end

  # Public: Checks if the given organizations has an
  # active or canceled subscription item for the given OAuth application or
  # integration through an enterprise, if it is listed in GitHub Marketplace.
  sig { params(app: T.untyped).returns(Promise[T::Boolean]) }
  def async_enterprise_has_purchased_app?(app)
    app.async_marketplace_listing.then do |listing|
      next false if listing.blank?

      enterprise_has_purchased_listing?(listing)
    end
  end

  sig { params(listing: Marketplace::Listing).returns(T::Boolean) }
  def enterprise_has_purchased_listing?(listing)
    return false if self.business.nil?
    ::Billing::SubscriptionItem.for_enterprise(business.customer_id).for_marketplace_listing(listing).exists?
  end

  sig { returns(T::Boolean) }
  def enterprise_has_subscriptions?
    return false if self.business.nil?
    ::Billing::SubscriptionItem.for_enterprise(business.customer_id).exists?
  end

  # Public: Checks if the given user or any of the user's adminable organizations has an
  # active or canceled subscription item for the given Marketplace listing.
  sig { params(listing: Marketplace::Listing).returns(T::Boolean) }
  def adminable_account_has_purchased_listing?(listing)
    adminable_account_ids = adminable_org_ids | [T.must(id)]
    has_subscription_for?(adminable_account_ids, listing)
  end

  # Public: IDs of accounts for the user and any orgs they belong to as member/admin/billing_manager.
  #
  # See https://github.com/github/github/pull/72915 for context on why we all
  # the ids from the org filter here (historically referred to as oap_unscoped)
  sig { returns(T::Array[Integer]) }
  def user_or_org_account_ids
    member_and_admin_org_ids = User::OrganizationFilter.new(self).unscoped_ids
    billing_manageable_org_ids = Ability.where(
        subject_type: "Organization::BillingManagement",
        actor_id: self,
        actor_type: self.ability_type,
        priority: Ability.priorities[:direct],
    ).pluck(:subject_id)

    member_and_admin_org_ids | billing_manageable_org_ids | [T.must(id)]
  end

  # Public: Ids of accounts for the user and any orgs they admin.
  sig { returns(T::Array[Integer]) }
  def user_or_adminable_org_ids
    return @user_or_adminable_org_ids if defined?(@user_or_adminable_org_ids)
    @user_or_adminable_org_ids = adminable_org_ids << T.must(id)
  end

  # Public: Checks if the given user or an org the user is a member/admin/billing manager of has
  # an active or canceled subscription item for the given Marketplace listing.
  sig { params(listing: Marketplace::Listing).returns(T::Boolean) }
  def user_or_org_account_has_purchased_listing?(listing)
    has_subscription_for?(user_or_org_account_ids, listing)
  end

  sig do
    params(
      account_ids: T::Array[Integer],
      listing: Marketplace::Listing
    ).returns(T::Boolean)
  end
  def has_subscription_for?(account_ids, listing)
    ::Billing::SubscriptionItem.for_account(account_ids).for_marketplace_listing(listing).exists?
  end

  # Public: Checks if the given user has an active subscription item for any of
  # the given Marketplace listing plan IDs
  sig { params(subscribable_ids: T::Array[Integer]).returns(T.nilable(T::Boolean)) }
  def has_active_subscription_item_for?(subscribable_ids)
    plan_subscription.present? && active_subscription_items.for_marketplace_listing_plans(subscribable_ids).any?
  end

  # Public: Checks if any of the given user's owned accounts has an active subscription
  # item for the given Marketplace listing.
  sig { params(marketplace_listing: Marketplace::Listing).returns(T::Boolean) }
  def any_active_subscription_items_for_owned_accounts?(marketplace_listing)
    marketplace_listing_plan_ids = marketplace_listing.listing_plans.pluck(:id)

    owned_accounts.any? do |account|
      account.has_active_subscription_item_for?(marketplace_listing_plan_ids)
    end
  end

  # Public: Checks if the given user can administer subscription items owned by this account.
  # This includes cancelling and editing subscription items.
  #
  # user - a User
  # subscribable_type - the String class name of the subscribable, if any
  sig { params(user: T.nilable(User), subscribable_type: T.nilable(String), is_stafftools_action: T::Boolean).returns(T::Boolean) }
  def subscription_items_adminable_by?(user, subscribable_type: nil, is_stafftools_action: false)
    return false unless user
    if subscribable_type == SponsorsTier.name
      SponsorsTier.subscription_items_adminable_by?(sponsor: self, actor: user)
    elsif subscribable_type == Marketplace::ListingPlan.name && enterprise_owned_self_serve_org?
      adminable_by?(user) && plan.account.owner?(user)
    else
      T.bind(self, T.any(User, Organization))
      user == self || adminable_by?(user) || (is_stafftools_action && user.site_admin?) || (is_stafftools_action && user.staff_user?)
    end
  end

  # Public: Schedules a cancellation for all of a user's associated paid subscription items.
  #         This will not remove any in-app purchased subscription items.
  #
  # force             - cancel the subscription items immediately
  # skip_sync         - don't sync with the billing system
  # subscribable_type - the String class name of the subscribable, if any
  #
  # Returns an Array of Billing::Public::SubscriptionItems::ResultStruct
  sig { params(force: T::Boolean, skip_sync: T::Boolean, subscribable_type: T.nilable(String)).returns(T::Array[Billing::Public::SubscriptionItems::ResultStruct]) }
  def cancel_subscription_items!(force: false, skip_sync: false, subscribable_type: nil)
    active_subscription_items.select(&:subscribable_paid?).map do |item|
      next if subscribable_type && item.subscribable_type != subscribable_type

      item.cancel!(force: force, skip_sync: skip_sync)
    end.compact
  end

  # Internal: The Users that should receive billing email
  # for an account.
  sig { returns(T::Array[User]) }
  def billing_users
    [T.cast(self, User)]
  end

  # This is only implemented for an Organization. If calling on a User it will raise a NotImplementedError.
  # It is needed here to satisy Sorbet's type checking. Its implemented in the Organization::BillingManagementDependency for organizations.
  # https://github.com/github/github/blob/a307e696b13c0e47adf5495179b26e1d8424f3b2/packages/billing/app/models/organization/billing_management_dependency.rb#L33-L36
  sig { returns(T.noreturn) }
  def billing_managers
    raise NotImplementedError
  end

  # Internal: The Users that should receive admin email
  # for an account.
  sig { returns(T::Array[User]) }
  def admins
    [T.cast(self, User)]
  end

  sig { returns(T.nilable(CustomerAccount)) }
  def customer_account
    return super if association(:customer_account).loaded?
    customer_accounts.detect(&:general_purpose?)
  end

  sig { returns(T.nilable(Customer)) }
  def customer
    return super if association(:customer).loaded?
    return customer_account&.customer if association(:customer_account).loaded?
    customers.detect(&:general_purpose?)
  end

  # Public: Convenience method to pull out PaymentMethod from this user's Customer
  sig { returns(T.nilable(PaymentMethod)) }
  def payment_method
    return customer&.payment_method if association(:customer).loaded?
    return customer_account&.customer&.payment_method if association(:customer_account).loaded?

    customer_list = customers.to_a
    GitHub::PrefillAssociations.prefill_associations(customer_list, :payment_method)

    general_purpose_customer = customers.detect(&:general_purpose?)
    general_purpose_customer&.payment_method
  end

  # Public: Returns the VAT Identification Number as a String
  #         This was historically stored in billing_extra, but
  #         now should live in customer.vat_code
  sig { returns(T.nilable(String)) }
  def vat_code
    customer.try(:vat_code).presence ||
      ::Billing::VatCode.parse(attributes["billing_extra"])
  end

  # Checks if the org has a linked billing contact
  sig { returns(T::Boolean) }
  def has_linked_billing_contact?
    # If we are checking a "billing_contact" before the flag is enabled, it will be a trade screening record
    return has_linked_trade_screening_record? unless feature_enabled?(:read_billing_information_from_contacts)
    return T.must(@has_linked_billing_contact) if defined?(@has_linked_billing_contact)
    return @has_linked_billing_contact = false unless is_a?(Organization) && organization?

    @has_linked_billing_contact = T.let(nil, T.nilable(T::Boolean))
    @has_linked_billing_contact = Billing::ContactLinkManager.org_has_linked_contact?(address_type: :billing, org: self)
  end

  # Public: Checks if the actor's billing contact is linked to the organization
  sig { params(actor: User).returns(T::Boolean) }
  def has_linked_billing_contact_to_actor?(actor:)
    # If we are checking a "billing_contact" before the flag is enabled, it will be a trade screening record
    return actor.has_trade_screening_record_linked_to_org?(organization: T.cast(self, Organization)) unless feature_enabled?(:read_billing_information_from_contacts)
    # until read_billing_information_from_contacts flag is removed, we need to access billing contact through
    # customer since user#billing_contact can resolve to AccountScreeningProfile if the flag is disabled on the user
    org_billing_contact = customer&.billing_contact
    return false unless org_billing_contact&.persisted?
    billing_contact = actor.customer&.billing_contact
    return false unless billing_contact&.persisted?

    org_billing_contact.id == billing_contact.id
  end

  # Public: Creates a link between a Standard Terms of Service organization and an admin user's billing contact
  sig { params(actor: User).returns(T::Boolean) }
  def link_billing_contact(actor:)
    return false unless is_a?(Organization) && organization?
    return false unless actor.customer&.billing_contact&.persisted?

    return false unless org_is_on_standard_tos?
    return false unless adminable_by?(actor) || billing_manager?(actor)
    return false if actor.has_trade_screening_restriction?

    find_or_create_customer
    result = Billing::ContactLinkManager.link_contact_to_org(address_type: :billing, actor:, org: self)
    reload
    result
  end

  # Public: Removes the link between a an organization and an admin user's billing contact
  sig { params(actor: User).returns(T::Boolean) }
  def unlink_billing_contact(actor:)
    return false unless is_a?(Organization) && organization?

    can_manage_org = adminable_by?(actor) || billing_manager?(actor)
    user_owns_contact = has_linked_billing_contact_to_actor?(actor:)
    return false unless can_manage_org || user_owns_contact

    result = Billing::ContactLinkManager.unlink_contact_from_org(address_type: :billing, actor:, org: self)
    reload
    result
  end

  sig { returns(T::Array[Organization]) }
  def orgs_linked_to_billing_contact
    return [] unless user?
    # until read_billing_information_from_contacts flag is removed, we need to access billing contact through
    # customer since user#billing_contact can resolve to AccountScreeningProfile if the flag is disabled on the user
    return [] unless billing_contact = customer&.billing_contact
    return [] unless billing_contact.persisted?

    self.owned_or_billing_manager_organizations.select \
      { |org| org.billing_contact_link.link_id == billing_contact.id }
  end

  sig { void }
  def unlink_contact_from_all_linked_orgs
    return unless is_a?(User) && user?

    orgs_linked_to_billing_contact.each do |org|
      org.unlink_billing_contact(actor: self)
    end
  end

  # Public: Returns the billing_extra column, unless the column contains
  #         the vat_code
  sig { returns(T.nilable(String)) }
  def billing_extra
    value = attributes["billing_extra"]
    value if value != vat_code
  end

  sig { returns(T.nilable(T::Boolean)) }
  def external_subscription?
    plan_subscription = self.plan_subscription
    plan_subscription.present? && plan_subscription.has_external_subscription?
  end

  sig { returns(T.nilable(T::Boolean)) }
  def any_external_subscriptions?
    external_subscription? || external_sponsors_subscription?
  end

  sig { returns(T.nilable(T::Boolean)) }
  def zuora_subscription?
    plan_subscription = self.plan_subscription
    plan_subscription.present? && plan_subscription.zuora_subscription_number?
  end

  sig { returns(T.nilable(T::Boolean)) }
  def apple_iap_subscription?
    plan_subscription = self.plan_subscription
    plan_subscription.present? && plan_subscription.apple_iap_subscription?
  end

  sig { returns(T::Boolean) }
  def plan_supports_unlimited_private_repos?
    limit = plan_limit(:repos, visibility: :private, fallback_to_free: disabled?)
    limit >= 9999
  end

  # Public: We warn staff who attempt to force a plan downgrade about potential custom roles which will be deleted.
  # This only applies when going from Enterprise plan (business_plus) to any other target.
  #
  sig { returns(T::Boolean) }
  def show_custom_role_downgrade_warning?
    return false unless organization?
    T.bind(self, Organization)

    plan.business_plus? && all_custom_roles.any?
  end

  # Public: If this user has a Zuora account for general-purpose billing.
  sig { returns(T::Boolean) }
  def zuora_account?
    !!customer&.zuora?
  end

  # Public: Returns this customer's payment method token
  sig { returns(T.nilable(String)) }
  def payment_method_token
    payment_method.try(:payment_token)
  end

  # Public: Is this User classified as a gift account?
  sig { returns(T::Boolean) }
  def gift?
    teacher_gift? || billing_type == "gift"
  end

  sig { returns(T::Boolean) }
  def teacher_gift?
    billing_type == "teacher"
  end

  sig { returns(String) }
  def gift_type_description
    if teacher_gift?
      "Teacher/student group"
    elsif gift?
      "Gift"
    else
      "Normal account"
    end
  end

  # Public: Boolean if this user has no upcoming charges to their account
  # because they are either:
  #   - On a gift account type or...
  #   - Have a coupon that covers 100% of their plan
  sig { returns(T::Boolean) }
  def no_upcoming_charges?
    free_trial? || !paying_customer?
  end

  # Public: Boolean inverse of `no_upcoming_charges?`
  sig { returns(T::Boolean) }
  def upcoming_charges?
    !no_upcoming_charges?
  end

  # Public: figures out whether a user needs to input a credit card if they're
  # moving to a paid plan. If you're on a free plan with a $12/mo coupon, you
  # don't need a cc# to upgrade to Micro or Small. But you need one for Medium.
  # If you've already entered your payment information, we don't need it.
  #
  # new_plan - The GitHub::Plan object the user wants to upgrade to.
  #            If passed a String, we'll try to find the GitHub::Plan.
  #
  # Returns a Boolean true if they need to enter in a CC, false otherwise.
  def needs_valid_payment_method_to_switch_to_plan?(new_plan, new_seats = seats, feature_type: :default)
    return false unless GitHub.billing_enabled?

    new_plan = GitHub::Plan.find(
      new_plan,
      effective_at: plan_effective_at,
      account: self
    ) if new_plan.is_a?(String)

    if new_plan.free?
      # First one's free.
      false
    elsif invoiced? || gift? || has_valid_payment_method?(feature_type:)
      # They already entered their card, or they don't need one ever.
      false
    elsif has_an_active_coupon?
      # They have a coupon - see if the discount covers their plan.
      # If they'll owe us money then ask for a card.
      new_plan_price = Billing::Pricing.new(
        account: T.cast(self, User),
        plan: new_plan,
        plan_duration: User::BillingDependency::MONTHLY_PLAN,
        seats: new_seats,
        discount: coupon&.discount,
      ).discounted

      new_plan_price.positive?
    else
      true
    end
  end

  # Public: figures out whether a user needs to input a credit card if they're
  # buying more data packs.
  sig { params(total_packs: Integer).returns(T::Boolean) }
  def needs_valid_payment_method_to_buy_data_packs?(total_packs)
    return false unless GitHub.billing_enabled?

    if invoiced? || has_valid_payment_method?(feature_type: :noncommercial, should_delegate_billing_to_business: true)
      false
    else
      new_price = Billing::Pricing.new(
        account: T.cast(self, User),
        plan_duration: MONTHLY_PLAN,
        data_packs: total_packs,
      ).discounted

      new_price.to_f > 0
    end
  end

  # Public: Charge this user for the current recurring payment amount.
  #
  # Returns GitHub::Billing::Result object indicating the success or
  # failure of the recurring charge
  def recurring_charge
    T.bind(self, User)
    GitHub.logger.info(
      "code.namespace" => self.class.name,
      "code.function" => "recurring_charge",
      "gh.user.login" => login,
      "gh.billing.billable_entity.billed_on" => billed_on,
      "gh.billing.billable_entity.billing_attempts" => billing_attempts,
      "gh.billing.plan_subscription.zuora_subscription_number" => plan_subscription&.zuora_subscription_number
    )

    if external_subscription?
      T.must(plan_subscription).retry_charge
    elsif should_transition_to_external_subscription?
      # Invoices generated after creation of an external subscription will be
      # collected by the CollectZuoraInvoiceJob.
      result = GitHub::Billing.transition_to_external_subscription(
        self, purpose: plan_subscription&.purpose&.to_sym, skip_sync: !!skip_update_external_subscription
      )
      GitHub::Billing::Result.new(result)
    else
      recurring_charge_with_coupon(Billing::Money.new(payment_amount * 100).cents, recurring_charge_type)
    end
  end

  # Public: Charge type label for a recurring charge
  sig { returns(String) }
  def recurring_charge_type
    first_time_charge? ? "first-time-paid-upgrade" : "recurring-charge"
  end

  # Public: Record a $0 charge and move serivce date appropriately.
  #
  # charge_type - String type of charge being made. Usually 'recurring-charge'
  #               or 'prorate-charge'. Optional, default: recurring-charge.
  #
  # Returns GitHub::Billing::Result.success
  def process_zero_charge_transaction(charge_type = nil)
    billing_transaction = log_zero_charge_transaction(charge_type) do |txn|
      if !autoset_bill_cycle_day?
        bcd = customer_bill_cycle_day
        cycle_date = GitHub::Billing.today

        if cycle_date.day >= bcd
          cycle_date = cycle_date.next_month
        end

        self.billed_on = cycle_date.change(day: [bcd, cycle_date.end_of_month.day].min)
      else
        move_billed_on(txn)
      end
      self.billing_attempts = 0
      enable_or_disable!

      # We have to bypass validation, a user may be invalid (e.g. no email address),
      # but we don't want to re-charge them every day they are!
      save(validate: false)
    end

    if customer = self.customer
      if customer_bill_cycle_day.nil? || customer_bill_cycle_day.zero?
        GitHub.dogstats.increment("billing.process_zero_charge_transaction", tags: ["with_customer:true", "bcd_update:true", "billable_entity_type:user"])
        customer.update(bill_cycle_day: billed_on.day)
      else
        GitHub.dogstats.increment("billing.process_zero_charge_transaction", tags: ["with_customer:true", "bcd_update:false", "billable_entity_type:user"])
      end
    else
      GitHub.dogstats.increment("billing.process_zero_charge_transaction", tags: ["with_customer:false", "billable_entity_type:user"])
    end

    GitHub::Billing::Result.success(billing_transaction)
  end

  # Public: Log a $0 billing transaction. If block is provided, call block.
  #         Update end of service metadata (after block finishes if block).
  #
  # charge_type - String type of charge being made. Usually 'recurring-charge'
  #               or 'prorate-charge'. Optional, default: recurring-charge.
  #
  # Returns the new billing transaction.
  def log_zero_charge_transaction(charge_type = nil, **options)
    charge_type ||= recurring_charge_type

    defaults = {
      user: self,
      amount_in_cents: 0,
      transaction_type: charge_type,
      payment_type: :no_charge,
      service_ends_at: billed_on,
    }

    billing_transaction = Billing::BillingTransaction.log defaults.merge(options)

    yield billing_transaction if block_given?

    # Update billing_transaction with actual end-of-service
    service_ends_at = options[:service_ends_at] || billed_on
    billing_transaction.update \
      last_status: :settled,
      transaction_id: billing_transaction.our_transaction_id,
      service_ends_at: service_ends_at

    billing_transaction
  end

  # Public: Remove all credit cards that this account has saved in our payment
  # processor's (Braintree or Zuora) vault.
  #
  # actor - The User taking this action.
  #
  # Returns truthy if all cards are successfully delete.
  def remove_all_payment_methods(actor)
    payment_method = self.payment_method
    payment_method && payment_method.clear_payment_details(actor)
  end

  # Public: Should this user be charged?
  #
  # Returns a Boolean indicating wether we should charge the user
  def past_due?
    return false if plan.free?

    billed_on.nil? || billed_on <= GitHub::Billing.today
  end

  # Is this user getting service that they should be paying for, but aren't?
  #
  # Returns a Boolean
  def beneficiary?
    past_due? && !has_valid_payment_method?(feature_type: :noncommercial, should_delegate_billing_to_business: true) &&
      payment_amount > 0
  end

  # Public: Getter for this User's seat count. If the seats are explicitly
  # set to nil, 0 will be returned. If current object is an organization and
  # belongs to a business we delegate the seat count to the business.
  #
  # Returns an integer representing the number of seats
  def seats
    if delegate_billing_to_business?
      business.total_invitable_purchased_licenses
    else
      super.to_i
    end
  end

  # Public: Setter for this User's plan
  sig { params(new_plan: T.nilable(T.any(Symbol, String, GitHub::Plan))).void }
  def plan=(new_plan)
    write_attribute(:plan, new_plan.to_s)
    @_plan_changed_this_save = true
  end

  # Public: Getter for this User's plan.  If the plan attribute is blank
  # the free default plan is used.
  #
  # Returns the Plan that this user is on or the free default plan
  def plan
    async_plan.sync
  end

  def async_plan
    async_delegate_billing_to_business?.then do |does_delegate_billing_to_business|
      if does_delegate_billing_to_business
        business&.plan
      else
        @plans_by_name ||= {}
        name = plan_name
        @plans_by_name[name] ||= GitHub::Plan.find(name, account: self)
      end
    end
  end

  # Public: Returns the plan's name. See User#plan.
  #
  # Returns String
  def plan_name
    return business&.plan_name if delegate_billing_to_business?

    return GitHub::Plan::EMU_USER if user? && is_enterprise_managed?

    name = read_attribute(:plan)
    return name if name.present?

    GitHub.default_plan_name
  end

  # Public: Previous value according to ActiveModel::Dirty
  sig { returns(T.nilable(GitHub::Plan)) }
  def plan_was
    plan = super
    plan.is_a?(String) ? GitHub::Plan.find(plan) : plan
  end

  sig { returns(T.nilable(GitHub::Plan)) }
  def plan_before_last_save
    plan = super
    plan.is_a?(String) ? GitHub::Plan.find(plan) : plan
  end

  def plan_changed_this_save?
    @_plan_changed_this_save
  end

  def forget_plan_changed_this_save
    unless frozen?
      @_plan_changed_this_save = false
    end
  end

  # Public: The DateTime the user signed up for their current plan
  #
  # Returns DateTime
  def plan_effective_at
    return GitHub::Billing.now unless persisted?
    return @plan_signup_transaction&.timestamp&.in_billing_timezone if @plan_signup_transaction&.timestamp&.in_billing_timezone
    @plan_signup_transaction = ActiveRecord::Base.connected_to(role: :reading) do
      transactions.where(
        action: %w[signed-up downgraded upgraded switched-to-yearly switched-to-monthly],
        current_plan: read_attribute(:plan),
      ).last
    end

    @plan_signup_transaction&.timestamp&.in_billing_timezone ||
      GitHub::Billing.now
  end

  # Public: Find the best fitting repository plan for this user based on
  # their number of repos.
  #
  # Returns GitHub::Plan.free because it always includes unlimited repos now.
  def best_plan
    GitHub::Plan.free
  end

  # Public: The next GitHub::Plan this User or Organization can upgrade to.
  #
  # Returns a GitHub::Plan or nil
  def next_plan
    plans =
      if organization?
        GitHub::Plan.all_non_free_org_plans.
          reject { |p| %w[engineyard unlimited].include? p.name }
      else
        GitHub::Plan.all_non_free_user_plans
      end

    current_plan = plan
    plans = [] if current_plan.name == "unlimited"
    plans.sort.find do |plan|
      repo_limit = organization? ? plan.org_repos : plan.repos
      plan.cost > current_plan.cost && repo_limit > private_repo_count_for_limit_check
    end
  end

  # Public: The next GitHub::Plan this User or Organization can upgrade to.
  #
  # Returns a GitHub::Plan or raises GitHub::Plan::Error if none are available to this user
  def next_plan!
    next_plan || raise(GitHub::Plan::Error, "no plan after #{self.plan.name}")
  end

  sig { returns(String) }
  def plan_duration
    async_plan_duration.sync
  end

  sig { returns(Promise[String]) }
  def async_plan_duration
    async_delegate_billing_to_business?.then do |delegate_billing_to_business|
      if delegate_billing_to_business
        business.async_customer.then do
          business.plan_duration
        end
      else
        self[:plan_duration] || MONTHLY_PLAN
      end
    end
  end

  def alternative_plan_duration
    monthly_plan? ? YEARLY_PLAN : MONTHLY_PLAN
  end

  # Public: Tells if this user is being billed on a yearly basis.
  #
  # Returns true if billing on a yearly cycle.
  def yearly_plan?
    plan_duration == YEARLY_PLAN
  end

  # Public: Tells if this user is being billed on a monthly basis.
  #
  # Returns true if billing on a monthly cycle.
  def monthly_plan?
    plan_duration == MONTHLY_PLAN
  end

  # Converts the wordy plan duration into something you can do math with
  #
  # Returns an Integer representing months
  def plan_duration_in_months
    yearly_plan? ? 12 : 1
  end

  # Public: If the users current plan does not support feature, trigger the removal of the feature
  #
  # Returns nil
  def remove_gated_features
    unless self.feature_enabled?(:pages_soft_deletion, memoize: false)
      unpublish_private_pages unless plan_supports?(:pages, visibility: :private, fallback_to_free: disabled?)
    end
  end

  # Public: Does this user's/org's plan support a gated feature?
  #
  # feature     - The feature Symbol to check (e.g. :codeowners)
  # visibility  - (Optional) The visibility scope. :public or :private.
  # fallback_to_free - (Optional) Should use the free plan instead if the User is disabled. Boolean
  sig do
    override.params(
      feature: Symbol,
      visibility: T.nilable(T.any(Symbol, String)),
      org: T::Boolean,
      feature_flag: T.nilable(T.any(Symbol, String)),
      fallback_to_free: T::Boolean
    ).returns(T::Boolean)
  end
  def plan_supports?(feature, visibility: nil, org: organization?, feature_flag: nil, fallback_to_free: false)
    feature_gated_plan(fallback_to_free: fallback_to_free).
      supports?(feature,
        visibility: visibility,
        org: org,
        feature_flag: plan_override_feature_flag,
      )
  end

  # Public: This org's/user's plan limit for a gated feature.
  #
  # feature     - The feature Symbol to check (e.g. :collaborators)
  # visibility  - (Optional) The visibility scope. :public or :private.
  # fallback_to_free - (Optional) Should use the free plan instead if the User is disabled. Boolean
  #
  # Returns an Integer.
  def plan_limit(feature, visibility: nil, fallback_to_free: false)
    feature_gated_plan(fallback_to_free: fallback_to_free).
      limit(feature,
        visibility: visibility,
        org: organization?,
        feature_flag: plan_override_feature_flag,
      )
  end

  # Public: Whether this user qualifies for HelpHub support
  #
  # eligibiliy_checker - The class used to determine eligibility for HelpHub
  #
  # Returns a ::Billing::HelpHubEligibility
  def help_hub_eligibility
    ::Billing::HelpHubEligibility.new(account: self)
  end

  def billing_attempts_limit
    BILLING_ATTEMPTS_LIMIT
  end

  # Users affected by India RBI regulations cannot use auto-pay or make manual payments via PayPal
  def autopay_disabled_by_india_rbi?
    return false if invoiced?
    return false unless existing_zuora_service?

    customer&.autopay_disabled_by_india_rbi?
  end

  # Public: Whether this user is on an education bundle
  #
  # This is currently only available for sales-serve customers
  #
  # Returns a Boolean
  def education_bundle?
    false
  end

  # Internal: This org's/user's current plan
  #
  # Returns a GitHub::Plan
  private def feature_gated_plan(fallback_to_free: false)
    use_free_plan = fallback_to_free && disabled? && !free_plan?
    if use_free_plan
      @plans_by_name ||= {}
      @plans_by_name["free"] ||= GitHub::Plan.free
    else
      plan
    end
  end

  # Private: Returns the name of a Flipper feature flag if
  #   it is enabled globally or individually for this user/org.
  #
  #   At the moment, we only expect to use one feature flag override at a time.
  #
  #   Any overrides defined in config/plans.yml under `feature_flag_overrides`
  #   for the user/org's plan under the flag name will be preferred.
  #
  # Returns a Symbol, or nil if the feature is not enabled for the user/org
  private def plan_override_feature_flag
    nil
  end

  # Public: Checks if the user is in a billing grace period on their current
  # plan, e.g. upgraded plans or changed to yearly and has not been billed yet.
  #
  # Returns true if the user is in grace period between billing for a monthly
  # plan and a yearly plan
  def in_yearly_grace_period?
    return false unless yearly_plan?
    return false if GitHub::Plan.find(plan_was).try(:free?)
    return false unless billing_transactions.last.try(:monthly?)

    billing_transactions.current.yearly.none? { |t| t.plan_name == plan.name }
  end

  # Public: How much should they actually be paying? Takes into account any discounts
  # their account currently has and any differing plan durations.
  #
  # options - Hash of options
  #        :plan                  - GitHub::Plan object. Defaults to the current plan.
  #        :duration              - Symbol representing duration (e.g. :month or :year)
  #        :duration_in_months    - Duration of requested plan. Defaults to current plan duration in months
  #        :type                  - Price type to return as a Symbol. Optional. Defaults to :final
  #        :plan_seats            - Integer representing the number of seats. Default delegates to #seats
  #        :include_metered_usage - Whether or not to include metered usage in the amount. Defaults to true.
  #
  # Returns a BigDecimal of dollars the person will pay.
  def payment_amount(plan: nil, duration: nil, duration_in_months: nil, type: :final, plan_seats: seats, include_metered_usage: true)
    period = \
      if duration
        duration
      elsif duration_in_months
        duration_in_months == 1 ? :month : :year
      end

    Billing::Pricing.new(
      account: T.cast(self, User),
      plan: plan,
      plan_duration: period,
      seats: plan_seats,
      include_metered_usage: include_metered_usage,
    ).discounted.dollars
  end

  # Public: How much is this user paying not accounting for discounts
  #
  # Returns BigDecimal of dollars
  sig { params(plan: T.nilable(GitHub::Plan), duration: T.nilable(Symbol), plan_seats: Integer).returns(BigDecimal) }
  def undiscounted_payment_amount(plan: nil, duration: nil, plan_seats: seats)
    Billing::Pricing.new(
      account: T.cast(self, User),
      plan: plan,
      plan_duration: duration,
      seats: plan_seats,
    ).undiscounted.dollars
  end

  # Public: Returns the difference in payment amount of moving to a new plan.
  #
  # new_plan    - GitHub::Plan this user is moving to
  # use_balance - Boolean factor in current account balance
  # seat_count  - Integer - the number of seats for the new plan
  #
  # Returns a BigDecimal amount in dollars
  def payment_difference(new_plan, use_balance: false, seat_count: seats)
    if external_subscription?
      plan_change = Billing::PlanChange.new \
        subscription,
        Billing::Subscription.for_account(self, plan: new_plan, seats: seat_count),
        starting_new_subscription: !self.external_subscription?
      plan_change.final_price(use_balance: use_balance).dollars
    else
      payment_amount(plan: new_plan, plan_seats: seat_count) - payment_amount
    end
  end

  def undiscounted_payment_difference(new_plan, seat_count: seats)
    undiscounted_payment_amount(plan: new_plan, plan_seats: seat_count) - undiscounted_payment_amount
  end

  # Public: Return a Billing::Subscription to model this user's plan subscription
  #
  # plan_subscription - Billing::PlanSubscription to use for this user/org; optional, defaults to
  #                     general-purpose plan subscription for the user/org
  #
  # Returns a Billing::Subscription
  def subscription(plan_subscription: nil)
    Billing::Subscription.for_account(self, plan_subscription: plan_subscription)
  end

  # Public: The balance on the customer's specified subscription. Negative means they have a
  # credit.
  #
  # purpose - Symbol indicating the billing purpose of the subscription to look up for this user/organization,
  #           either :general or :sponsors
  #
  # Returns dollars in BigDecimal or 0
  def balance(purpose: Customer::DEFAULT_PURPOSE)
    plan_sub = plan_subscription_for(purpose)
    plan_sub&.balance || 0
  end

  # Public: The balance in cents on the customer's specified subscription. Negative means they have a
  # credit.
  #
  # purpose - Symbol indicating the billing purpose of the subscription to look up for this user/organization,
  #
  # Returns cents in Integer or 0
  def balance_in_cents(purpose: Customer::DEFAULT_PURPOSE)
    plan_sub = plan_subscription_for(purpose)
    plan_sub&.balance_in_cents || 0
  end

  # The credit the customer has on their subscription. Positive means they have
  # a credit
  #
  # Returns dollars in BigDecimal or 0
  def credit
    -1 * balance
  end

  # Whether a user has any credit.
  #
  # Returns true if a user has any credit
  def has_credit?
    credit > 0
  end

  # The next amount the customer will be charged. Includes the balance on the
  # customer's account.
  #
  # Returns non-negative dollars in BigDecimal or 0
  def next_charge_amount
    return [(payment_amount + balance), 0].max if balance < 0

    plan_subscription&.active? ? balance : payment_amount
  end

  def free_plan?
    plan.free? && !plan.coupon?
  end

  # Public: Returns a promise that resolves to a Boolean indicating whether this User has an
  # active subscription to the Marketplace listing with the given database ID.
  def async_has_purchased_marketplace_listing?(listing_id)
    listing_plans_ids = Marketplace::ListingPlan.where(marketplace_listing_id: listing_id).pluck(:id)
    async_plan_subscription.then { active_subscription_items.for_marketplace_listing_plans(listing_plans_ids).exists? }
  end

  # Public: Integer number of default seats when starting a per-seat plan
  def default_seats(new_plan: nil)
    check_plan = new_plan ? new_plan : self.plan
    check_seats = self.plan.paid? ? seats : 0
    base = check_plan.per_seat? ? check_plan.base_units : 0
    [check_seats, filled_seats, base].max
  end

  # Public: Integer number of seats that are in use.
  #
  # How filled seats is calculated:
  #
  #     direct organization members and admins
  #   + outside collaborators on private repositories
  #   + outside collaborators on private repositories with pending invites
  #   + any invited direct members
  #   + any invited admins
  # ---------------------------
  #     filled seats
  #
  # Returns an Integer of the number of seats occupied by users.
  def filled_seats
    return @filled_seats if defined?(@filled_seats) && @cache_billing_data

    GitHub.dogstats.time("organization", tags: ["action:filled_seats"]) do
      @filled_seats =
        if delegate_billing_to_business?
          business.consumed_invitable_licenses
        elsif organization?
          Organization::LicenseAttributer.new(self).unique_count
        else
          collaborators_on_private_repositories.count + 1
        end
    end
  end

  # Returns the user/org with billing data caching enabled.
  # This is intended to cache the results for expensive methods like filled_seats which
  # can be called multiple times directly and indirectly in a single page load.
  def with_billing_data_caching
    @cache_billing_data = true
    self
  end

  # Public: Integer number of seats that need to be *added* to support the
  #         number of collaborators to make the passed repository private or to
  #         transfer the private repository to this organization.
  #
  # repository - Repository to check
  # pending_cycle - Boolean to check pending cyle rather than current plan/seats. Default false.
  # Returns an Integer
  def seats_needed_for_collaborators_on(repository, pending_cycle: false)
    return repository.filled_seats if user?
    return 0 if GitHub.enterprise?
    return 0 if !pending_cycle && plan.per_repository?
    return 0 if pending_cycle && pending_cycle_plan.per_repository?

    if delegate_billing_to_business?
      if business == repository.business
        return 0
      end

      business.additional_licenses_required_for_repository(repository)
    else
      repository_user_ids = repository.member_ids + repository.repository_invitations.where.not(invitee_id: nil).pluck(:invitee_id)
      repository_emails = repository.repository_invitations.where.not(email: nil).pluck(:email).map(&:downcase)
      organization_license_attributer = Organization::LicenseAttributer.new(self)
      needed_seats = (repository_user_ids.to_set - organization_license_attributer.user_ids).size +
        (repository_emails.to_set - organization_license_attributer.emails).size
      [needed_seats - (pending_cycle ? pending_cycle_available_seats : available_invitable_seats), 0].max
    end
  end

  # Public: checks if a user is an outside collaborator. This will perform better than
  #         calling `outside_collaborators.include?` as it won't query for all outside
  #         collaborators.
  #         Note: this should only be called on organization objects, not User objects.
  # repo_ids - specific repo ids to check
  #
  # Returns a boolean
  def user_is_outside_collaborator?(user_id, repository_ids = [])
    org_membership = Ability.where(
      actor_id: user_id,
      subject_id: id,
      actor_type: "User",
      subject_type: "Organization",
      priority: Ability.priorities[:direct],
    )
    return false if org_membership.exists?

    user_collaborates_on_any_repositories?(user_id, repository_ids)
  end

  def user_collaborates_on_any_repositories?(user_id, repository_ids = [])
    repo_ids = Array(repository_ids)

    if repo_ids.empty?
      repo_ids = Repository.active.where(organization_id: id).pluck(Arel.sql("/*vt+ IGNORE_MAX_MEMORY_ROWS=1 */ id"))
    end

    return false if repo_ids.empty?

    batched_repo_ids = repo_ids.uniq.in_groups_of(BATCH_SIZE, false)
    user_collab_repo_ids = Ability.direct.where(
      actor_type: "User", actor_id: user_id, subject_type: "Repository",
    ).pluck(:subject_id)

    batched_repo_ids.any? do |ids|
      user_collab_repo_ids.intersection(ids).count > 0
    end
  end

  def outside_collaborators_count
    outside_collaborator_ids.count
  end

  # Public: Get all the other users who have access to this user's
  # repositories (that aren't members of the org).
  #
  # Note: This is a fairly expensive method, and it's not memoized so that it
  # won't act weird after changing organization membership and repo access. If
  # you need to access this multiple times in one request, save it in a variable
  # first.
  #
  # on_repositories_with_visibility - Array of symbols defining visibility of
  #                                   repositories whose collaborators we're
  #                                   looking for. Valid values are :public and
  #                                   :private. Default: [:public, :private]
  #
  # include_forks                   - A Boolean value of whether to include
  #                                   counting forked repositories
  #                                   Default: true
  #
  # Returns a User scope.
  def outside_collaborators(on_repositories_with_visibility: [:public, :private], include_forks: true)
    ids = outside_collaborator_ids(on_repositories_with_visibility: on_repositories_with_visibility, include_forks: include_forks)

    User.where(id: ids)
  end

  def outside_collaborator_ids(on_repositories_with_visibility: [:public, :private], include_forks: true, actor_ids: nil, skip_cache: false, force_cache: false)
    return [] if new_record?

    visibility = on_repositories_with_visibility.map do |visibility|
      { public: 1, private: 0 }[visibility]
    end.compact

    # if both visibility options are included (public and private), then _all_
    # repos are included and repository_visibility is nil so that it isn't
    # included in the query as a filter
    repository_visibility = visibility.first if visibility.count == 1

    permission_cache_key = ["outside_collaborator_ids_no_join", id,
                            on_repositories_with_visibility,
                            (:exclude_forks unless include_forks)].compact

    if self.is_a?(Organization) && !skip_cache && !force_cache && feature_enabled?(:collaborator_cache_write) && !feature_enabled?(:collaborator_cache_read)
      return science "collaborator_cache_org_experiment" do |e|
        e.context({ org_id: id, on_repositories_with_visibility: on_repositories_with_visibility, include_forks: include_forks, actor_ids: actor_ids })
        e.compare do |control, candidate|
          control.sort == candidate.sort
        end
        e.try do
          outside_collaborator_ids(
            on_repositories_with_visibility: on_repositories_with_visibility,
            include_forks: include_forks,
            actor_ids: actor_ids,
            force_cache: true
          )
        end
        e.use do
          outside_collaborator_ids(
            on_repositories_with_visibility: on_repositories_with_visibility,
            include_forks: include_forks,
            actor_ids: actor_ids,
            skip_cache: true
          )
        end
      end
    end

    PermissionCache.fetch permission_cache_key do
      if self.is_a?(Organization) && ((feature_enabled?(:collaborator_cache_read) && !skip_cache) || force_cache)
        query = OrganizationCollaborator.where(organization_id: id)
        query = if visibility.size == 1
          if on_repositories_with_visibility.include?(:public)
            if include_forks
              query.where(public: true).or(OrganizationCollaborator.where(public_only_forks: true))
            else
              query.where(public: true)
            end
          else
            if include_forks
              query.where(private: true).or(OrganizationCollaborator.where(private_only_forks: true))
            else
              query.where(private: true)
            end
          end
        elsif !include_forks
          query.where(private_only_forks: false, public_only_forks: false)
        else
          query
        end
        query = query.where(user_id: actor_ids) unless actor_ids.nil?
        return query.pluck(:user_id).to_set
      end

      repos = Repository.active
      repos = repos.where(public: repository_visibility) if repository_visibility
      repos = repos.where(parent_id: nil) unless include_forks
      if organization?
        repos = repos.where(organization_id: id)
      else
        repos = repos.where(owner_id: id)
      end

      # Remove advisory workspaces from the list of repos.
      # Collaborators on advisory workspaces are not considered
      # outside collaborators and should not count towards seats
      repos = remove_advisory_workspaces(repos)

      repo_ids = repos.limit(MYSQL_MAX_ROWS_LIMIT).ids

      return [] if repo_ids.empty?

      repo_ability_ids = Set.new

      abilities_scope = Ability.where(
        actor_type: "User",
        subject_type: "Repository",
        priority: Ability.priorities[:direct],
      )

      if actor_ids
        abilities_scope = abilities_scope.where(actor_id: actor_ids)
      end

      repo_ids.in_groups_of(1000, false) do |rids|
        repo_ability_ids.merge abilities_scope.where(subject_id: rids).distinct.pluck(:actor_id)
      end

      org_abilities_scope = Ability.where(
        subject_id: id,
        actor_type: "User",
        subject_type: "Organization",
        priority: Ability.priorities[:direct],
      )

      if actor_ids
        org_abilities_scope = org_abilities_scope.where(actor_id: actor_ids)
      end

      org_member_ids = org_abilities_scope.distinct.pluck(:actor_id)

      repo_ability_ids - org_member_ids
    end
  end

  # Internal: Is the user already using the zuora service?
  #
  # Returns Boolean
  def existing_zuora_service?
    payment_method&.on_zuora? || zuora_subscription?
  end

  # Internal: IDs of users invited to collaborate
  def pending_non_manager_invited_user_ids
    T.bind(self, Organization)

    pending_non_manager_invitations.excluding_expired.pluck(:invitee_id).compact
  end

  # Internal: A list pending email addresses not associated with user invited to join the organization.
  def pending_invited_non_user_emails
    T.bind(self, Organization)

    pending_non_manager_invitations.excluding_expired.where("normalized_email IS NOT NULL and invitee_id IS NULL").pluck(:normalized_email)
  end

  # Internal: collaborators on private repositories only
  def collaborators_on_private_repositories
    outside_collaborators(on_repositories_with_visibility: [:private], include_forks: false)
  end

  def user_ids_with_private_repo_access
    return [] if new_record?
    repos = Repository.active.private_scope.where(parent_id: nil)

    if organization?
      repos = repos.where(organization_id: id)
    else
      repos = repos.where(owner_id: id)
    end

    # Remove advisory workspaces from the list of repos.
    # Collaborators on advisory workspaces are not considered
    # outside collaborators and should not count towards seats
    repos = remove_advisory_workspaces(repos)

    repo_ids = repos.limit(MYSQL_MAX_ROWS_LIMIT).ids

    return [] if repo_ids.empty?

    user_ids = []

    repo_ids.each_slice(5000) do |rids|
      user_ids.concat Ability.where(subject_id: rids).where(
        actor_type: "User",
        subject_type: "Repository",
        priority: Ability.priorities[:direct],
        ).group(:subject_id, :subject_type, :priority, :actor_type, :actor_id).pluck(:actor_id)
    end
    user_ids
  end

  # Internal: returns invited users that are not already collaborating either
  # as contributors or outside collaborators in the organization
  def private_repo_non_collaborator_invitee_ids
    T.bind(self, Organization)

    private_repo_invitee_ids -
      people_ids -
      collaborators_on_private_repositories.pluck(:id) -
      pending_non_manager_invited_user_ids
  end

  # Internal: User ids of users who have been invited to collaborate on private repositories.
  # This list may contain ids of users who may already be members of the organization or
  # outside collaborators.
  def private_repo_invitee_ids
    owned_private_repositories
      .joins(:repository_invitations)
      .merge(RepositoryInvitation.excluding_expired)
      .where("email IS NULL and invitee_id IS NOT NULL")
      .pluck(Arel.sql("DISTINCT repository_invitations.invitee_id"))
  end

  # Internal: A list pending email addresses not associated with users invited to collaborate on org private repositories.
  def private_repo_non_user_invited_emails
    owned_private_repositories
      .joins(:repository_invitations)
      .merge(RepositoryInvitation.excluding_expired)
      .where("email IS NOT NULL and invitee_id IS NULL")
      .distinct
      .pluck(:email)
      .map(&:downcase)
  end

  # Internal: Users that are collaborators on private repositories only and have
  # NOT been invited to be a member/admin of the organization.
  #
  # Returns an Array of Users
  def collaborators_on_private_repositories_without_invitations
    collaborators_on_private_repositories.map(&:id) -
      pending_non_manager_invited_user_ids
  end

  # Public: returns float percentage of seats that are in use
  def filled_seats_percent
    return 0 unless plan.per_seat?
    cached_filled_seats = filled_seats

    # Return early to avoid comparing `0/0` (= `NaN` to 100) when we call `#min` on the
    # array below
    return 0 if seats.zero? && cached_filled_seats.zero?

    # There won't be devide by zero errors here since `cached_seats` will be non-zero
    # and in floating point arithmetic `n / 0` will return `Infinity` for positive `n`
    # values and `-Infinity` for negative `n` values - both of which can be compared
    # to 100.
    [(cached_filled_seats / seats.to_f * 100).round(1), 100].min
  end

  # Public: returns integer number of seats that are not in use
  def available_invitable_seats
    if delegate_billing_to_business?
      business.available_invitable_licenses
    else
      [seats - filled_seats, 0].max
    end
  end

  # Public: returns integer number of seats that are not in use including non-invitable seats
  def total_available_seats
    if delegate_billing_to_business?
      business.total_available_licenses
    else
      available_invitable_seats
    end
  end

  def pending_cycle_available_seats
    [pending_cycle_seats - filled_seats, 0].max
  end

  # Public: Boolean if on a per seat plan and at the seat limit (no available
  # seats). Always false for organizations on repository plans.
  # Pending Cycle - Boolean if at seat limit for pending cycle. Default false.
  def at_seat_limit?(pending_cycle: false)
    return false if has_unlimited_seats?

    if pending_cycle
      pending_cycle_plan.per_seat? && pending_cycle_available_seats < 1
    else
      plan.per_seat? && available_invitable_seats < 1
    end
  end

  # Public: Boolean if on a per seat plan and can give a seat to the user.
  # Always true for organizations on a repository plan.
  # Pending Cycle - Boolean if has seats for pending cycle. Default false.
  def has_seat_for?(user, pending_cycle: false)
    return true if has_unlimited_seats?

    if delegate_billing_to_business?
      business.has_sufficient_licenses_for?(user: user)
    else
      !at_seat_limit?(pending_cycle: pending_cycle) ||
        Organization::LicenseAttributer.new(self).user_ids.include?(user&.id)
    end
  end

  # Public: Boolean if on a per seat plan and can give a seat to the users.
  # Always true for organizations on a repository plan.
  # Pending Cycle - Boolean if has seats for pending cycle. Default false.
  def has_seats_for?(user_ids, pending_cycle: false)
    return true if has_unlimited_seats?

    if delegate_billing_to_business?
      business.has_sufficient_licenses_for_users?(user_ids: user_ids)
    else
      !at_seat_limit?(pending_cycle: pending_cycle) ||
        (user_ids - Organization::LicenseAttributer.new(self).user_ids.to_a).empty?
    end
  end

  # Public: Boolean if on a per seat plan and can give a seat to the email.
  # Always true for organizations on a repository plan.
  #
  # email String of the email to check
  # pending_cycle: Boolean if has seats for pending cycle. Default false.
  #
  # Returns Boolean
  def has_seat_for_email?(email, pending_cycle: false)
    T.bind(self, ::Organization)

    return true if has_unlimited_seats?


    if delegate_billing_to_business?
      T.must(business).has_sufficient_licenses_for?(email: email)
    else
      !at_seat_limit?(pending_cycle: pending_cycle) ||
        pending_invitation_for(email: email)
    end
  end

  # Public: Whether the organization has an unlimited seat count
  sig { returns(T::Boolean) }
  memoize def has_unlimited_seats?
    if delegate_billing_to_business?
      return true if T.must(business).has_unlimited_seats?
    end

    has_unlimited_seat_coupon?
  end

  # Public: Whether the organization has a coupon applied to give unlimited seats
  sig { returns(T::Boolean) }
  def has_unlimited_seat_coupon?
    !!(has_an_active_coupon? && T.must(coupon).trial?)
  end

  # Public: Whether their plan has unlimited private repos
  sig { returns(T::Boolean) }
  def has_unlimited_private_repositories?
    feature_gated_plan.unlimited?(org: organization?, feature_flag: plan_override_feature_flag)
  end

  sig { returns(T::Boolean) }
  def has_downgradable_seats?
    seats > plan.base_units && available_invitable_seats > 0
  end

  sig { returns(T::Boolean) }
  def per_seat_plan_only?
    organization? && (plan.free? || plan.per_seat?)
  end

  # Public: Is this a user on the new personal plan (free tier).
  # TODO: Move this to plan.rb once we no longer need the feature flags.
  sig { returns(T::Boolean) }
  def personal_plan?
    user? && (plan.free? || plan.free_with_addons?)
  end

  # Public: Is this an org on the free plan.
  # TODO: Move this to plan.rb once we no longer need the feature flags.
  sig { returns(T::Boolean) }
  def org_free_plan?
    organization? && (plan.free? || plan.free_with_addons?)
  end

  sig { returns(T::Boolean) }
  def org_business_plan?
    organization? && plan.business?
  end

  sig { returns(T::Boolean) }
  def org_business_plus_plan?
    organization? && plan.business_plus?
  end

  sig { returns(Asset::Status) }
  def new_or_asset_status
    asset_status || Asset::Status.new(asset_type: :lfs, owner: self)
  end

  # Public: Integer number of data packs this user/org has purchased.
  sig { returns(Integer) }
  def data_packs
    new_or_asset_status.asset_packs
  end

  # Public: Money price of all current data packs for current plan duration.
  def data_pack_price
    data_pack_monthly_price * plan_duration_in_months
  end

  # Public: Money price of all current data packs per month.
  def data_pack_monthly_price
    data_packs * Asset::Status.data_pack_unit_price
  end

  # Public: Integer days remaining in the current lfs cycle.
  sig { returns(T.nilable(Integer)) }
  def days_remaining_in_lfs_cycle
    if free_plan?
      first_day = first_day_in_lfs_cycle
      return unless first_day

      end_date = first_day + 1.month
      today = GitHub::Billing.today
      (end_date - today).to_i
    else
      subscription.service_days_remaining
    end
  end

  # Public: Integer percent remaining in billing cycle.
  sig { returns(Integer) }
  def percent_passed_in_billing_cycle
    100 - (subscription.service_percent_remaining * 100).to_i
  end

  def first_day_in_lfs_cycle
    if free_plan?
      # We're a not a paying customer thus have no billing date to go off of, so
      # lets check when the user started using LFS
      status_created_at = self.new_or_asset_status.created_at&.in_billing_timezone
      # If the user has never used LFS, give up
      return if status_created_at.nil?

      today = GitHub::Billing.today
      last_month_day = today.end_of_month.day
      day = [status_created_at.day, last_month_day].min
      first_day = ::GitHub::Billing.today.change(day: day)
      if first_day > today
        [first_day - 1.month, status_created_at.to_date].max
      else
        first_day
      end
    else
      if invoiced? && billing_start_date = plan_subscription&.billing_start_date
        start = billing_start_date
        today = ::GitHub::Billing.today
        year = today.year
        if Date.new(year, start.month, start.day) > today
          year -= 1
        end
        Date.new(year, start.month, start.day)
      else
        T.must(next_billing_date) - (yearly_plan? ? 1.year : 1.month)
      end
    end
  end

  sig { override.returns(T::Boolean) }
  def paid_plan?
    async_paid_plan?.sync
  end

  sig { returns(Promise[T::Boolean]) }
  def async_paid_plan?
    async_plan.then do |plan|
      plan.try(:paid?)
    end
  end

  # Checks whether the user (org) is on an enterprise trial plan. This is used
  # to gate certain features to orgs that are not on trials.
  sig { returns(T::Boolean) }
  def paid_non_trial_plan?
    paid_plan? && !Billing::EnterpriseCloudTrial.new(self).active?
  end

  # Public: Checks to see if the user can change to a particular plan by an actor.
  #         If no actor is defined, it assumes the user itself.
  sig { params(target_plan: T.any(String, Symbol, GitHub::Plan), actor: User).returns(T::Boolean) }
  def can_change_plan_to?(target_plan, actor: T.cast(self, User))
    T.bind(self, User)

    Billing::ChangeSubscription.can_perform?(self, plan: target_plan.to_s, actor: actor)
  end

  sig { returns(T::Boolean) }
  def paying_customer?
    !!(!gift? && paid_plan?)
  end

  # Public: A user's manual payment due date.
  #
  # Currently only applies to users that have been placed in manual dunning due to India RBI and Auto Pay set to false.
  #
  # Returns nil if the user is not in manual dunning
  # Returns a Date if the user is in manual dunning
  def manual_payment_due_date
    manual_dunning_period&.due_date
  end

  sig { returns(T::Boolean) }
  def manual_dunning?
    manual_dunning_period.present? && balance.positive?
  end

  sig { returns(T::Boolean) }
  def can_be_manually_charged?
    has_billing_record? && has_valid_payment_method?
  end

  # Public: Is this user/org being billed via invoice?
  sig { override.returns(T::Boolean) }
  def invoiced?
    async_invoiced?.sync
  end

  sig { returns(Promise[T::Boolean]) }
  def async_invoiced?
    return T.cast(Promise.resolve(true), Promise[T::Boolean]) if billing_type == INVOICE_BILLING_TYPE
    async_business.then do |business|
      if business&.self_serve_payment?
        next Promise.resolve(false)
      end
      business.present?
    end
  end

  # Public: Switch to credit card billing
  sig { params(actor: User).returns(T::Boolean) }
  def switch_billing_type_to_card(actor)
    T.bind(self, User)

    User::CardConverter.new(self).convert(actor: actor)
  end

  # Public: Switch to invoice billing
  sig { params(actor: User).returns(T::Boolean) }
  def switch_billing_type_to_invoice(actor)
    T.bind(self, User)

    User::InvoiceConverter.new(self).convert(actor: actor)
  end

  # Check if the user has any billing transactions.
  sig { returns(T::Boolean) }
  def has_billing_transactions?
    billing_transactions.present?
  end

  # Public: Boolean if the user has valid billing information on Zuora.
  sig { override.returns(T::Boolean) }
  def has_billing_record?
    zuora_account?
  end

  # Public: Boolean if a user has a valid credit card on their account
  sig { returns(T::Boolean) }
  def has_credit_card?
    payment_method = self.payment_method
    !!(payment_method.present? && payment_method.credit_card?)
  end

  # Public: Boolean if a user has a valid paypal account registered.
  sig { returns(T::Boolean) }
  def has_paypal_account?
    payment_method = self.payment_method
    !!(payment_method.present? && payment_method.paypal?)
  end

  # Public: Check if this user has a valid payment method on file for use with any purchase or subscription.
  #
  # feature_type - by default we require valid contact info to be present before performing any commercial interactions. There are some scenarios where it is okay to bypass this check.
  #   For any scenarios where the check is made for non-commercial interactions, use ':noncommercial' feature type (example when allowing a customer to remove a payment method)
  # check_for_stopgap_restriction - whether stopgap restriction should be checked before checking for valid payment
  # should_delegate_billing_to_business - whether to delegate billing to business for enterprise linked organization
  sig { params(feature_type: Symbol, check_for_stopgap_restriction: T::Boolean, should_delegate_billing_to_business: T::Boolean).returns(T::Boolean) }
  def has_valid_payment_method?(feature_type: :default, check_for_stopgap_restriction: false, should_delegate_billing_to_business: false)
    return false if check_for_stopgap_restriction && has_lic_r_stopgap_restriction?
    unless should_delegate_billing_to_business
      should_delegate_billing_to_business = true if feature_enabled?(:delegate_valid_payment_method_to_business)
    end
    return business.has_valid_payment_method?(feature_type:) if should_delegate_billing_to_business && delegate_billing_to_business?

    payment_method = self.payment_method
    return false unless payment_method.present?
    return false unless payment_method.valid_payment_token?
    has_valid_trade_screening_record_for_payment?(feature_type:)
  end

  # Public: String friendly name for the payment method on file.
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

  # Public: Set a new date to bill this user on.
  def billed_on=(date)
    unless date.nil? || date.is_a?(Date)
      raise TypeError, "expected a Date, got #{date.inspect} instead. " \
        "Hint: #to_billing_date can be used to convert a Time into the right Date according to the billing timezone."
    end

    self[:billed_on] = date
  end

  def billed_on
    if delegate_billing_to_business?
      business.billed_on
    else
      self[:billed_on]
    end
  end

  # Public: The first date of the next billing cycle.
  #         For accounts in good standing, this is the next day we will
  #         automatically bill on.
  #
  #  with_dunning - Boolean. Whether to consider our dunning process when
  #                          calculating the date for a past due account.
  #         When false, returns today's date for past due accounts.
  #              (this is used in billing calculations when renewing an account
  #               to determine when the next cycle should begin)
  #         When true, returns the next day we will automatically attempt to
  #              charge the account's stored payment method, assuming that the
  #              user takes no action. This can return nil if no further
  #              attempts will be made.
  #         Defaults to false.
  sig { params(with_dunning: T::Boolean).returns(T.nilable(Date)) }
  def next_billing_date(with_dunning: false)
    next_billing_date = billed_on || GitHub::Billing.today
    if with_dunning
      next_dunning_day = [0, 7, 15][billing_attempts.to_i]
      return unless next_dunning_day
      next_billing_date + next_dunning_day.days
    else
      [next_billing_date, GitHub::Billing.today].max
    end
  end

  # Public: The next date that the account will be billed for their GitHub plan
  sig { returns(T.nilable(Date)) }
  def github_plan_next_billing_date
    return next_billing_date unless external_subscription?
    plan_subscription = T.must(self.plan_subscription)
    product_rate_plan_charge_id = plan.zuora_charge_ids(cycle: plan_duration)&.values&.first

    zuora_rate_plan_charges = plan_subscription.zuora_rate_plan_charges
    use_cache = zuora_rate_plan_charges.present? && !!zuora_rate_plan_charges[product_rate_plan_charge_id]&.has_key?(:charged_through_date)
    if use_cache
      zuora_rate_plan_charges.dig(product_rate_plan_charge_id, :charged_through_date)
    elsif external_subscription = plan_subscription.external_subscription
      external_subscription.charged_through_date_for(product_rate_plan_charge_id: product_rate_plan_charge_id)
    end
  end

  # Public: The soonest date a free trial will be ending for the user
  #
  # Returns a Date
  def next_free_trial_end_date
    if free_trials
      free_trials.order(:free_trial_ends_on).first&.free_trial_ends_on
    end
  end

  # Public: The next time the user will need to make a payment
  #
  # Returns a Date
  def next_payment_due_on
    [billed_on, next_free_trial_end_date].compact.sort.first
  end

  # Public: The users subscription items that are on a current free trial
  #
  # Returns an ActiveRecord::Relation of SubscriptionItems
  def free_trials
    active_subscription_items.free_trials if active_subscription_items.present?
  end

  # Public: The previous billed_on based on the cycle.
  #
  # cycles - How many cycles to count the billing date. Defaults to 1
  #
  # Returns a Date
  def previous_billing_date(cycles: 1)
    billing_date = billed_on || GitHub::Billing.today

    if monthly_plan?
      billing_date - cycles.month
    else
      billing_date - cycles.year
    end
  end

  # Public: Calculate billed_on date for an out of date metered cycle
  #
  # N.B. this will only update in memory, use #advance_metered_cycle_reset_date!
  # in the event you want to save the user instance this is called on.
  #
  # Returns Date or nil
  def advanced_metered_cycle_reset_date
    return billed_on unless billed_on.nil? || billed_on < ::GitHub::Billing.today

    active_charged_through_date = plan_subscription&.zuora_subscription&.active_charged_through_date

    # will return nil if no active_charged_through_date, no zuora_account, and also
    # no budget it is the intent to set the billed_on to nil
    # in those cases, as it will cause the metered billing quota reset to happen on
    # the first of every month
    #
    # note the nil check above, that is so that we give a chance to update if
    # something got out of sync, but we are ok with a nil billed_on
    if active_charged_through_date.present?
      active_charged_through_date
    elsif T.must(customer).bill_cycle_day.to_i > 0
      build_date_in_future(T.must(customer).bill_cycle_day)
    # This will have a side effect of persisting a previously non-existent
    # budget record if a saving operation is called
    # on the the user record
    else
      budget_enabled_date = budgets.first&.created_at
      if budget_enabled_date
        build_date_in_future(budget_enabled_date.day)
      end
    end
  end

  # Public: Uses the in memory calculation done in #advanced_metered_cycle_reset_date
  # and sets the billed_on date accordingly
  sig { returns(T::Boolean) }
  def advance_metered_cycle_reset_date!
    update!(billed_on: advanced_metered_cycle_reset_date)
  end

  # Internal: Builds a date based on the combination of todays
  # date, and a passed day.
  #
  # base_day - the day to base the change on
  #
  # Examples:
  #
  #   Today is Jan 31st, 2020 and base_day is 30
  #   set_billed_on_to_future(30) => Sat, 29 Feb 2020
  #
  #   Today is Jan 25th, 2020 and base_day is 29
  #   set_billed_on_to_future(29) => Wed, 29 Jan 2020
  #
  # Returns Date
  def build_date_in_future(base_day)
    today = ::GitHub::Billing.today

    if base_day < today.day
      temp_date = (today + 1.month)
      update_date_with_day(temp_date, base_day)
    else
      update_date_with_day(today, base_day)
    end
  end

  # Internal: Handle date manipulations ensure we don't fall outside the end of the month
  #
  # Returns Date
  def update_date_with_day(date, day)
    if day > date.end_of_month.day
      date.end_of_month
    else
      date.change(day: day)
    end
  end

  # Public: Returns the timestamp where the current metered billing cycle starts (in the correct time zone)
  #
  # Returns ActiveSupport::TimeWithZone the starting timestamp
  def current_metered_billing_cycle_starts_at
    return business.current_metered_billing_cycle_starts_at if delegate_billing_to_business?

    return Time.now.utc.beginning_of_month if metered_via_azure? || customer&.billed_via_billing_platform?

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

  # Internal: Retrieves start time of next metered billing cycle
  #
  # Returns ActiveSupport::TimeWithZone
  def next_metered_billing_cycle_starts_at
    return business.next_metered_billing_cycle_starts_at if delegate_billing_to_business?

    return current_metered_billing_cycle_starts_at + 1.month if metered_via_azure? || customer&.billed_via_billing_platform?

    end_of_cycle = current_metered_billing_cycle_starts_at.next_month
    bcd = metered_cycle_day

    if end_of_cycle.day != bcd
      # This means the prior month had less days than the BCD
      # We use that information to advance the date to the the lowest between the BCD or the end of month day
      bcd = [bcd, end_of_cycle.end_of_month.day].min
      end_of_cycle = end_of_cycle.change(day: bcd)
    end

    end_of_cycle
  end

  # Public: Set disabled flag based on current plan limits, create a
  # Transaction to reflect the update, and update some stats.
  sig { void }
  def enable_or_disable!
    should_disable? ? disable! : enable!
  end

  sig { returns(T::Boolean) }
  def enabled?
    !disabled?
  end

  # Public: Unlocks billing for the User
  #
  # This allows the user to continue incurring new or additional costs on paid products/services.
  sig { void }
  def enable!
    return if enabled?
    self.update_attribute!(:disabled, false)
    customer&.unlock_billing
  end

  # Public: Unlocks a User for 2 days by resetting their billing attempts,
  # moving their billing date 2 days into the future, and enabling their
  # account.
  #
  # After 2 days, the account will enter the normal dunning cycle.
  sig { void }
  def unlock_billing!
    unless plan_subscription
      self.update \
        billing_attempts: 0,
        billed_on: [next_billing_date, relock_on].max
    end

    enable!
  end

  # Public: Will this user be relocked if unlocked with unlock_billing!
  sig { returns(T::Boolean) }
  def will_relock?
    !!(billed_on && billed_on < relock_on && over_billing_attempts_limit?)
  end

  # Public: Date this users will be relocked if unlocked with unlock_billing!
  sig { returns(Date) }
  def relock_on
    GitHub::Billing.today + 2.days
  end

  # Public: Locks billing for the User
  #
  # This prevents the user from incurring new or additional costs on paid products/services.
  sig { params(reason: T.nilable(Billing::Public::BillingDisabledReasons), send_email: T::Boolean).void }
  def disable!(reason: nil, send_email: false)
    return if disabled?
    self.update_attribute!(:disabled, true)
    customer&.lock_billing(reason: reason)
    Billing::CancelPastDueProductsJob.perform_later(billable_entity: T.cast(self, User), send_email: send_email, caller: __method__.to_s)
  end

  def subscription_next_bills_on
    subscription.service_next_bills_on
  end

  # Public: Unlock billing-locked private repos if the user has started paying
  sig { returns(T::Boolean) }
  def update_locked_repositories
    repositories.locked_repos.each do |repo|
      repo.network.billing_unlock
    end

    true
  end

  # Public: Queue a job to unlock billing-locked private repos if the user has
  # started paying for them.
  sig { void }
  def enqueue_update_locked_repositories
    forget_plan_changed_this_save
    UpdateLockedRepositoriesJob.perform_later(self.id)
  end

  sig { returns(T::Boolean) }
  def plan_changed_to_paid?
    !!(plan_changed_this_save? && paid_plan?)
  end

  # Public: Boolean if we have attempted billing on the account but failed.
  sig { returns(T::Boolean) }
  def dunning?
    billing_attempts.to_i > 0
  end

  # Public: Boolean if a paid user has 3 or greater billing attempts.
  sig { returns(T::Boolean) }
  def unable_to_bill?
    billing_attempts.to_i >= 3
  end

  # Public: Boolean if a paid user is in billing trouble:
  #   - 3 or greater billing attempts OR
  #   - Failure to pay invoice
  sig { returns(T::Boolean) }
  def billing_trouble?
    unable_to_bill? && payment_amount > 0
  end

  sig { void }
  def set_personal_billing_trouble_notice
    return unless user? && billing_trouble?

    Billing::PersonalBillingTroubleCheckJob.perform_later(self)
  end

  # Public: Destroy or restore pages if the plan was changed
  # This is invoked by an after_update lifecycle callback
  #
  # If new plan does support private pages, restore any that are soft deleted
  # If new plan does not support private pages, destroy or soft delete them
  sig { void }
  def delete_or_restore_pages_on_plan_change
    return if GitHub.enterprise?
    return if GitHub.multi_tenant_enterprise?
    previous_plan = GitHub::Plan.find(previous_changes.dig("plan", 0))
    return unless saved_change_to_plan? && plan.present? && previous_plan.present?
    if plan_supports_private_pages?
      RestoreSoftDeletedPagesJob.perform_later(self)
    elsif plan_supports?(:pages, visibility: :private) && !previous_plan.supports?(:pages, visibility: :private)
      RestoreSoftDeletedPagesJob.perform_later(self)
    else
      DestroyPrivatePageJob.perform_later(self)
    end
  end

  sig { returns(T::Boolean) }
  def plan_supports_private_pages?
    GitHub.multi_tenant_enterprise? || plan_supports?(:private_pages)
  end

  sig { returns(T::Array[Business]) }
  def renewal_eligible_businesses
    return @renewal_eligible_businesses if defined? @renewal_eligible_businesses

    date_range = 1.year.ago...Business::BillingContractUpdateDependency::CONTRACT_RENEWAL_WINDOW_SHORT.from_now
    renewal_businesses = (
      businesses(membership_type: :admin).self_renewal_eligible.with_term_end_date(date_range) +
      businesses(membership_type: :billing_manager).self_renewal_eligible.with_term_end_date(date_range)
    )

    # Remove any businesses that have already requested a renewal
    renewal_businesses.reject! { |business| business.renewal_already_requested? }

    # Bucket the businesses by non-expired/expired
    current, expired = renewal_businesses.partition { |business| business.billing_term_ends_on > GitHub::Billing.today }

    # Sort the buckets with billing_term_ends_on closest to today
    current.sort_by! { |business| business.billing_term_ends_on }
    expired.sort_by! { |business| business.billing_term_ends_on }.reverse!

    # Combine the buckets (expired ones are in the back)
    @renewal_eligible_businesses = current + expired
  end

  # This does some extra checks for eligiblity. It's separate from the above to avoid
  # doing the extra checks for every business, which can be expensive.
  sig { returns(T.nilable(Business)) }
  def renewal_eligible_business
    return @renewal_eligible_business if defined? @renewal_eligible_business
    @renewal_eligible_business = renewal_eligible_businesses.find do |business|
      next false if business.feature_enabled?(:ghe_sales_serve_overdue) && business.past_due_invoice?

      business.feature_enabled?(:ghe_sales_serve_renewals) && business.sales_managed_subscription_self_serve_eligible?
    end
  end

  # Public: Find Businesses owned by this user that are in manual dunning.
  sig { returns(T::Array[Business]) }
  def manual_dunning_businesses
    return @manual_dunning_businesses if defined? @manual_dunning_businesses

    @manual_dunning_businesses = \
      businesses(membership_type: :admin).select(&:manual_dunning?)
  end

  # Public: Does this User own a Business that is in manual dunning?
  sig { returns(T::Boolean) }
  def business_manual_dunning?
    manual_dunning_businesses.size > 0
  end

  # Public: Find Organizations owned by this user that are in manual dunning
  sig { returns(T::Array[Organization]) }
  def manual_dunning_orgs
    @manual_dunning_orgs ||= owned_organizations.paying.select(&:manual_dunning?)
  end

  # Public: Does this User own an Organization that is in manual dunning?
  sig { returns(T::Boolean) }
  def org_manual_dunning?
    manual_dunning_orgs.size > 0
  end

  # Public: Find Businesses owned by this user that are in billing trouble.
  sig { returns(T::Array[Business]) }
  def billing_troubled_businesses
    return @billing_troubled_businesses if defined? @billing_troubled_businesses

    @billing_troubled_businesses = \
      businesses(membership_type: :admin).select(&:billing_trouble?)
  end

  # Public: Does this User own a Business that is in billing trouble?
  sig { returns(T::Boolean) }
  def business_billing_trouble?
    billing_troubled_businesses.size > 0
  end

  # Public: Find Organizations owned by this user that are in billing trouble
  sig { returns(T::Array[Organization]) }
  def billing_troubled_orgs
    @troubled_orgs ||= owned_organizations.paying.select(&:billing_trouble?)
  end

  # Public: Does this User own an Organization that is in billing trouble?
  sig { returns(T::Boolean) }
  def org_billing_trouble?
    billing_troubled_orgs.size > 0
  end

  sig { void }
  def set_org_billing_trouble_notice
    return unless organization? && billing_trouble?

    Billing::OrgBillingTroubleCheckJob.perform_later(self)
  end

  # Public: Is this org in billing trouble?
  sig { params(org: Organization).returns(T::Boolean) }
  def org_in_billing_trouble?(org:)
    billing_troubled_orgs.include?(org)
  end

  # Public: Returns true when a user has exceeded the billing attempts limit
  sig { returns(T::Boolean) }
  def over_billing_attempts_limit?
    # NB: This is to prevent first time payers from getting 2 grace period
    if never_successfully_billed?
      billing_attempts.to_i > 0
    else
      billing_attempts.to_i >= BILLING_ATTEMPTS_LIMIT
    end
  end

  sig { returns(T::Boolean) }
  def under_billing_attempts_limit?
    billing_attempts.to_i < BILLING_ATTEMPTS_LIMIT
  end

  # Public: Returns true if the user has a payment count greater than `minimum_payment_count`
  #
  # start_date            - the date to start counting payments from
  # minimum_payment_count - the number of payments required to be considered successful
  #
  # Returns true if user has enough successful payments
  def successful_paid_payments?(start_date: nil, minimum_payment_count: 1)
    transactions = billing_transactions.successful.paid
    transactions = transactions.created_at_or_after(start_date) unless start_date.nil?
    transactions.count >= minimum_payment_count
  end

  # Returns truthy if this user has never successfully been billed.
  sig { returns(T::Boolean) }
  def never_successfully_billed?
    # Note: Zero charge transactions can cause `billed_on` to be set, so we also need to check their transactions
    billed_on.nil? || billing_transactions.successful.paid.count.zero?
  end

  # Public: Find the next day the user will need to pay after their payment has
  # been processed.
  #
  # service_started_on - Date service starts, from which we calculate the new billed on.
  # duration           - "month" or "year" of service. Set this to determine next billing date
  #                      when plan duration is changing. Defaults to user's current plan_duration.
  #
  # Returns the Date that this User should be billed on next.
  def new_billed_on(service_started_on, duration = nil)
    duration ||= plan_duration
    if duration.to_s == YEARLY_PLAN
      service_started_on + 1.year
    else
      service_started_on + 1.month
    end.to_date
  end

  # Public: Applies the dunning rules to the account and performs
  # the necessary actions, like sending notifications or disabling the account.
  sig { params(message: String).void }
  def dun_subscription(message)
    T.bind(self, User)
    Billing::DunSubscription.perform self, message: message
  end

  # Public: Cancels the account's billing
  # Closes all external subscriptions, zeroes out all invoices and balances, and cancels all pending changes.
  # Does not remove paid products from the account, but any previous payments made will be forfeited.
  # External subscriptions can be recreated unless the account is in a state which prevents subscription creation.
  sig { void }
  def cancel_billing
    plan_subscriptions.each { |plan_sub| plan_sub.cancel_external_subscription(force: true) }
    incomplete_pending_plan_changes.each(&:cancel)
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

  # Public: Resets the account's billing to a clean state.
  # Removes all payment methods, resets billing attempts, and enables the account.
  sig { void }
  def reset_billing
    GitHub.logger.info(
      "code.namespace" => self.class.name,
      "code.function" => "reset_billing",
      "gh.billing.billable_entity.billed_on" => billed_on,
      "gh.billing.billable_entity.billing_attempts" => billing_attempts,
      "gh.billing.billable_entity.disabled" => disabled?,
      "gh.billing.billable_entity.id" => self.id,
      "gh.billing.billable_entity.login" => self.display_login,
      "gh.billing.billable_entity.should_disable" => should_disable?,
      "gh.user.login" => login,
    )

    remove_all_payment_methods(User.ghost)
    reset_billing_attempts
    enable_or_disable!
    reset_billed_on
  end

  # Public: Whether or not the account is eligible to have their billing reset
  # Generally, they are eligible if they are in a billing locked state
  # with no current or expected outstanding balance.
  sig { params(has_balance: T::Boolean).returns(T::Boolean) }
  def can_reset_billing?(has_balance: balance.positive?)
    return false unless disabled?
    return false if any_external_subscriptions?
    return false if has_balance
    true
  end

  # Internal: can this user be billed?
  sig { returns(T::Boolean) }
  def billable?
    true
  end

  # Public: Find Organizations billing manageable by this user that are on per repository plan
  sig { returns(T::Array[Organization]) }
  def billing_manageable_per_repo_orgs
    @billing_manageable_per_repo_orgs ||= owned_or_billing_manager_organizations.select { |o| !o.plan.per_seat? }
  end

  sig { returns(T::Array[Organization]) }
  def billing_manageable_free_plan_orgs
    @billing_manageable_free_plan_orgs ||= owned_or_billing_manager_organizations.select { |o| o.plan.free? }
  end

  sig { returns(T::Array[Organization]) }
  def billing_manageable_team_plan_orgs
    @billing_manageable_team_plan_orgs ||= owned_or_billing_manager_organizations.select do |o|
      o.plan.business? && o.plan.paid?
    end
  end

  # Public: Find Organizations billing manageable by this user that are gifted (edu/nonprofit/opensource)
  sig { returns(T::Array[Organization]) }
  def billing_manageable_gifted_orgs
    @billing_manageable_gifted_orgs ||= owned_or_billing_manager_organizations.select do |org|
      org.plan.per_seat? &&
      org.coupon &&
      (%w[notsoprofitable opensource].include?(org.coupon.code) || org.coupon.group == "educaton-org")
    end
  end

  # Shows whether a given user has a plan or organization on the
  # `business_plus` / Business plan.
  #
  # Returns true for:
  #    - an organization on the Business plan
  #    - an owner, member or billing manager of an organization that is on the business_plus plan
  #    - an outside collaborator on a repo belonging to an organization that is on the business_plus plan
  #    - an owner or a billing manager of a Business
  sig { returns(T::Boolean) }
  def business_plus?
    plan.business_plus? || business_plus_member? || business_plus_collaborator? || business_admin_or_manager?
  end

  # Is this user a member, admin, or billing manager of a Business org?
  sig { returns(T::Boolean) }
  def business_plus_member?
    return false unless user?
    !!(organizations.detect(&:business_plus?) || billing_manager_organizations.detect(&:business_plus?))
  end

  # Is this user an outside collaborator in a Business organization?
  sig { returns(T::Boolean) }
  def business_plus_collaborator?
    return false unless user?
    !!(member_repositories.where(public: false).includes(:owner).map(&:owner)
      .compact.select(&:organization?).detect(&:business_plus?))
  end

  sig { returns(T::Boolean) }
  def business_admin_or_manager?
    return false unless user?
    businesses(membership_type: :admin).any? || businesses(membership_type: :billing_manager).any?
  end

  def product_uuid_subscription_items
    plan_subscription.try(:product_uuid_subscription_items) || Billing::SubscriptionItem.none
  end

  def active_product_uuid_subscription_items
    plan_subscription.try(:active_product_uuid_subscription_items) || Billing::SubscriptionItem.none
  end

  def past_product_uuid_subscription_items
    plan_subscription.try(:past_product_uuid_subscription_items) || Billing::SubscriptionItem.none
  end

  # Public: Returns this User's active SubscriptionItem for a Marketplace listing.
  sig { params(marketplace_listing_or_id: T.any(Marketplace::Listing, Integer)).returns(T.nilable(Billing::SubscriptionItem)) }
  def subscription_item_for_marketplace_listing(marketplace_listing_or_id)
    active_subscription_items.for_marketplace_listing(marketplace_listing_or_id).first
  end

  # Public: Returns a list of Organizations that have an active subscription to the Marketplace
  # listing with the given ID, and for which this User can administer those subscriptions.
  sig { params(listing_id: Integer).returns(T::Array[Organization]) }
  def billed_organizations_for_marketplace_listing(listing_id)
    return [] unless user?

    orgs = owned_organizations
    subscription_items_by_org_id = Billing::SubscriptionItem.joins(:plan_subscription)
      .merge(Billing::PlanSubscription.for_user(orgs)).active.for_marketplace_listing(listing_id)
      .includes(:plan_subscription)
      .each_with_object({}) do |item, hash|
        org_id = T.must(item.plan_subscription).user_id
        hash[org_id] = item
      end

    promises = subscription_items_by_org_id.values.map { |item| item.async_adminable_by?(self) }
    Promise.all(promises).sync

    orgs.select do |org|
      item = subscription_items_by_org_id[org.id]
      item && item.adminable_by?(self)
    end
  end

  sig { params(include_addons: T::Boolean).returns(Billing::PendingCycle) }
  def pending_cycle(include_addons: true)
    T.bind(self, User)
    Billing::PendingCycle.new(self, include_addons: include_addons)
  end

  # The changes that will occur on the users next billing date
  sig { returns(T.nilable(Billing::PendingPlanChange)) }
  def pending_cycle_change
    @pending_cycle_change ||= pending_plan_changes.incomplete.not_past.first
  end

  # Public: Returns the given users pending_cycle_change
  sig { returns(Promise[T.nilable(Billing::PendingPlanChange)]) }
  def async_pending_cycle_change
    return Promise.resolve(@pending_cycle_change) if @pending_cycle_change

    async_pending_plan_changes.then do |pending_changes|
      incomplete_changes = pending_changes.reject(&:is_complete).sort_by(&:id)

      change_item_promises = incomplete_changes.map(&:async_pending_subscription_item_changes)
      Promise.all(change_item_promises).then do |changes_item_changes|
        change_idx = changes_item_changes.find_index do |item_changes|
          item_changes.any?
        end

        @pending_cycle_change = change_idx.present? ? incomplete_changes[change_idx] : nil
      end
    end
  end

  def pending_free_trial_changes
    pending_plan_changes
       .joins(:pending_subscription_item_changes)
       .where(pending_subscription_item_changes: { free_trial: true })
  end

  sig { returns(T::Boolean) }
  def eligible_for_org_enterprise_cloud_trial?
    T.bind(self, User)

    Billing::EnterpriseCloudTrial.new(self).eligible?
  end

  sig { returns(T::Boolean) }
  def eligible_for_nonmetered_github_plan?
    true
  end

  # Should this user be disabled if it's not already?
  sig { params(check_plan_limit: T::Boolean).returns(T::Boolean) }
  def should_disable?(check_plan_limit: true)
    return false if never_disable?
    (check_plan_limit && over_plan_limit?) || (over_billing_attempts_limit? && dunning_period_expired?) || !!(disabled_reasons&.any?)
  end

  sig { returns(T::Boolean) }
  def never_disable?
    invoiced?
  end

  # Private: Returns if we're upgrading from an enterprise cloud trial or not.
  # If the trial is active we return true. We also return true if the trial is
  # expired and the user is on a free plan.
  sig { returns(T::Boolean) }
  def upgrading_from_trial?
    trial = Billing::PlanTrial.find_by(user: self, plan: GitHub::Plan::BUSINESS_PLUS)

    trial&.active? || (plan.name != GitHub::Plan::BUSINESS_PLUS && trial.present?)
  end

  # Public: Returns true if we're an organization with an associated business,
  # and not in enterprise mode
  sig { returns(T::Boolean) }
  def delegate_billing_to_business?
    async_delegate_billing_to_business?.sync
  end

  sig { returns(Promise[T::Boolean]) }
  def async_delegate_billing_to_business?
    not_present = T.let(false, T::Boolean)
    return Promise.resolve(not_present) unless organization?
    return Promise.resolve(not_present) if GitHub.single_business_environment?
    async_business.then do |business|
      business.present?
    end
  end

  # Public: Returns the business associated to that organization
  # When running on enterprise server, will return the global business
  # otherwise try look it from the association.
  def billing_business
    return GitHub.global_business if GitHub.single_business_environment?
    business
  end

  # Public: Returns the User, Organization or Business that is billed
  # for this User or Organization
  sig { returns(Billing::Types::Account) }
  def billable_owner
    delegate_billing_to_business? ? billing_business : self
  end

  # Public: True when User is Organization which delegates billing to
  # it's associated business
  sig { returns(T::Boolean) }
  def is_organization_billed_through_business?
    !!(organization? && billable_owner.instance_of?(Business))
  end

  # Public: checks if account is on free plan or undiscounted amount
  # is zero (which is the case on free trials, or free with free addons, etc.
  sig { returns(T::Boolean) }
  def uncharged_account?
    !!plan&.free? || undiscounted_payment_amount.zero?
  end

  sig { returns(T::Boolean) }
  def charged_account?
    !uncharged_account?
  end

  sig { returns(Integer) }
  def customer_bill_cycle_day
    return business.customer_bill_cycle_day if delegate_billing_to_business?

    customer&.bill_cycle_day.to_i
  end

  sig { returns(Integer) }
  def metered_cycle_day
    return 1 if metered_via_azure?

    [customer_bill_cycle_day.to_i, 1].max
  end

  def start_of_billing_day_with_timezone(on_date)
    billing_timezone = if delegate_billing_to_business? && business.billed_through_azure_subscription?
      ActiveSupport::TimeZone["UTC"]
    else
      GitHub::Billing.timezone
    end
    billing_timezone.parse(on_date.iso8601).beginning_of_day
  end

  def annual_discount_allowed?(plan: self.plan, billing_cycle: plan_duration, target_date: GitHub::Billing.today)
    return false if self.feature_enabled?(:remove_org_annual_discount)
    return false unless billing_cycle == YEARLY_PLAN
    return false unless organization?
    return false unless plan.business_plus? || plan.business?
    first_transaction = billing_transactions.paid.yearly.first
    return true unless first_transaction
    # we may apply the discount for seat additions + upgrades in the same year
    (target_date - T.must(first_transaction.created_at).in_time_zone(GitHub::Billing.timezone).to_date).to_i < 365
  end

  sig { returns(String) }
  def change_billing_duration_message
    "Switch to #{alternative_plan_duration}ly billing"
  end

  sig { returns(T.nilable(Billing::PendingPlanChange)) }
  def pending_seats_change
    pending_plan_changes.incomplete.with_seats.find { |pc| pc.changing_seats? }
  end

  sig { returns(T::Boolean) }
  def on_enterprise_cloud_trial?
    enterprise_cloud_trial.active?
  end

  sig { params(reason: T.any(Symbol, String), actor: T.nilable(User)).returns(T.nilable(GitHub::Billing::Result)) }
  def enable_auto_pay!(reason, actor: nil)
    T.bind(self, User)

    Billing::AutoPay.enable! \
      account: self,
      actor: actor,
      reason: reason
  end

  sig { params(reason: T.any(Symbol, String), actor: T.nilable(User)).returns(T.nilable(GitHub::Billing::Result)) }
  def disable_auto_pay!(reason, actor: nil)
    T.bind(self, User)

    Billing::AutoPay.disable! \
      account: self,
      actor: actor,
      reason: reason
  end

  # Public: The payment processor email address to use for users and organizations.
  sig { returns(T.nilable(String)) }
  def payment_processor_email
    business ? business.billing_email : email
  end

  # Public: The payment processor account name to use for users and organizations.
  sig { returns(String) }
  def payment_processor_account_name
    business ? business.name : login
  end

  sig { params(listing_slug: String).returns(T.nilable(Marketplace::Listing)) }
  def active_listing_plan(listing_slug)
    async_active_listing_plan(listing_slug).sync
  end

  sig { params(listing_slug: String).returns(Promise[T.nilable(Marketplace::Listing)]) }
  def async_active_listing_plan(listing_slug)
    @active_listing_plans_by_slug ||= Hash.new do |hash, slug|
      hash[slug] = async_plan_subscription.then do |plan_subscription|
        next unless plan_subscription

        plan_subscription.async_active_subscription_items.then do |items|
          plan_promises = items.map(&:async_subscribable)
          Promise.all(plan_promises).then do |listing_plans|
            listing_promises = listing_plans.map(&:async_listing)
            Promise.all(listing_promises).then do
              listing_plans.compact.detect do |listing_plan|
                listing_plan.listing.slug == slug
              end
            end
          end
        end
      end
    end

    @active_listing_plans_by_slug[listing_slug]
  end

  # Public: Enqueues suspension email to be sent using relevant mailer
  #
  # cancelled_subscription_item_names - Array of cancelled subscription items listing_names for user
  # for user due to suspension. Is used in mailer to notify user of changes to their account.
  #
  # Returns ApplicationDeliveryJob
  def send_suspension_email(cancelled_subscription_item_names, tos_reason: nil, dsa_source: nil)
    if is_a?(Organization)
      OrganizationMailer.suspension(self, cancelled_subscription_item_names, tos_reason, dsa_source).deliver_later
    else
      AccountMailer.suspension(self, cancelled_subscription_item_names, tos_reason, dsa_source).deliver_later
    end
  end

  def send_billing_lock_email(cancelled_subscription_item_names)
    if is_a?(Organization)
      OrganizationMailer.billing_lock(self, cancelled_subscription_item_names).deliver_later
    else
      AccountMailer.billing_lock(self, cancelled_subscription_item_names).deliver_later
    end
  end

  sig { returns(T::Boolean) }
  def requires_invoice_by_email?
    !!customer&.requires_invoice_by_email?
  end

  sig { returns(T::Boolean) }
  def collect_payment_immediately_for_plan_or_seat_changes?
    return false if customer&.requires_manual_transactions? || invoiced?
    return false unless plan_subscription.present? && zuora_account? &&
      payment_amount(plan: plan, duration: plan_duration) > 0
    !self.feature_enabled?(:skip_immediate_payment_collection_for_plan_or_seat_changes, memoize: false)
  end

  sig { returns(Billing::EnterpriseCloudTrial) }
  def enterprise_cloud_trial
    @enterprise_cloud_trial ||= ::Billing::EnterpriseCloudTrial.new self
  end

  # Public: Checks if user meets requirements for auth
  #
  # check_payment_method - skip payment method check
  # useful in situations like the credit card form that informs users of auth & capture
  # while they are filling in their new credit card payment method
  sig { params(check_payment_method: T::Boolean, check_overage: T::Boolean).returns(T::Boolean) }
  def can_be_authorized?(check_payment_method: true, check_overage: true)
    return false if metered_via_azure?

    if check_payment_method
      return false unless payment_method_supports_authorization?
    end

    # Only target non tier 1 users
    trust_tier = TrustTiers::Tier.for_billable_owner(self).tier
    return false if trust_tier == 1

    # Skip users in dunning that have a paid plan and a recent history of successful payments.
    # This prevents prematurely locking the account and zeroing out of their invoices which is a bad experience
    # for the users and also causes unnecessary losses for us.
    #
    # TODO: Remove this once we have a way to collect outstanding invoices for locked accounts
    return false if self.dunning? && self.plan.cost > 0 && successful_paid_payments?(
      start_date: GitHub::Billing.today - 4.months, minimum_payment_count: 3)

    # metered_billing_overage_allowed? always returns nil for Copilot, but we still want to
    # auth and capture
    if check_overage
      return false unless self.metered_billing_overage_allowed?
    end

    true
  end

  sig { returns(T::Array[Billing::Zuora::Invoice]) }
  def invoices
    return [] unless zuora_account_id = customer&.zuora_account_id

    @_invoices ||= Billing::Zuora::Invoice.invoices_for_account(zuora_account_id)
      .select(&:posted?)
      .reject(&:suppress_from_customer_view?)
      .sort_by(&:invoice_date)
      .reverse
  end

  sig { returns(T::Boolean) }
  def display_sales_tax_on_checkout?
    !!customer&.in_taxable_country?
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
  def validate_purchases_allowed(actor: nil, check_disabled: true, check_dunning: false, check_trade_restrictions: true)
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

  # Onboards a user to the billing platform if feature flag is enabled
  sig { void }
  def onboard_to_billing
    return unless feature_enabled?(:onboard_new_individual_free_plan_to_billing_platform)

    user = self.is_a?(User) ? T.cast(self, User) : nil
    raise TypeError, "Expected self to be User" unless user

    return if customer&.billed_via_billing_platform?

    response = GitHub::Billing.create_customer(user, {}, actor: user) unless customer

    if customer
      T.must(customer).onboard_to_all_billing_platform_products
      GitHub.dogstats.increment("billing_platform.onboard_new_free_user.count", tags: ["free_user_customer_create"])
    else
      GitHub.dogstats.increment("billing_platform.onboard_new_free_user_failed.count", tags: ["free_user_failed_customer_create", "error_code:#{response&.error_code}"])
    end
  end

  private

  sig { returns(T::Boolean) }
  def enterprise_owned_self_serve_org?
    organization? && plan.account&.business? && plan.account.self_serve_payment?
  end

  # Remove advisory workspaces from the list of repos
  def remove_advisory_workspaces(repo_scope)
    workspace_repo_ids = RepositoryAdvisory
      .where(owner_id: id)
      .where.not(workspace_repository_id: nil)
      .limit(MYSQL_MAX_ROWS_LIMIT)
      .pluck(:workspace_repository_id)
    repo_scope.where.not(id: workspace_repo_ids)
  end

  # Checks whether the user's bill cycle day has been set or not
  #
  # If true, the bill cycle has not been set and will be set by a future charge
  # If false, the bill cycle day has been set and is being synced with Zuora
  sig { returns(T::Boolean) }
  def autoset_bill_cycle_day?
    customer_bill_cycle_day.nil? || customer_bill_cycle_day.zero?
  end

  # Internal: Schedule a job to synchronize this user's plan information
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
    UpdateExternalCustomerJob.perform_later(T.must(self.customer)) if @needs_external_customer_update
  end

  # Internal: Enqueues a SynchronizePlanSubscription job to synchronize the
  # customer's plan subscription with Braintree or Zuora.
  #
  # This happens after commit to ensure that when the job is picked up by the
  # worker, all of the changes processed in the enqueuing thread are saved.
  sig { params(one_time_only: T::Boolean).void }
  def run_scheduled_subscription_synchronization(one_time_only: false)
    return unless @needs_subscription_synchronization
    synchronize_general_purpose_subscription_later
    T.must(sponsors_plan_subscription).synchronize_later if sponsors_plan_subscription

    # Set the flag to false to prevent subsequent synchronization jobs from firing off
    # on future updates
    if one_time_only
      @needs_subscription_synchronization = false
    end
  end

  # Internal: Mark the record as requiring a Braintree customer update, which
  # is handled in the UpdateExternalCustomer job
  sig { void }
  def schedule_external_customer_update
    @needs_external_customer_update = true
  end

  # Internal: Mark the record as requiring a subscription synchronization,
  # which is handled by the SynchronizePlanSubscription job
  sig { void }
  def schedule_subscription_synchronization
    @needs_subscription_synchronization = true
  end

  # Internal: Are there plan changes that need to be synchronized
  sig { returns(T::Boolean) }
  def remote_subscription_needs_update?
    T.bind(self, User)

    (
      saved_change_to_plan? ||
      saved_change_to_seats? ||
      saved_change_to_plan_duration?
    ) &&
    !Organization.transforming?(self)
  end

  # Internal: Determine if this user should be transitioned to an external subscription.
  # A subscription is required to bill for any paid products and metered usage.
  sig { returns(T::Boolean) }
  def should_transition_to_external_subscription?
    return false if enterprise_cloud_trial.active?
    !!(!external_subscription? && has_valid_payment_method?(feature_type: :noncommercial))
  end

  # Internal: Uncache user plan signup transaction in case this value has changed
  #
  # _transaction: Because this is called on `after_add` AR passes the added
  # transaction. We, however, don't need it.
  sig { params(_transaction: T.untyped).void }
  def clear_signup_transaction(_transaction)
    @plan_signup_transaction = nil
  end

  # Internal: Has the 2-week dunning period for this user elapsed?
  sig { returns(T::Boolean) }
  def dunning_period_expired?
    return true if never_successfully_billed?
    GitHub::Billing.today >= billed_on + DUNNING_DAYS
  end

  sig { returns(T::Boolean) }
  def first_time_charge?
    billing_transactions.first_time_charge.blank?
  end

  sig { returns(::Transaction) }
  def signup_transaction
    transactions.create(user: self, action: "signed-up")
  end


  sig { returns(::Transaction) }
  def delete_transaction
    transactions.create(action: "deleted")
  end

  sig { void }
  def seat_count_no_greater_than_world_population
    if changing_seats? && seats > 10_000_000_000
      errors.add :seats, "must be no more than the total number of people on Planet Earth"
    end
  end

  sig { void }
  def seat_count_greater_than_member_count
    if !delegate_billing_to_business? && changing_seats? && seats < filled_seats
      errors.add :seats, "must be at least the number of currently filled seats"
    end
  end

  sig { void }
  def seat_count_greater_than_base_units
    if changing_seats? && !delegate_billing_to_business? && seats < plan.base_units
      errors.add :seats, "must be at least #{plan.base_units}"
    end
  end

  sig { returns(T::Boolean) }
  def changing_seats?
    organization? && will_save_change_to_seats? && plan && plan.per_seat?
  end

  # Private: Given a transaction, determine the date the user should be billed
  # next. Depending on the state of the user, we might need to start a new
  # billing cycle.
  sig { params(transaction: Billing::BillingTransaction).void }
  def move_billed_on(transaction)
    self.billed_on = if start_new_billing_period?
      new_billed_on(transaction.date)
    else
      new_billed_on(billed_on)
    end
  end

  # Private: Boolean if we should start a brand new billing period for this
  # user. Generally users keep a standard billing cycle (we charge you every
  # month on the 4th, for example). We only start a new cycle if:
  #   - Your card fails for more than 14 days OR
  #   - You don't have a cycle for some reason (billed_on.blank?) OR
  #   - Your account gets disabled (staff locks, outside repo limits) OR
  #   - You've somehow ended up with an extremely old billing date
  sig { returns(T::Boolean) }
  def start_new_billing_period?
    over_billing_attempts_limit? || billed_on.blank? || disabled? ||
      billed_on < (GitHub::Billing.today - DUNNING_DAYS)
  end

  # Private: Handles coupon expiry and fully covered paid plans.
  #
  # Returns GitHub::Billing::Result
  def recurring_charge_with_coupon(amount_in_cents, charge_type)
    if !past_due?
      enable_or_disable!
      GitHub::Billing::Result.success
    elsif amount_in_cents.zero?
      process_zero_charge_transaction(charge_type)
    else
      Failbot.push \
        "gh.user.id" => self.id
    end
  end

  sig { returns(T::Array[Integer]) }
  def adminable_org_ids
    Ability.where(
      actor_id: id,
      actor_type: "User",
      subject_type: "Organization",
      action: Ability.actions[:admin],
    ).pluck(:subject_id)
  end
end
