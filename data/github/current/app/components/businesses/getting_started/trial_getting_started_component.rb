# typed: true
# frozen_string_literal: true

class Businesses::GettingStarted::TrialGettingStartedComponent < ApplicationComponent
  attr_reader :business

  def initialize(business:)
    @business = business
  end

  private

  sig { returns(T::Boolean) }
  def render?
    return false if GitHub.single_or_multi_tenant_enterprise?
    return false unless business.present?
    return false unless current_user.present?
    return false unless business.owner?(current_user)
    return false unless business.trial?
    true
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def add_members_tasks
    tasks = []

    tasks << {
      id: "create-organization",
      icon: :organization,
      icon_color: "yellow",
      icon_text_color_class: "fgColor-attention",
      text_color_class: "fgColor-default",
      title: "Create an organization",
      description: "Set up an organization to manage users, repositories, and permissions. All members get Enterprise access.",
      link: new_enterprise_onboarding_organization_path(business)
    } unless business.trial_with_organization?

    tasks << {
      id: "invite-owners",
      icon: :"person-add",
      icon_color: "yellow",
      icon_text_color_class: "fgColor-attention",
      text_color_class: "fgColor-default",
      title: "Invite owners",
      description: "Invite people to manage your enterprise.",
      link: enterprise_admins_path(business, show_onboarding_guide_tip: true)
    } unless business.trial_with_invited_owner?

    tasks
  end

  def copilot_tasks
    tasks = []

    tasks << {
      id: "verify-identity",
      icon: :"credit-card",
      icon_color: "purple",
      icon_text_color_class: "fgColor-done",
      text_color_class: "fgColor-default",
      title: "Verify your identity to use Copilot",
      description: "Secure your account to start using Copilot. Unlock AI-powered coding for your team.",
      link: enterprise_trial_activations_path(business)
    } unless business.trial_with_verified_identity_for_copilot?

    tasks << {
      id: "enable-copilot",
      icon: :"copilot",
      icon_color: "purple",
      icon_text_color_class: "fgColor-done",
      text_color_class: "fgColor-default",
      title: "Invite members to Copilot",
      description: "Enable your team to use Copilot. Boost productivity with AI-powered code suggestions.",
    } if business.trial_with_verified_identity_for_copilot? && !business.trial_with_two_copilot_seats_assigned?

    tasks << {
      id: "enable-copilot",
      icon: :"lock",
      icon_color: "gray",
      icon_text_color_class: "fgColor-muted",
      text_color_class: "fgColor-default",
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
      text_color_class: "fgColor-default",
      title: "Set up Secret Scanning",
      description: "Protect your code by scanning repositories for exposed credentials and secrets before they become a risk.",
      link: enterprise_security_center_metrics_secret_scanning_path(business),
    } unless business.trial_with_secret_scanning?

    tasks << {
      id: "enable-code-scanning",
      icon: :codescan,
      icon_color: "blue",
      icon_text_color_class: "fgColor-accent",
      text_color_class: "fgColor-default",
      title: "Set up Code Scanning",
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
      text_color_class: "fgColor-default",
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
      title: "You invited members to Copilot",
      description: "Let your team know that they can start using Copilot in their IDE, or chat with Copilot.",
    } if business.trial_with_verified_identity_for_copilot? && business.trial_with_two_copilot_seats_assigned?

    tasks << {
      id: "secret-scanning-enabled",
      icon: :check,
      icon_color: "blue",
      icon_text_color_class: "fgColor-accent",
      text_color_class: "color-fg-muted",
      title: "You tried Secret Scanning",
      description: "Check back in 7 days to check if any secrets have been leaked. ",
      link: enterprise_security_center_metrics_secret_scanning_path(business),
    } if business.trial_with_secret_scanning?

    tasks << {
      id: "code-scanning-enabled",
      icon: :check,
      icon_color: "blue",
      icon_text_color_class: "fgColor-accent",
      text_color_class: "color-fg-muted",
      title: "You tried Code Scanning",
      description: "Check back in 14 days to make sure your code is fully secure.",
      link: security_center_alerts_code_scanning_enterprise_path(business),
    } if business.trial_with_code_scanning?

    tasks << {
      id: "saml-sso-enabled",
      icon: :check,
      icon_color: "green",
      icon_text_color_class: "fgColor-open",
      text_color_class: "color-fg-muted",
      title: "You enabled SAML Single Sign-On",
      description: "Now, you can add members and they can log in securely with ease.",
    } if business.trial_with_saml_sso?

    tasks
  end
end
