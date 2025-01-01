# typed: true
# frozen_string_literal: true

class Organizations::Settings::GhasRepositoriesHeaderComponent < ApplicationComponent

  include SecurityAnalysisSettingsHelper

  def initialize(organization:)
    @organization = organization
  end

  def render?
    advanced_security_purchased?
  end

  # Note that @organization.advanced_security_license returns the
  # license for the relevant billable entity (org or business), not
  # necessarily for the org on which it's called.
  memoize def advanced_security_license
    @organization.advanced_security_license
  end

  memoize def advanced_security_purchased?
    @organization.advanced_security_purchased?
  end

  # This includes committers who may also be active in other orgs
  memoize def seats_used_by_org
    @organization.advanced_security_seats_used
  end

  memoize def unused_seats
    advanced_security_license.remaining_seats
  end

  memoize def purchased_seats
    advanced_security_license.seats
  end

  memoize def other_entities_licenses
    advanced_security_license.consumed_seats - seats_used_by_org
  end

  memoize def unlimited_seats?
    advanced_security_license.unlimited_seats?
  end

  memoize def business_license?
    advanced_security_license.billable_entity.is_a?(Business)
  end
end
