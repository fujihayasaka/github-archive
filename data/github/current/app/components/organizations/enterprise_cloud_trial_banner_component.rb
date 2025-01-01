# typed: true
# frozen_string_literal: true

# This component renders a persistent header on all organization's page.
# This will display some actionable actions based on the user permission on
# the organization
# Soon business_trial flag is fully shipped to everyone we can drop this component
# and rely only on the Businesses::EnterpriseCloudTrialBannerComponent.

class Organizations::EnterpriseCloudTrialBannerComponent < ApplicationComponent
  include FeatureFlagHelper

  WARNING_THRESHOLD = 4

  attr_reader :organization, :trial

  def initialize(organization:, on_dashboard: false)
    @organization = organization
    @trial        = Billing::EnterpriseCloudTrial.new(organization)
    @on_dashboard = on_dashboard
  end

  def days_remaining
    return "Your GitHub Enterprise trial has expired" if trial_expired?
    return "Your trial will expire today" if trial.days_remaining.zero?

    "#{pluralize(trial.days_remaining, "day")} left on trial"
  end

  def warn_class
    warning? ? "flash-warn" : "trial-banner-notice"
  end

  def text_color_class
    warning? ? "color-fg-attention" : "color-text-white"
  end

  # @return [Array<Hash>] the actions to display on the bar
  def actions
    return [] unless organization_adminable_by_user?

    [
      {
        title: "Upgrade to Enterprise",
        link: helpers.upgrade_path(plan: GitHub::Plan.business_plus, target: "organization", org: organization),
      },
      {
        title: "Talk to us",
        link: "#{enterprise_contact_url}?utm_source=github&utm_medium=site&utm_campaign=enterprise_cloud_trial_banner_cta",
      }
    ]
  end

  memoize def organization_adminable_by_user?
    organization.adminable_by?(current_user)
  end

  def render?
    return unless organization&.organization?
    return if current_page?(settings_org_oauth_application_policy_path(organization))
    return if controller.class.ancestors.include?(Businesses::BusinessController) # This can be dropped soon we fully ship business trial and rely only on the Businesses::EnterpriseCloudTrialBannerComponent

    true
  end

  def show_go_to_dashboard?
    !on_dashboard && showing_onboarding_tasks?
  end

  def show_get_started_with_tasks?
    trial.active? && !showing_onboarding_tasks?
  end

  def should_display_banner?
    trial.should_display_banner_for?(current_user) && helpers.display_organization_notice?(organization, current_user, :enterprise_trial_banner)
  end

  private

  attr_accessor :on_dashboard

  alias :on_dashboard? :on_dashboard

  memoize def trial_expired?
    trial.expired?
  end

  def warning?
    trial.days_remaining <= WARNING_THRESHOLD
  end

  memoize def showing_onboarding_tasks?
    helpers.display_organization_notice?(organization, current_user, :enterprise_trial_onboarding, for_whole_org: true)
  end
end
