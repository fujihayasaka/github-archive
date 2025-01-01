# typed: true
# frozen_string_literal: true

# This component renders a persistent header on all organization's page.
# This will display some actionable actions based on the user permission on
# the organization
class Businesses::EnterpriseCloudOnboarding::SurveyBannerComponent < ApplicationComponent
  include BusinessesHelper

  SURVEY_LINK = "https://survey3.medallia.com/?C4EN7g-LgLrCR5aRtjoFQx"
  EXPIRED_DURATION_DAYS = 30
  MIN_NUMBER_OF_DAYS = 3

  attr_reader :custom_classes, :business

  def initialize(business, custom_classes: nil)
    @custom_classes = custom_classes
    @business       = business
  end

  def render?
    return false unless ever_been_in_trial?
    return false if !trial_active_for_minimum_days? && !trial_expired_within_threshold?
    true
  end

  def survey_link
    SURVEY_LINK
  end

  memoize def trial_expired?
    business.trial_expired?
  end

  private

  sig { returns(Date) }
  def started_on
    business.created_at.in_time_zone(GitHub::Billing.timezone).to_date
  end

  sig { returns(Date) }
  def expired_on
    business.trial_expires_at.in_time_zone(GitHub::Billing.timezone).to_date
  end

  def trial_active_for_minimum_days?
    !trial_expired? && trial_days_active >= MIN_NUMBER_OF_DAYS
  end

  def trial_days_active
    (GitHub::Billing.today - started_on).to_i
  end

  def trial_expired_within_threshold?
    trial_expired? && trial_days_expired <= EXPIRED_DURATION_DAYS
  end

  def trial_days_expired
    (GitHub::Billing.today - expired_on).to_i
  end

  def ever_been_in_trial?
    business.trial?
  end
end
