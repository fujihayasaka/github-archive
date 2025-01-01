# typed: true
# frozen_string_literal: true

class Onboarding::Organizations::ToggleComponent < ApplicationComponent

  attr_reader :organization, :user

  def initialize(organization:, user:)
    @organization = organization
    @user = user
  end

  def render?
    return if GitHub.enterprise?
    return unless organization&.organization?
    return unless organization.adminable_by?(user)
    return if organization.enterprise_managed_user_enabled?
    true
  end

  def show_for_trial?
    organization.show_onboarding_tasks.nil? && trial_active?
  end

  private

  def trial_active?
    trial = Billing::EnterpriseCloudTrial.new(organization)
    trial.active?
  end
end
