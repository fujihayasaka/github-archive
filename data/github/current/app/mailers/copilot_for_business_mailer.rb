# typed: strict
# frozen_string_literal: true

class CopilotForBusinessMailer < CopilotBaseMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers

  self.mailer_name = "mailers/copilot_for_business"

  helper Primer::ViewHelper

  layout "layouts/copilot_business_email"

  sig do
    params(grantor: T.any(::Organization, ::Business), user: ::User).returns(String)
  end
  def seat_added_for_user(grantor, user)
    @grantor = T.let(grantor, T.any(T.nilable(::Organization), T.nilable(::Business)))
    @user = T.let(user, T.nilable(::User))
    @grantor_name = T.let(
      if @grantor.is_a? ::Organization
        @grantor.display_login
      elsif @grantor.is_a? ::Business
        @grantor.slug
      end,
    T.nilable(String))

    @friendly_grantor_type = T.let(@grantor.class.name&.downcase, T.nilable(String))

    # the newsies method can have an organization optionally passed in
    organization = @grantor.is_a?(::Organization) ? grantor : nil

    premail(
      from: github_noreply,
      to: user_email(user, GitHub.newsies.email(user, organization).value),
      subject: "You have been granted access to GitHub Copilot",
    )
  end

  sig do
    params(
      organization: ::Organization,
      user: ::User,
      payment_type: String,
      refund_amount_in_cents: Integer,
      refunded_at: Time,
      sale_date: Date,
    ).returns(String)
  end
  def seat_added_for_user_with_cfi_refund(organization, user, payment_type, refund_amount_in_cents, refunded_at, sale_date)
    @organization = T.let(organization, T.nilable(::Organization))
    @organization_name = T.let(organization.display_login, T.nilable(String))
    @user = T.let(user, T.nilable(::User))
    @user_name = T.let(user.display_login, T.nilable(String))
    @payment_type = T.let(payment_type, T.nilable(String))
    @refund_amount = T.let(Money.usd(refund_amount_in_cents), T.nilable(Money))
    @refunded_at = T.let(refunded_at, T.nilable(Time))
    @sale_date = T.let(sale_date, T.nilable(Date))

    premail(
      from: github_noreply,
      to: user_email(user, GitHub.newsies.email(user, organization).value),
      subject: "You have been granted access to GitHub Copilot",
    )
  end

  sig do
    params(
      organization: ::Organization,
      user: ::User,
    ).returns(String)
  end
  def seat_added_for_user_with_cfi_trial(organization, user)
    @organization = T.let(organization, T.nilable(::Organization))
    @user = T.let(user, T.nilable(::User))
    @organization_name = T.let(organization.display_login, T.nilable(String))
    @user_name = T.let(user.display_login, T.nilable(String))

    premail(
      from: github_noreply,
      to: user_email(user, GitHub.newsies.email(user, organization).value),
      subject: "You have been granted access to GitHub Copilot",
    )
  end

  sig do
    params(grantor: T.nilable(T.any(::Organization, ::Business)), user: ::User)
      .returns(String)
  end
  def seat_removed_for_user(grantor, user)
    @grantor = T.let(grantor, T.any(T.nilable(::Organization), T.nilable(::Business)))
    @user = T.let(user, T.nilable(::User))
    @grantor_name = T.let(
      if @grantor.is_a? ::Organization
        @grantor.display_login
      elsif @grantor.is_a? ::Business
        @grantor.slug
      end,
    T.nilable(String))
    @friendly_grantor_type = T.let(@grantor.class.name&.downcase, T.nilable(String))

    organization = @grantor.is_a?(::Organization) ? grantor : nil

    premail(
      from: github_noreply,
      to: user_email(user, GitHub.newsies.email(user, organization).value),
      subject: "Your GitHub Copilot access has been disabled",
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
      subject: "[GitHub] You have been granted access to GitHub #{Copilot::BUSINESS_PRODUCT_NAME} by the organization #{organization.display_login}",
    )
  end

  sig { params(organization: Organization, user: User).returns(String) }
  def trial_seat_expired_for_user(organization, user)
    @organization = T.let(organization, T.nilable(::Organization))
    @user = T.let(user, T.nilable(::User))
    @organization_name = T.let(organization.display_login, T.nilable(String))
    @user = T.let(user, T.nilable(User))
    @header = T.let("Your GitHub #{Copilot::BUSINESS_PRODUCT_NAME} access has expired", T.nilable(String))

    premail(
      from: github_noreply,
      to: user_email(user, GitHub.newsies.email(user, organization).value),
      subject: "[GitHub] Your GitHub #{Copilot::BUSINESS_PRODUCT_NAME} access has expired",
    )
  end

  sig { params(organization: ::Organization).returns(String) }
  def cfb_enabled(organization)
    @organization = T.let(organization, T.nilable(::Organization))
    @organization_name = T.let(organization.display_login, T.nilable(String))
    @organization_login = T.let(organization.display_login, T.nilable(String))

    premail(
      from: github_noreply,
      bcc: admin_emails(organization),
      subject: "GitHub Copilot is now accessible for your organization.",
    )
  end

  sig do
    params(business: ::Business, organization: ::Organization)
      .returns(String)
  end
  def cfb_enabled_by_business(business, organization)
    @business = T.let(business, T.nilable(::Business))
    @organization = T.let(organization, T.nilable(::Organization))
    @business_name = T.let(business.name, T.nilable(String))
    @organization_name = T.let(organization.display_login, T.nilable(String))
    @organization_login = T.let(organization.display_login, T.nilable(String))

    premail(
      from: github_noreply,
      bcc: admin_emails(organization),
      subject: "Your organization has been granted access to GitHub Copilot",
    )
  end

  sig do
    params(business: ::Business, organization: ::Organization)
      .returns(String)
  end
  def cfb_disabled_by_business(business, organization)
    @organization = T.let(organization, T.nilable(::Organization))
    @business_name = T.let(business.name, T.nilable(String))
    @organization_name = T.let(organization.display_login, T.nilable(String))

    premail(
      from: github_noreply,
      bcc: admin_emails(organization),
      subject: "Your organization access to GitHub Copilot has been revoked",
    )
  end

  sig { params(organization: Organization, trial_length: Integer).returns(String) }
  def trial_welcome(organization, trial_length)
    @organization = T.let(organization, T.nilable(Organization))
    @trial_length = T.let(trial_length, T.nilable(Integer))
    @header = T.let("Welcome to GitHub #{Copilot::BUSINESS_PRODUCT_NAME}!", T.nilable(String))

    premail(
      from: github_noreply,
      bcc: admin_emails(organization),
      subject: "[GitHub] Welcome to your GitHub #{Copilot::BUSINESS_PRODUCT_NAME} trial",
    )
  end

  sig { params(organization: Organization).returns(String) }
  def trial_half_over(organization)
    @organization = T.let(organization, T.nilable(Organization))
    @header = T.let("15 days left on your GitHub #{Copilot::BUSINESS_PRODUCT_NAME} trial", T.nilable(String))

    premail(
      from: github_noreply,
      bcc: admin_emails(organization),
      subject: "[GitHub] Your organization’s #{organization.display_login} GitHub #{Copilot::BUSINESS_PRODUCT_NAME} trial is halfway through",
    )
  end

  sig { params(organization: Organization).returns(String) }
  def trial_nearly_over(organization)
    @organization = T.let(organization, T.nilable(Organization))
    @header = T.let("Only 5 days left on your GitHub #{Copilot::BUSINESS_PRODUCT_NAME} trial", T.nilable(String))

    premail(
      from: github_noreply,
      bcc: admin_emails(organization),
      subject: "[GitHub] Your organization’s #{organization.display_login} GitHub #{Copilot::BUSINESS_PRODUCT_NAME} trial is almost over",
    )
  end

  sig { params(organization: Organization).returns(String) }
  def trial_final_day(organization)
    @organization = T.let(organization, T.nilable(Organization))
    @header = T.let("Only 1 day left on your GitHub #{Copilot::BUSINESS_PRODUCT_NAME} trial", T.nilable(String))

    premail(
      from: github_noreply,
      bcc: admin_emails(organization),
      subject: "[GitHub] Your organization’s #{organization.display_login} GitHub #{Copilot::BUSINESS_PRODUCT_NAME} trial expires today",
    )
  end

  sig { params(organization: Organization).returns(String) }
  def trial_expired(organization)
    @organization = T.let(organization, T.nilable(Organization))
    @header = T.let("Your organization’s GitHub #{Copilot::BUSINESS_PRODUCT_NAME} trial has expired", T.nilable(String))

    premail(
      from: github_noreply,
      bcc: admin_emails(organization),
      subject: "[GitHub] Your organization’s #{organization.display_login} GitHub #{Copilot::BUSINESS_PRODUCT_NAME} trial has expired",
    )
  end

  sig { params(organization: ::Organization, user: ::User).returns(String) }
  def chat_enabled_for_user(organization, user)
    @organization = T.let(organization, T.nilable(::Organization))
    @header = T.let("You have been granted access to #{Copilot::COPILOT_CHAT_IN_IDE}", T.nilable(String))
    @organization_login = T.let(organization.display_login, T.nilable(String))
    @user_login = T.let(user.display_login, T.nilable(String))
    @user = T.let(user, T.nilable(User))

    subject = "[GitHub] You have been granted access to #{Copilot::COPILOT_CHAT_IN_IDE}"
    premail(
      from: github_noreply,
      to: user_email(user, GitHub.newsies.email(user, organization).value),
      subject: subject
    )
  end

  sig { params(organization: ::Organization, user: ::User).returns(String) }
  def chat_disabled_for_user(organization, user)
    @organization = T.let(organization, T.nilable(::Organization))
    @user = T.let(user, T.nilable(User))
    @header = T.let("Your access for #{Copilot::COPILOT_CHAT_IN_IDE} has been disabled.", T.nilable(String))
    @organization_login = T.let(organization.display_login, T.nilable(String))
    @user_login = T.let(user.display_login, T.nilable(String))

    premail(
      from: github_noreply,
      to: user_email(user, GitHub.newsies.email(user, organization).value),
      subject: "[GitHub] #{Copilot::COPILOT_CHAT_IN_IDE} has been disabled by your organization.",
    )
  end

  sig { params(organization: ::Organization, user: ::User).returns(String) }
  def cli_enabled_for_user(organization, user)
    @user = T.let(user, T.nilable(::User))
    @organization = T.let(organization, T.nilable(::Organization))
    @header = T.let("You have been granted access to GitHub #{Copilot::CLI_UI_NAME}.", T.nilable(String))
    @organization_login = T.let(organization.display_login, T.nilable(String))
    @user_login = T.let(user.display_login, T.nilable(String))

    premail(
      from: github_noreply,
      to: user_email(user, GitHub.newsies.email(user, organization).value),
      subject: "[GitHub] You have been granted access to GitHub #{Copilot::CLI_UI_NAME}",
    )
  end

  sig { params(organization: ::Organization, user: ::User).returns(String) }
  def cli_disabled_for_user(organization, user)
    @user = T.let(user, T.nilable(::User))
    @organization = T.let(organization, T.nilable(::Organization))
    @header = T.let("Your access for GitHub #{Copilot::CLI_UI_NAME} has been disabled.", T.nilable(String))
    @organization_login = T.let(organization.display_login, T.nilable(String))
    @user_login = T.let(user.display_login, T.nilable(String))

    premail(
      from: github_noreply,
      to: user_email(user, GitHub.newsies.email(user, organization).value),
      subject: "[GitHub] GitHub #{Copilot::CLI_UI_NAME} has been disabled by your organization.",
    )
  end

  sig { params(organization: ::Organization, user: ::User).returns(String) }
  def desktop_enabled_for_user(organization, user)
    @user = T.let(user, T.nilable(::User))
    @organization = T.let(organization, T.nilable(::Organization))
    @header = T.let("You have been granted access to GitHub #{Copilot::COPILOT_DESKTOP}.", T.nilable(String))
    @organization_login = T.let(organization.display_login, T.nilable(String))
    @user_login = T.let(user.display_login, T.nilable(String))

    premail(
      from: github_noreply,
      to: user_email(user, GitHub.newsies.email(user, organization).value),
      subject: "[GitHub] You have been granted access to GitHub #{Copilot::COPILOT_DESKTOP}",
    )
  end

  sig { params(organization: ::Organization, user: ::User).returns(String) }
  def desktop_disabled_for_user(organization, user)
    @user = T.let(user, T.nilable(::User))
    @organization = T.let(organization, T.nilable(::Organization))
    @header = T.let("Your access for GitHub #{Copilot::COPILOT_DESKTOP} has been disabled.", T.nilable(String))
    @organization_login = T.let(organization.display_login, T.nilable(String))
    @user_login = T.let(user.display_login, T.nilable(String))

    premail(
      from: github_noreply,
      to: user_email(user, GitHub.newsies.email(user, organization).value),
      subject: "[GitHub] GitHub #{Copilot::COPILOT_DESKTOP} has been disabled by your organization.",
    )
  end

  sig { params(organization: Organization, is_new_signup: T::Boolean).returns(String) }
  def welcome_org_admins(organization, is_new_signup: false)
    @has_parent_business = T.let(organization.business.present?, T.nilable(T::Boolean))
    @is_new_signup = T.let(is_new_signup, T.nilable(T::Boolean))
    @organization = T.let(organization, T.nilable(Organization))
    @header = T.let("Welcome to GitHub #{Copilot::BUSINESS_PRODUCT_NAME}!", T.nilable(String))

    premail(
      from: github_noreply,
      bcc: admin_emails(organization),
      subject: "[GitHub] [#{organization.display_login}] Welcome to #{Copilot::BUSINESS_PRODUCT_NAME}!",
    )
  end

  sig { params(organization: Organization, user: User).returns(String) }
  def welcome_individual(organization, user)
    @user = T.let(user, T.nilable(User))
    @organization = T.let(organization, T.nilable(Organization))
    @header = T.let("Welcome to GitHub #{Copilot::BUSINESS_PRODUCT_NAME}!", T.nilable(String))

    premail(
      from: github_noreply,
      to: user_email(user, GitHub.newsies.email(user, organization).value),
      subject: "[GitHub] Welcome to #{Copilot::BUSINESS_PRODUCT_NAME}!",
    )
  end

  sig { returns(T.nilable(T.any(::User, ::Organization, ::Business))) }
  def mailable
    return @user if @user.present?
    return @organization if @organization.present?
    @business if @business.present?
  end
end
