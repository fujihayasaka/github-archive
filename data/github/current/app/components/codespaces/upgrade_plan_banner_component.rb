# typed: true
# frozen_string_literal: true

class Codespaces::UpgradePlanBannerComponent < ApplicationComponent
  include BillingSettingsHelper

  attr_reader :organization, :org_policy

  def initialize(organization:, org_policy:)
    @organization = organization
    @org_policy = org_policy
  end

  # This should render if the organization needs to upgrade to enable codespaces ownership.
  def render?
    org_policy.must_upgrade_to_use_codespaces? &&
      BillingSettings::OverviewView.new(account: organization, current_user: current_user).account_can_upgrade?
  end
end
