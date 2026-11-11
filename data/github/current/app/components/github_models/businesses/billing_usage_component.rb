# typed: true
# frozen_string_literal: true

class GitHubModels::Businesses::BillingUsageComponent < ApplicationComponent
  sig { params(business: Business, in_stafftools: T::Boolean).void }
  def initialize(business:, in_stafftools: false)
    @business = business
    @in_stafftools = in_stafftools
  end

  sig { returns(T::Boolean) }
  def render?
    return false unless GitHub.models_enabled?
    business.can_show_models_billing?
  end

  sig { returns(T::Boolean) }
  def billing_enabled
    business.models_billing_enabled?
  end

  sig { returns(String) }
  def href
    if in_stafftools
      helpers.stafftools_enterprise_models_billing_path(business)
    else
      helpers.settings_models_update_billing_enterprise_path(business)
    end
  end

  private

  attr_reader :business, :in_stafftools
end
