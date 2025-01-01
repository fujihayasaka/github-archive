# typed: true
# frozen_string_literal: true

class GitHubModels::Businesses::BillingUsageComponent < ApplicationComponent
  sig { params(business: Business).void }
  def initialize(business:)
    @business = business
  end

  sig { returns(T::Boolean) }
  def render?
    return false unless GitHub.models_enabled?
    return false unless business.billed_via_billing_platform?
    return false if business.metered_via_azure?
    return false if business.plan.legacy?
    return false if business.trial?

    user_or_global_feature_enabled?(:github_models_billing_ui)
  end

  sig { returns(T::Boolean) }
  def billing_enabled
    business.models_billing_enabled?
  end

  private

  attr_reader :business
end
