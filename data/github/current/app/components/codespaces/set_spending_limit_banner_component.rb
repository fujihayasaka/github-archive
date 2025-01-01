# typed: true
# frozen_string_literal: true

class Codespaces::SetSpendingLimitBannerComponent < ApplicationComponent
  include BillingSettingsHelper

  attr_reader :organization

  def initialize(organization:)
    @organization = organization
  end

  def render?
    return false unless organization.codespaces_feature_enabled?

    # don't show anything to do with payment if free codespace use is enabled
    return false if organization.free_codespace_use_enabled?

    return false if organization.feature_enabled?(:codespaces_v_next_fix_budget_calls) && organization.billing_v_next_enabled_for_codespaces?

    !valid_payment_method_configured? || untouched_spending_limit?
  rescue Billing::Api::ClientWrapper::BillingClientError
    false
  end

  private

  def valid_payment_method_configured?
    Codespaces::BillingPolicy.valid_organization_payment_method_configured?(organization)
  end

  def untouched_spending_limit?
    # note: this doesn't check if the org has any budget left! it only checks if the org has
    # a non-zero/unlimited codespaces spending limit set
    !budget.enforcement_configured? || !budget.overage_allowed?
  end

  def budget
    organization.billable_owner.budget_for(group: "codespaces")
  end
end
