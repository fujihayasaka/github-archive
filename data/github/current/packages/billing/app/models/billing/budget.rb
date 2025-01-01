# typed: strict
# frozen_string_literal: true

class Billing::Budget < ApplicationRecord::Domain::Billing

  include Instrumentation::Model
  include GitHub::Memoizer

  GHE_BUDGETS_VALIDATION_SCOPE = :ghe_budgets
  NO_BUDGET = :no_budget

  self.table_name = "billing_budgets"

  belongs_to :owner, polymorphic: true

  validates :budget_name, presence: true, length: { maximum: 100 }, on: GHE_BUDGETS_VALIDATION_SCOPE
  validates :product, uniqueness: { scope: [:owner_type, :owner_id], case_sensitive: false, message: "has already been taken for this scope" }
  validates :owner, presence: true
  validates :enforce_spending_limit, inclusion: { in: [true, false] }
  validates :spending_limit_in_subunits, numericality: {
    greater_than_or_equal_to: 0,
    only_integer: true,
    message: "Spending limit must be a positive number",
  }

  validate :valid_payment_method_for_overages?, unless: -> { T.cast(self, Billing::Budget).owner.invoiced? }
  validate :organization_budget_cannot_be_more_than_enterprise_budget, on: GHE_BUDGETS_VALIDATION_SCOPE
  validate :enterprise_budget_cannot_be_less_than_organization_budget, on: GHE_BUDGETS_VALIDATION_SCOPE

  validate :tiering_limits_budget

  after_create_commit :instrument_create
  after_update_commit :instrument_update
  after_destroy_commit :instrument_destroy

  scope :overage_allowed, -> { where.not("enforce_spending_limit = 1 AND spending_limit_in_subunits = 0") }

  enum :product, {
    shared: "shared",
    codespaces: "codespaces"
  }

  sig { returns(T::Hash[T.any(String, Symbol), String]) }
  def self.product_labels
    {
      shared: "GitHub Actions & Packages",
      codespaces: "GitHub Codespaces"
    }.with_indifferent_access
  end

  sig { returns(Symbol) }
  def self.ghe_budgets_validation_scope
    GHE_BUDGETS_VALIDATION_SCOPE
  end

  sig { params(group: T.any(String, Symbol)).returns(T::Boolean) }
  def self.valid_budget_group?(group)
    @valid_budget_groups ||= T.let(
      ::GitHub::Billing::MeteredProduct.all.each_with_object(Set.new) do |product, memo|
        memo << product.budget_group
        memo << product.prepaid_budget_group
      end,
      T.nilable(T::Set[String]))

    @valid_budget_groups.include?(group.to_s)
  end

  sig { params(product: T.nilable(T.any(String, Symbol)), prepaid: T::Boolean).returns(T.nilable(String)) }
  def self.budget_group_for(product:, prepaid:)
    metered_product = ::GitHub::Billing::MeteredProduct.find(product.to_s)

    if prepaid
      metered_product.prepaid_budget_group
    else
      metered_product.budget_group
    end
  end

  sig { params(owner: T.nilable(Billing::Types::Account)).returns(T::Boolean) }
  def self.configurable?(owner)
    return false if owner.nil?
    return false if owner.billed_through_azure_subscription? && !owner.linked_azure_subscription?
    return false if !owner.plan_metered_billing_eligible?

    true
  end

  sig { params(enforce_spending_limit: T::Boolean, limit: T.nilable(T.any(Billing::Types::Numeric, String))).void }
  def configure(enforce_spending_limit:, limit: nil)
    overage_allowed_previously = overage_allowed?

    configured = if enforce_spending_limit
      set_spending_limit(limit)
    else
      set_unlimited_spending
    end
    return unless configured

    if owner.is_a?(Business)
      if !overage_allowed_previously && overage_allowed?
        ::Billing::UpdateSkippedMeteredLineItemsJob.perform_later(billable_owner: owner)
      end
    else
      # Does not attempt synchronization if user already has subscription
      ::Billing::PlanSubscription::Transition.activate(owner, purpose: :general, force: true)
    end
  end

  # Returns whether the owner has set configured enforcement
  # on spending limits.
  sig { returns(T::Boolean) }
  def enforcement_configured?
    !!(persisted? && enforce_spending_limit?)
  end

  sig { returns(T::Boolean) }
  def overage_allowed?
    !(enforce_spending_limit? && spending_limit_in_subunits.zero?)
  end

  # Public: Does this budget not enforce a budget, setting an unlimited spending limit?
  sig { returns(T::Boolean) }
  def unlimited_spending_limit?
    !enforce_spending_limit?
  end

  sig { returns(T::Boolean) }
  def set_unlimited_spending
    update(enforce_spending_limit: false)
  end

  sig { params(limit: T.nilable(T.any(Billing::Types::Numeric, String))).returns(T::Boolean) }
  def set_spending_limit(limit)
    limit ||= limit.to_i

    update(
      enforce_spending_limit: true,
      spending_limit_in_subunits: Integer(limit.to_d * 100)
    )
  end

  sig { returns(String) }
  def slug
    [id, spending_limit_in_subunits].join("-")
  end

  # Public: Owners set usage limit
  #
  sig { returns(Billing::Types::Numeric) }
  def usage_limit
    enforce_spending_limit? ? spending_limit_in_subunits : BigDecimal("Infinity")
  end

  sig { returns(T::Boolean) }
  def enterprise_budget_for_org?
    owner.is_organization_billed_through_business?
  end

  sig { returns(T::Boolean) }
  def has_products_with_included_usage?
    return true if codespaces? && Codespaces::Policy.entitlements_feature_enabled?(owner)

    shared?
  end

  sig { returns(T::Boolean) }
  def included_usage_notification
    return false unless has_products_with_included_usage?
    self[:included_usage_notification]
  end

  sig do
    params(
      paid_usage_notification: T.any(T.nilable(T::Boolean), String),
      included_usage_notification: T.any(T.nilable(T::Boolean), String)
    ).returns(T::Boolean)
  end
  def configure_notifications(paid_usage_notification:, included_usage_notification: nil)
    notification_args = {
      paid_usage_notification: paid_usage_notification
    }
    if has_products_with_included_usage?
      notification_args[:included_usage_notification] = included_usage_notification
    end
    update(notification_args)
  end

  private

  ## This is a validation that checks whether the spending limit is available for the
  ## organization's tier.
  #
  # If the owner is in the most trusted tier, we let them set spending limits or allow it to be unlimited.
  #
  # If the owner is not in the most trusted tier, we limit them to the maximum allowed for their tier.
  sig { returns(T::Boolean) }
  def tiering_limits_budget
    max_budget = Billing::BudgetLimit::FindBudget.for_account(owner, shared?)

    # for trusted accounts, we don't do any more checks.
    return true if max_budget.infinite?

    max_budget_description = Billing::Money.new(max_budget).format
    message = "Spending limit amount cannot exceed #{max_budget_description}. Please contact support to learn more."

    # if we aren't enforcing spending limits, that means they are trying to set it to an unlimited amount.
    errors.add(:tiered_spending, message) and return false if unlimited_spending_limit?

    # if we are enforcing spending limits, we need to check whether spending limit is valid
    errors.add(:tiered_spending, message) if spending_limit_in_subunits > max_budget
    false
  end

  sig { returns(T::Boolean) }
  def valid_payment_method_for_overages?
    return true unless overage_allowed?
    return true if owner.has_valid_payment_method?(feature_type: :noncommercial)

    errors.add(:payment_method, "must be present and valid")
    false
  end

  sig { returns(T.nilable(Billing::Budget)) }
  def org_business_budget
    return unless owner.organization?
    owner.business&.budgets&.find_by(product: product)
  end

  sig { returns(T::Boolean) }
  def org_business_budget_has_greater_spending_limit?
    return true unless owner.organization?
    org_business_budget = self.org_business_budget
    return true unless org_business_budget
    return true unless org_business_budget.enforce_spending_limit

    !!(enforce_spending_limit && spending_limit_in_subunits <= org_business_budget.spending_limit_in_subunits)
  end

  sig { void }
  def organization_budget_cannot_be_more_than_enterprise_budget
    message = "Organization monthly budget cannot exceed the Enterprise account budget of #{Billing::Money.new(org_business_budget&.spending_limit_in_subunits).format}"
    errors.add(:base, message) unless org_business_budget_has_greater_spending_limit?
  end

  sig { returns(T::Array[Billing::Budget]) }
  memoize def business_orgs_budgets
    return [] unless owner.is_a?(Business)

    # Making sure only only 1 query is performed
    Billing::Budget.where(product: product, owner_type: "User", owner_id: owner.organizations.pluck(:id)).to_a
  end

  sig { returns(T.nilable(Integer)) }
  def max_business_org_pending_limit
    business_orgs_budgets.pluck(:spending_limit_in_subunits).max
  end

  sig { returns(T::Boolean) }
  def has_unlimited_business_org_budget?
    business_orgs_budgets.any? { |budget| budget.enforce_spending_limit == false }
  end

  sig { returns(T::Boolean) }
  def business_budget_has_greater_spending_limit?
    return true unless enforce_spending_limit
    return true unless owner.is_a?(Business)
    return true unless owner.organizations.any?
    return true unless business_orgs_budgets.any? do |budget|
      !budget.enforce_spending_limit || budget.spending_limit_in_subunits > spending_limit_in_subunits
    end

    false
  end

  sig { void }
  def enterprise_budget_cannot_be_less_than_organization_budget
    message = if has_unlimited_business_org_budget?
      "Enterprise monthly budget cannot be less than an unlimited Organization budget"
    else
      "Enterprise monthly budget cannot be less than the Organization budget of #{Billing::Money.new(max_business_org_pending_limit).format}"
    end
    errors.add(:base, message) unless business_budget_has_greater_spending_limit?
  end

  sig { returns(T.nilable(T::Boolean)) }
  def set_billed_on
    owner.update(billed_on: ::GitHub::Billing.today + 1.month) if owner.billed_on.nil?
  end

  sig { returns(Symbol) }
  def event_prefix
    # TODO: switch this to `billing_budget` once we've moved over completely to Meuse
    :metered_billing_configuration
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def event_payload
    payload = {
      enforce_spending_limit: enforce_spending_limit,
      spending_limit_in_subunits: spending_limit_in_subunits,
      spending_limit_currency_code: spending_limit_currency_code,
      spending_limit_description: spending_limit_description,
      spending_limit_product_name: Billing::Budget.product_labels[product]
    }

    if owner.is_a?(Business)
      payload[:business] = owner
    elsif owner.organization?
      payload[:org] = owner
    else
      payload[:user] = owner
    end

    payload
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def hydro_payload
    payload = {
      budget_id: id,
      billable_owner_detail: {
        bill_cycle_day: owner.billable_owner.metered_cycle_day,
        free_usage_user: owner.billable_owner.active_plan_subscription&.has_free_usage_product? || false,
        customer_id: owner.billable_owner.customer&.id,
        entitlement_plan_name: owner.billable_owner.plan.entitlement_plan_name,
      },
      current_budget: {
        enforce_spending_limit: enforce_spending_limit,
        spending_limit_in_subunits: spending_limit_in_subunits,
        spending_limit_currency_code: spending_limit_currency_code,
      },
      product_names: [product]
    }

    owner_key = owner.billable_owner.is_a?(Business) ? :business_owner : :user_owner
    payload[owner_key] = owner.billable_owner

    target_key = owner.is_a?(Business) ? :business_target : :user_target
    payload[target_key] = owner

    payload
  end

  sig { void }
  def instrument_create
    instrument :create

    GlobalInstrumenter.instrument(
      "billing.budget_updated",
      hydro_payload.merge(action: :CREATE),
    )
  end

  sig { void }
  def instrument_update
    was_enforce_spending_limit, _ = previous_changes[:enforce_spending_limit]
    was_spending_limit_in_subunits, _ = previous_changes[:spending_limit_in_subunits]

    instrument :update, {
      was_spending_limit_description: spending_limit_description(
        enforce_limit: was_enforce_spending_limit,
        subunits: was_spending_limit_in_subunits,
      ),
      was_enforce_spending_limit: was_enforce_spending_limit,
      was_spending_limit_in_subunits: was_spending_limit_in_subunits,
    }

    GlobalInstrumenter.instrument(
      "billing.budget_updated",
      hydro_payload.merge(
        action: :UPDATE,
        previous_budget: {
          enforce_spending_limit: was_enforce_spending_limit,
          spending_limit_in_subunits: was_spending_limit_in_subunits,
          spending_limit_currency_code: spending_limit_currency_code,
        },
      ),
    )
  end

  sig { void }
  def instrument_destroy
    instrument :destroy
  end

  sig { params(enforce_limit: T.nilable(T::Boolean), subunits: T.nilable(Integer)).returns(String) }
  def spending_limit_description(enforce_limit: nil, subunits: nil)
    enforce_limit = enforce_spending_limit if enforce_limit.nil?
    subunits ||= spending_limit_in_subunits

    if enforce_limit
      Billing::Money.new(subunits).format
    else
      "Unlimited"
    end
  end
end
