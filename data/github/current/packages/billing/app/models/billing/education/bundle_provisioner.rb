# typed: strict
# frozen_string_literal: true

class Billing::Education::BundleProvisioner

  sig { params(business: Business, education_bundle: String, actor: T.nilable(User)).returns(GitHub::Billing::Result) }
  def self.perform!(business:, education_bundle:, actor: nil)
    new(business: business, education_bundle: education_bundle, actor: actor).perform!
  end


  sig { params(business: Business, education_bundle: String, actor: T.nilable(User)).void }
  def initialize(business:, education_bundle:, actor: nil)
    @business = business
    @education_bundle = education_bundle
    @actor = actor
    @previous_education_bundle = T.let(nil, T.nilable(String))
  end

  sig { returns(GitHub::Billing::Result) }
  def perform!
    return success_response unless changing_bundle?
    return invalid_customer_response unless valid_education_customer?

    create_sales_serve_plan_subscription unless sales_serve_plan_subscription

    @previous_education_bundle = sales_serve_plan_subscription.education_bundle

    if sales_serve_plan_subscription.update(education_bundle: education_bundle)
      instrument_education_bundle_changed
    end

    success_response
  end

  private

  sig { returns(::Business) }
  attr_reader :business

  sig { returns(String) }
  attr_reader :education_bundle

  sig { returns(T.nilable(User)) }
  attr_reader :actor

  delegate :billed_through_azure_subscription?, :customer, to: :business
  delegate :sales_serve_plan_subscription, to: :customer, allow_nil: true

  sig { returns(T::Boolean) }
  def changing_bundle?
    sales_serve_plan_subscription&.education_bundle != education_bundle
  end

  sig { returns(::Billing::SalesServePlanSubscription) }
  def create_sales_serve_plan_subscription
    ::Billing::SalesServePlanSubscription.create!(
      customer: business.customer,
      billing_start_date: business.plan_effective_at || GitHub::Billing.now,
    )
  end

  sig { void }
  def instrument_education_bundle_changed
    GitHub.instrument "billing.update_education_bundle", {
      education_bundle: education_bundle,
      previous_education_bundle: @previous_education_bundle,
      business: customer.business,
      actor: actor,
    }
  end

  sig { returns(T::Boolean) }
  def valid_education_customer?
    !!(sales_serve_plan_subscription || billed_through_azure_subscription?)
  end

  sig { returns(GitHub::Billing::Result) }
  def success_response
    GitHub::Billing::Result.success
  end

  sig { returns(GitHub::Billing::Result) }
  def invalid_customer_response
    GitHub::Billing::Result.failure "Customer not configured correctly for education bundle"
  end
end
