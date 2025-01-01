# typed: strict
# frozen_string_literal: true

class Billing::PlanSubscription::Transition
  # Public: Transitions an account to an external subscription
  #
  # force     - Whether or not to disregard all guards and force activaton (default: false)
  # skip_sync - Whether or not to skip synchronization with Zuora (default: false)
  # purpose   - The purpose of the Billing::PlanSubscription that you want to sync; choose between :general and
  #             :sponsors
  #
  # Returns a PlanSubscription if successful, nil otherwise.
  sig do
    params(
      billable_entity: ::Billing::Types::Account,
      force: T::Boolean,
      skip_sync: T::Boolean,
      purpose: T.nilable(T.any(Symbol, String))
    ).returns(T.nilable(Billing::PlanSubscription))
  end
  def self.activate(billable_entity, force: false, skip_sync: false, purpose: :general)
    new(billable_entity, purpose: purpose).activate(force: force, skip_sync: skip_sync)
  end

  sig { params(billable_entity: ::Billing::Types::Account, purpose: T.nilable(T.any(Symbol, String))).void }
  def initialize(billable_entity, purpose: :general)
    @billable_entity = billable_entity
    @purpose = T.let((purpose || :general).to_sym, Symbol)
  end

  sig { params(force: T::Boolean, skip_sync: T::Boolean).returns(T.nilable(Billing::PlanSubscription)) }
  def activate(force: false, skip_sync: false)
    log_data = {
      "code.namespace" => self.class.name,
      "code.function" => "activate",
      "gh.billing.billable_entity.billed_on" => billable_entity.billed_on,
      "gh.billing.billable_entity.billing_type" => billable_entity.billing_type,
      "gh.billing.billable_entity.plan_name" => billable_entity.plan.name,
      "gh.billing.billable_entity.plan_duration" => billable_entity.plan_duration,
      "gh.billing.plan_subscription.zuora_subscription_number" => existing_plan_subscription&.zuora_subscription_number
    }

    billable_entity = self.billable_entity
    if billable_entity.is_a?(Business)
      GitHub.logger.info({ "gh.business.slug" => billable_entity.slug }.merge(log_data))
    else
      GitHub.logger.info({ "gh.user.login" => billable_entity.login }.merge(log_data))
    end

    # These are also checked during synchronization, so we shouldn't bother to
    # enqueue a synchronization job that will noop
    return if billable_entity.invoiced?
    return if billable_entity.payment_method.blank?

    # We normally want to apply these guards, but in some cases we may wish to
    # transition a billable entity anyway
    unless force
      return existing_plan_subscription if external_subscription_for_purpose?
    end

    existing_plan_subscription = self.existing_plan_subscription
    if existing_plan_subscription.present?
      GitHub.dogstats.increment("zuora.sync.transition.sync")
      existing_plan_subscription.synchronize_later unless skip_sync
      existing_plan_subscription
    else
      GitHub.dogstats.increment("zuora.sync.transition.create")
      create_plan_subscription(skip_sync: skip_sync)
    end
  end

  private

  sig { returns(::Billing::Types::Account) }
  attr_reader :billable_entity

  sig { returns(Symbol) }
  attr_reader :purpose

  sig { returns(T::Boolean) }
  def general_purpose?
    purpose == :general
  end

  sig { returns(T::Boolean) }
  def sponsors_purpose?
    purpose == :sponsors
  end

  sig { returns(T.nilable(Billing::PlanSubscription)) }
  def existing_plan_subscription
    # Load the relation off the billable entity since it might already be preloaded, such as in
    # GitHub::Billing::Legacy::Run, and an n+1 query can be avoided:
    if general_purpose?
      billable_entity.plan_subscription
    elsif sponsors_purpose?
      billable_entity.sponsors_plan_subscription
    end
  end

  sig { returns(T::Boolean) }
  def external_subscription_for_purpose?
    return true if general_purpose? && billable_entity.external_subscription?
    return true if sponsors_purpose? && billable_entity.external_sponsors_subscription?
    false
  end

  # Internal: Creates a new PlanSubscription for the billable entity
  sig { params(skip_sync: T::Boolean).returns(Billing::PlanSubscription) }
  def create_plan_subscription(skip_sync: false)
    billable_entity = self.billable_entity
    plan_subscription =
      if billable_entity.is_a?(Business)
        T.must(billable_entity.customer).build_plan_subscription(purpose: purpose)
      else
        billable_entity.build_plan_subscription(customer: billable_entity.customer, purpose: purpose)
      end

    plan_subscription.skip_synchronize_later = skip_sync
    plan_subscription.save!
    plan_subscription
  end
end
