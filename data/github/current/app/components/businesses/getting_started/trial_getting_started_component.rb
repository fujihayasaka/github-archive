# typed: true
# frozen_string_literal: true

class Businesses::GettingStarted::TrialGettingStartedComponent < ApplicationComponent
  attr_reader :business, :user_session

  def initialize(business:, user_session:)
    @business = business
    @user_session = user_session
  end

  sig { returns(T::Boolean) }
  def render?
    return false if GitHub.single_business_environment?
    return false unless business.present?
    return false unless user_session.present?
    return false unless current_user.present?
    return false unless business.owner?(current_user)
    return false unless business.trial?
    true
  end

  TOTAL_TASK_COUNT = FeatureFlag.vexi.enabled?(:enterprise_copilot_licensing, @business, default: false) ? 8 : 7

  def all_tasks_completed?
    completed_tasks.count == TOTAL_TASK_COUNT && business.trial_with_readme?
  end

  sig { returns(T::Boolean) }
  def trial_expired?
    business.trial_expired?
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def add_members_tasks
    tasks = []

    tasks << {
      id: "create-organization",
      icon: :organization,
      icon_color: "yellow",
      icon_text_color_class: "fgColor-attention",
      text_color_class: "color-fg-default",
      description_text_color_class: "color-fg-muted",
      title: "Create an organization",
      description: "Set up an organization to manage users, repositories, and permissions. All members get Enterprise access.",
      link: new_enterprise_onboarding_organization_path(business)
    } unless business.trial_with_organization?

    tasks << {
      id: "invite-owners",
      icon: :"person-add",
      icon_color: "yellow",
      icon_text_color_class: "fgColor-attention",
      text_color_class: "color-fg-default",
      description_text_color_class: "color-fg-muted",
      title: "Invite owners",
      description: "Invite people to manage your enterprise.",
      link: enterprise_admins_path(business, show_onboarding_guide_tip: true)
    } unless business.trial_with_invited_owner?

    tasks << {
      id: "invite-enterprise-members",
      icon: :"person-add",
      icon_color: "yellow",
      icon_text_color_class: "fgColor-attention",
      text_color_class: "color-fg-default",
      description_text_color_class: "color-fg-muted",
      title: "Invite enterprise members",
      description: "Invite people to join your enterprise.",
      link: people_enterprise_path(business, show_onboarding_guide_tip: true)
    } if FeatureFlag.vexi.enabled?(:enterprise_copilot_licensing, business, default: false) && !business.trial_with_invited_member?

    tasks
  end

  def copilot_tasks
    tasks = []

    tasks << {
      id: "verify-identity",
      icon: :"credit-card",
      icon_color: "purple",
      icon_text_color_class: "fgColor-done",
      text_color_class: "color-fg-default",
      description_text_color_class: "color-fg-muted",
      title: "Verify your identity to use Copilot",
      description: "Secure your account to start using Copilot. Unlock AI-powered coding for your team.",
      link: enterprise_trial_activations_path(business)
    } unless business.trial_with_verified_identity_for_copilot?

    tasks << {
      id: "enable-copilot",
      icon: :"copilot",
      icon_color: "purple",
      icon_text_color_class: "fgColor-done",
      text_color_class: "color-fg-default",
      description_text_color_class: "color-fg-muted",
      title: "Add members to Copilot",
      description: "Enable your team to use Copilot. Boost productivity with AI-powered code suggestions.",
      link: FeatureFlag.vexi.enabled?(:enterprise_copilot_licensing, business, default: false) ? copilot_licensing_enterprise_path(business) : settings_copilot_enterprise_path(business)
    } if business.trial_with_verified_identity_for_copilot? && !business.trial_with_two_copilot_seats_assigned?

    tasks << {
      id: "enable-copilot",
      icon: :"lock",
      icon_color: "gray",
      icon_text_color_class: "fgColor-muted",
      text_color_class: "color-fg-muted",
      description_text_color_class: "color-fg-muted",
      title: "Before you add members to Copilot, you must verify your identity.",
      description: "Enable your team to try Copilot. Boost productivity by 55% with AI-powered code suggestions and Copilot chat.",
    } unless business.trial_with_verified_identity_for_copilot?

    tasks
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def security_tasks
    tasks = []

    tasks << {
      id: "enable-secret-scanning",
      icon: :shield,
      icon_color: "blue",
      icon_text_color_class: "fgColor-accent",
      text_color_class: "color-fg-default",
      description_text_color_class: "color-fg-muted",
      title: "Try Secret Scanning",
      description: "Protect your code by scanning repositories for exposed credentials and secrets before they become a risk.",
      link: security_center_alerts_secret_scanning_enterprise_path(business),
    } unless business.trial_with_secret_scanning?

    tasks << {
      id: "enable-code-scanning",
      icon: :codescan,
      icon_color: "blue",
      icon_text_color_class: "fgColor-accent",
      text_color_class: "color-fg-default",
      description_text_color_class: "color-fg-muted",
      title: "Try Code Security",
      description: "Find and fix security issues early with automated scanning and insights.",
      link: security_center_alerts_code_scanning_enterprise_path(business),
    } unless business.trial_with_code_scanning?

    tasks
  end

  def further_setup_tasks
    tasks = []

    tasks << {
      id: "enable-saml-sso",
      icon: :codescan,
      icon_color: "green",
      icon_text_color_class: "fgColor-open",
      text_color_class: "color-fg-default",
      description_text_color_class: "color-fg-muted",
      title: "Enable SAML Single Sign-On",
      description: "Improve security with SAML SSO. Simplify logins while maintaining control.",
      link: settings_security_enterprise_path(business),
    } unless business.trial_with_saml_sso?

    tasks
  end

  def completed_tasks
    tasks = []

    tasks << {
      id: "organization-created",
      icon: :check,
      icon_color: "yellow",
      icon_text_color_class: "fgColor-attention",
      text_color_class: "color-fg-muted",
      description_text_color_class: "color-fg-muted",
      title: "You added an organization",
      description: "You have already added an organization, you can add members to your Enterprise by inviting them to your organization.",
      link: new_enterprise_onboarding_organization_path(business)
    } if business.trial_with_organization?

    tasks << {
      id: "owners-invited",
      icon: :check,
      icon_color: "yellow",
      icon_text_color_class: "fgColor-attention",
      text_color_class: "color-fg-muted",
      description_text_color_class: "color-fg-muted",
      title: "You added owners to your Enterprise",
      description: "Let them know they can explore Enterprise features with you.",
      link: enterprise_admins_path(business, show_onboarding_guide_tip: true)
    } if business.trial_with_invited_owner?

    tasks << {
      id: "identity-verified",
      icon: :check,
      icon_color: "purple",
      icon_text_color_class: "fgColor-done",
      text_color_class: "color-fg-muted",
      description_text_color_class: "color-fg-muted",
      title: "You verified your identity",
      description: "You can now use Copilot! Invite your team to try it.",
      link: enterprise_trial_activations_path(business)
    } if business.trial_with_verified_identity_for_copilot?

    tasks << {
      id: "copilot-enabled",
      icon: :check,
      icon_color: "purple",
      icon_text_color_class: "fgColor-done",
      text_color_class: "color-fg-muted",
      description_text_color_class: "color-fg-muted",
      title: "You invited members to Copilot",
      description: "Let your team know that they can start using Copilot in their IDE, or chat with Copilot.",
      link: settings_copilot_enterprise_path(business)
    } if business.trial_with_verified_identity_for_copilot? && business.trial_with_two_copilot_seats_assigned?

    tasks << {
      id: "secret-scanning-enabled",
      icon: :check,
      icon_color: "blue",
      icon_text_color_class: "fgColor-accent",
      text_color_class: "color-fg-muted",
      description_text_color_class: "color-fg-muted",
      title: "You tried Secret Scanning",
      description: "Check back in 7 days to check if any secrets have been leaked. ",
      link: security_center_alerts_secret_scanning_enterprise_path(business)
    } if business.trial_with_secret_scanning?

    tasks << {
      id: "code-scanning-enabled",
      icon: :check,
      icon_color: "blue",
      icon_text_color_class: "fgColor-accent",
      text_color_class: "color-fg-muted",
      description_text_color_class: "color-fg-muted",
      title: "You tried Code Security",
      description: "Check back in 14 days to make sure your code is fully secure.",
      link: security_center_alerts_code_scanning_enterprise_path(business)
    } if business.trial_with_code_scanning?

    tasks << {
      id: "saml-sso-enabled",
      icon: :check,
      icon_color: "green",
      icon_text_color_class: "fgColor-open",
      text_color_class: "color-fg-muted",
      description_text_color_class: "color-fg-muted",
      title: "You enabled SAML Single Sign-On",
      description: "Now, you can add members and they can log in securely with ease.",
      link: settings_security_enterprise_path(business)
    } if business.trial_with_saml_sso?

    tasks
  end
end
