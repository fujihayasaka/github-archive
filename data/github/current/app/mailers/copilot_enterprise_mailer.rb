# typed: strict
# frozen_string_literal: true

class CopilotEnterpriseMailer < CopilotBaseMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers

  self.mailer_name = "mailers/copilot_enterprise"

  helper Primer::ViewHelper

  layout "layouts/copilot_enterprise_email"

  sig { params(business: Business).returns(String) }
  def welcome_business_admins(business)
    @has_mixed_licenses = T.let(business.admins.any? { |admin| GitHub.flipper[:copilot_mixed_licenses].enabled?(admin) }, T.nilable(T::Boolean))
    @product_name = T.let(@has_mixed_licenses ? "Copilot" : Copilot::ENTERPRISE_PRODUCT_NAME, T.nilable(String))
    @business = T.let(business, T.nilable(Business))
    @header = T.let("Welcome to GitHub #{@product_name}!", T.nilable(String))

    premail(
      from: github_noreply,
      bcc: admin_emails(business),
      subject: "[GitHub] [#{business.name}] Welcome to #{@product_name}!",
    )
  end

  sig { params(organization: Organization).returns(String) }
  def welcome_org_admins(organization)
    @organization = T.let(organization, T.nilable(Organization))
    @header = T.let("Welcome to GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME}!", T.nilable(String))

    premail(
      from: github_noreply,
      bcc: admin_emails(organization),
      subject: "[GitHub] [#{organization.display_login}] Welcome to #{Copilot::ENTERPRISE_PRODUCT_NAME}!",
    )
  end

  sig { params(organization: Organization, user: User).returns(String) }
  def welcome_individual(organization, user)
    @user = T.let(user, T.nilable(User))
    @organization = T.let(organization, T.nilable(Organization))
    @header = T.let("Welcome to GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME}!", T.nilable(String))
    @copilot_summary_beta_feature_enabled = T.let(user.feature_enabled?(:copilot_summary_beta), T.nilable(T::Boolean))

    premail(
      from: github_noreply,
      to: user_email(user, GitHub.newsies.email(user, organization).value),
      subject: "[GitHub] Welcome to #{Copilot::ENTERPRISE_PRODUCT_NAME}!",
    )
  end

  sig { params(organization: Organization, user: User, has_trial: T::Boolean).returns(String) }
  def upgrade_individual(organization, user, has_trial = false)
    @user = T.let(user, T.nilable(User))
    @organization = T.let(organization, T.nilable(Organization))
    @has_trial = T.let(has_trial, T.nilable(T::Boolean))
    @header = T.let("You have been granted access to GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME}.", T.nilable(String))
    @copilot_summary_beta_feature_enabled = T.let(user.feature_enabled?(:copilot_summary_beta), T.nilable(T::Boolean))

    premail(
      from: github_noreply,
      to: user_email(user),
      subject: "[GitHub] You have been granted access to GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME}!",
    )
  end

  sig { params(organization: Organization, trial_length: Integer).returns(String) }
  def trial_welcome(organization, trial_length)
    @organization = T.let(organization, T.nilable(Organization))
    @trial_length = T.let(trial_length, T.nilable(Integer))
    @mixed_licenses_feature_enabled = T.let(@organization&.business&.feature_enabled?(:copilot_mixed_licenses), T.nilable(T::Boolean))
    @header = T.let("Welcome to GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME}!", T.nilable(String))

    premail(
      from: github_noreply,
      bcc: admin_emails(organization),
      subject: "[GitHub] Welcome to your GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME} trial",
    )
  end

  sig { params(organization: Organization).returns(String) }
  def trial_half_over(organization)
    @organization = T.let(organization, T.nilable(Organization))
    @mixed_licenses_feature_enabled = T.let(@organization&.business&.feature_enabled?(:copilot_mixed_licenses), T.nilable(T::Boolean))
    @header = T.let("15 days left on your GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME} trial", T.nilable(String))

    premail(
      from: github_noreply,
      bcc: admin_emails(organization),
      subject: "[GitHub] Your organization’s #{organization.display_login} GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME} trial is halfway through",
    )
  end

  sig { params(organization: Organization).returns(String) }
  def trial_nearly_over(organization)
    @organization = T.let(organization, T.nilable(Organization))
    @mixed_licenses_feature_enabled = T.let(@organization&.business&.feature_enabled?(:copilot_mixed_licenses), T.nilable(T::Boolean))
    @header = T.let("Only 5 days left on your GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME} trial", T.nilable(String))

    premail(
      from: github_noreply,
      bcc: admin_emails(organization),
      subject: "[GitHub] Your organization’s #{organization.display_login} GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME} trial is almost over",
    )
  end

  sig { params(organization: Organization).returns(String) }
  def trial_final_day(organization)
    @organization = T.let(organization, T.nilable(Organization))
    @mixed_licenses_feature_enabled = T.let(@organization&.business&.feature_enabled?(:copilot_mixed_licenses), T.nilable(T::Boolean))
    @header = T.let("Only 1 day left on your GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME} trial", T.nilable(String))

    premail(
      from: github_noreply,
      bcc: admin_emails(organization),
      subject: "[GitHub] Your organization’s #{organization.display_login} GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME} trial expires today",
    )
  end

  sig { params(organization: Organization).returns(String) }
  def trial_expired(organization)
    @organization = T.let(organization, T.nilable(Organization))
    @already_on_copilot_enterprise = T.let(Copilot::Organization.new(organization).copilot_plan_enterprise?, T.nilable(T::Boolean))
    @mixed_licenses_feature_enabled = T.let(@organization&.business&.feature_enabled?(:copilot_mixed_licenses), T.nilable(T::Boolean))
    @header = if @already_on_copilot_enterprise
      T.let("Your organization’s GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME} trial has expired. Welcome to #{Copilot::ENTERPRISE_PRODUCT_NAME}!", T.nilable(String))
    else
      T.let("Your organization’s GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME} trial has expired and your access has been downgraded to GitHub #{Copilot::BUSINESS_PRODUCT_NAME}", T.nilable(String))
    end

    premail(
      from: github_noreply,
      bcc: admin_emails(organization),
      subject: "[GitHub] Your organization’s #{organization.display_login} GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME} trial has expired",
    )
  end

  sig { params(organization: Organization, user: User, trial_length: Integer).returns(String) }
  def trial_seat_added_for_user(organization, user, trial_length)
    @organization = T.let(organization, T.nilable(::Organization))
    @organization_name = T.let(organization.display_login, T.nilable(String))
    @user = T.let(user, T.nilable(User))
    @trial_length = T.let(trial_length, T.nilable(Integer))
    @header = T.let("You have been granted access to GitHub Copilot via an organization", T.nilable(String))

    premail(
      from: github_noreply,
      to: user_email(user, GitHub.newsies.email(user, organization).value),
      subject: "[GitHub] You have been granted access to GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME} by the organization #{organization.display_login}",
    )
  end

  sig { params(organization: Organization, user: User).returns(String) }
  def trial_expired_for_user(organization, user)
    @organization = T.let(organization, T.nilable(::Organization))
    @user = T.let(user, T.nilable(::User))
    @organization_name = T.let(organization.display_login, T.nilable(String))
    @header = T.let("Your GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME} access has expired and has been downgraded to GitHub #{Copilot::BUSINESS_PRODUCT_NAME}", T.nilable(String))

    premail(
      from: github_noreply,
      to: user_email(user, GitHub.newsies.email(user, organization).value),
      subject: "[GitHub] Your GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME} access has expired",
    )
  end

  sig { params(organization: ::Organization, user: ::User).returns(String) }
  def cfe_enabled_for_user(organization, user)
    @user = T.let(user, T.nilable(::User))
    @organization = T.let(organization, T.nilable(::Organization))
    @header = T.let("You have been granted access to GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME} beta.", T.nilable(String))
    @organization_login = T.let(organization.display_login, T.nilable(String))
    @user_login = T.let(user.display_login, T.nilable(String))
    @copilot_summary_beta_feature_enabled = T.let(user.feature_enabled?(:copilot_summary_beta), T.nilable(T::Boolean))

    premail(
      from: github_noreply,
      to: user_email(user, GitHub.newsies.email(user, organization).value),
      subject: "[GitHub] You have been granted access to GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME} beta.",
    )
  end

  sig { params(organization: ::Organization, user: ::User).returns(String) }
  def cfe_disabled_for_user(organization, user)
    @user = T.let(user, T.nilable(::User))
    @organization = T.let(organization, T.nilable(::Organization))
    @header = T.let("Your access for GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME} beta has been disabled.", T.nilable(String))
    @organization_login = T.let(organization.display_login, T.nilable(String))
    @user_login = T.let(user.display_login, T.nilable(String))
    @copilot_summary_beta_feature_enabled = T.let(user.feature_enabled?(:copilot_summary_beta), T.nilable(T::Boolean))

    premail(
      from: github_noreply,
      to: user_email(user, GitHub.newsies.email(user, organization).value),
      subject: "[GitHub] GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME} beta has been disabled by your organization.",
    )
  end

  sig { params(organization: ::Organization).returns(String) }
  def copilot_in_dotcom_disabled_for_organization(organization)
    @organization = T.let(organization, T.nilable(Organization))
    @header = T.let("Your organization access to GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME} has been disabled", T.nilable(String))

    premail(
      from: github_noreply,
      bcc: admin_emails(organization),
      subject: "[GitHub] Your organization’s #{organization.display_login} GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME} has been disabled",
    )
  end

  sig { params(organization: Organization, user: User).returns(String) }
  def copilot_in_dotcom_disabled_for_user(organization, user)
    @organization = T.let(organization, T.nilable(::Organization))
    @user = T.let(user, T.nilable(User))
    @header = T.let("Your access for GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME} has been disabled.", T.nilable(String))
    @organization_login = T.let(organization.display_login, T.nilable(String))
    @user_login = T.let(user.display_login, T.nilable(String))
    @copilot_summary_beta_feature_enabled = T.let(user.feature_enabled?(:copilot_summary_beta), T.nilable(T::Boolean))

    premail(
      from: github_noreply,
      to: user_email(user, GitHub.newsies.email(user, organization).value),
      subject: "[GitHub] GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME} has been disabled by your organization.",
    )
  end

  sig { returns(T.nilable(T.any(::User, ::Organization, ::Business))) }
  def mailable
    return @user if @user.present?
    return @organization if @organization.present?
    @business if @business.present?
  end
end
