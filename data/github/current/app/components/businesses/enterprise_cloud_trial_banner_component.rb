# typed: true
# frozen_string_literal: true

# This component renders a persistent header on all business's page.
# This will display some actionable actions based on the user permission on
# the business
class Businesses::EnterpriseCloudTrialBannerComponent < ApplicationComponent
  include BusinessesHelper
  include FeatureFlagHelper

  WARNING_THRESHOLD = 4
  TRIAL_WARNING_THRESHOLD = 7

  attr_reader :business, :on_dashboard, :viewing_org

  # if the on_dashboard flag is set to true, this means the banner
  # is being rendered in one of two places:
  # if viewing_org is present, the banner is rendered on the org's landing page
  # if viewing_org is nil, the banner is rendered on the business's getting started page
  def initialize(business:, on_dashboard: false, viewing_org: nil)
    @business = business
    @on_dashboard = on_dashboard
    @viewing_org = viewing_org
  end

  # Returns String
  def days_remaining
    return "#{startup_program_days_remaining} days left of free access" if display_for_startup_program?

    if business.trial_conversion_initiated?
      return "Your GitHub Enterprise purchase is being processed and may take a while."
    end

    return "Your GitHub Enterprise trial has expired." if business.trial_expired?
    return "Your trial will expire today." if business.trial_days_remaining.zero?

    if business.metered_ghe? && business.dfd_trial?
      return "#{pluralize(business.trial_days_remaining, "day")} left to try out Enterprise, GitHub Advanced Security and Copilot features."
    end

    "#{pluralize(business.trial_days_remaining, "day")} left on trial."
  end

  # Returns String
  def banner_color
    return "color-bg-severe color-border-severe" if business.trial_expired?

    warning? ? "color-bg-attention color-border-attention" : "color-bg-accent color-border-accent"
  end

  # Returns String
  def text_color
    return "color-fg-severe" if business.trial_expired?

    warning? ? "color-fg-attention" : "color-fg-default"
  end

  # Returns a Symbol to be used to set color of "Get started with suggested tasks" link in banner
  def text_color_symbol
    return :severe if business.trial_expired?

    warning? ? :attention : :accent
  end

  def link_color
    return "color-fg-severe" if business.trial_expired?

    "color-fg-accent"
  end

  # Returns String
  def font_weight
    return "font-weight: bold" if business.trial_expired?

    "font-weight: normal"
  end

  # Returns Array<Hash> of actions to display on the banner
  def actions
    return [about_github_enterprise_cloud_action] unless show_billing_settings_link?
    return startup_program_actions if display_for_startup_program?

    actions = []
    actions << talk_to_us_action unless current_user.is_first_emu_owner?
    actions
  end

  def startup_program_actions
    [
      {
        title: "Contact us",
        link: "mailto:startups@github.com",
      }
    ]
  end

  memoize def business_adminable_by_user?
    business.adminable_by?(current_user)
  end

  # Returns Boolean
  def render?
    return false unless business.present?
    business.trial? || display_for_startup_program?
  end

  memoize def is_billing_manager?
    business.billing_manager?(current_user)
  end

  def show_billing_settings_link?
    business_adminable_by_user? || is_billing_manager?
  end

  # Returns Boolean
  def show_go_to_dashboard?
    return false if on_dashboard
    return false unless business.trial?
    return false if business.feature_flag_enabled?(:digital_front_door_getting_started, default: false) && business_adminable_by_user?
    return false if business.trial_expired?

    viewing_org.present? && viewing_org.adminable_by?(current_user)
  end

  # Returns Boolean
  def show_suggested_tasks?
    return false if on_dashboard && viewing_org.nil?
    return false unless business.trial?
    return false if business.trial_expired?

    if business.feature_flag_enabled?(:digital_front_door_getting_started, default: false)
      return business_adminable_by_user?
    end

    viewing_org.nil? && business_adminable_by_user?
  end

  # Returns Boolean
  def should_display_banner?
    helpers.show_onboarding_experience_banner?(business)
  end

  def show_message_for_orgs_created_in_trial?
    return false unless business.trial_expired?
    return false if business.trial_deleted_at.present?
    business.organizations.present?
  end

  def show_expired_trial_deletion_countdown?
    return false unless business.eligible_for_expired_trial_deletion?
    business.trial_deleted_at.present?
  end

  def days_to_deletion
    (business.trial_deleted_at.to_date - Time.zone.now.to_date).to_i
  end

  private

  # Returns Boolean
  def warning?
    return false if business.trial_expired?
    return startup_program_days_remaining <= WARNING_THRESHOLD if display_for_startup_program?
    business.trial_days_remaining <= TRIAL_WARNING_THRESHOLD if business.trial?

  end

  memoize def startup_program_days_remaining
    ending_date = business.created_at.to_date + 1.year

    (ending_date - Date.current).to_i
  end

  def display_for_startup_program?
    business.part_of_startup_program? && business_adminable_by_user?
  end

  def display_buy_enterprise_button?
    business_adminable_by_user? && !business.trial_conversion_initiated? && !current_user.is_first_emu_owner?
  end

  def talk_to_us_action
    environment = GitHub.multi_tenant_enterprise? ? "proxima" : "dotcom"
    {
      title: "Talk to us",
      link: "https://github.com/enterprise/contact?utm_source=github&utm_medium=site&utm_campaign=enterprise_cloud_trial_banner_cta",
      data: {
        **analytics_click_attributes(
          category: "enterprise_trial_account",
          action: "talk_to_us",
          label: "enterprise_id:#{business.id};enterprise_slug:#{business.slug};location:enterprise_trial_banner;environment:#{environment}"),
      }
    }
  end

  def about_github_enterprise_cloud_action
    {
      title: "About GitHub Enterprise Cloud",
      link: "#{GitHub.help_url(ghec_exclusive: true)}",
    }
  end
end
