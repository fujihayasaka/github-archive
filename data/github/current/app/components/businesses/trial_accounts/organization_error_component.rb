# typed: true
# frozen_string_literal: true

class Businesses::TrialAccounts::OrganizationErrorComponent < ApplicationComponent
  attr_reader :organization

  def initialize(organization:, any_organizations:, max_seat_count: 0)
    @organization = organization
    @any_organizations = any_organizations
    @max_seat_count = max_seat_count
  end

  def any_organizations?
    @any_organizations
  end

  def test_selector
    if @max_seat_count > 0
      "new-business-trial-organization-selection-seats-limit"
    else
      "new-business-trial-organization-selection-marketplace-apps"
    end
  end

  def error_reason
    if @max_seat_count > 0
      "requires more than #{pluralize(@max_seat_count, "seat")}"
    else
      "has marketplace applications. You can invite this organization once you have purchased Enterprise"
    end
  end
end
