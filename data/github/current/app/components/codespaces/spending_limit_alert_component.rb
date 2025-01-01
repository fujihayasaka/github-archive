# typed: true
# frozen_string_literal: true

class Codespaces::SpendingLimitAlertComponent < ApplicationComponent
  include CodespacesHelper

  attr_reader :usage, :organization
  def initialize(organization:)
    @organization = organization
    @usage = Codespaces::AccessChecker.new(@organization)
  end

  def render?
    # don't render if codespaces are allowed for the org by Codespaces::OrgPolicy
    return false unless organization.codespaces_feature_enabled?

    # don't show anything to do with payment if free codespace use is enabled
    return false if organization.free_codespace_use_enabled?

    spending_limit_set? && !usage.allowed_by_billing?
  end

  def cta_href
    settings_org_billing_path(organization)
  end

  private

  def budget
    organization.budget_for(group: "codespaces")
  end

  def spending_limit_set?
    # note: this doesn't check if the org has any budget left! it only checks if the org has
    # a non-zero/unlimited codespaces spending limit set
    budget.enforcement_configured? && budget.overage_allowed?
  end
end
