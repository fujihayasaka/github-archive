# typed: true
# frozen_string_literal: true

# This component renders a persistent header on all organization's page.
# This will display some actionable actions based on the user permission on
# the organization
class Organizations::EnterpriseCloudOnboarding::SurveyBannerComponent < ApplicationComponent
  include OrganizationsHelper

  SURVEY_LINK = "https://survey3.medallia.com/?PBiAVI-VhobnvdouQdrZHr"
  EXPIRED_DURATION_DAYS = 30
  MIN_NUMBER_OF_DAYS = 3

  attr_reader :custom_classes, :organization, :trial

  def initialize(trial, organization, custom_classes: nil)
    @custom_classes = custom_classes
    @organization   = organization
    @trial          = trial
  end

  def render?
    return false if current_page?(settings_org_oauth_application_policy_path(organization))
    return false unless trial.ever_been_in_trial?
    return false if !trial_active_for_minimum_days?(trial) && !trial_expired_within_threshold?(trial)

    true
  end

  def survey_link
    SURVEY_LINK
  end

  memoize def trial_expired?
    trial.expired?
  end

  private

  def trial_active_for_minimum_days?(trial)
    trial.active? && trial.days_active >= MIN_NUMBER_OF_DAYS
  end

  def trial_expired_within_threshold?(trial)
    trial_expired? && trial.expired_within?(EXPIRED_DURATION_DAYS.days)
  end
end
