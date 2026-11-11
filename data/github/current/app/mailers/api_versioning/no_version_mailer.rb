# typed: strict
# frozen_string_literal: true

class ApiVersioning::NoVersionMailer < ApplicationMailer
  self.mailer_name = "mailers/api_versioning_no_version"

  helper :application

  layout "layouts/primer_layout"

  sig do
    params(
      user: User,
      selected_version: String,
      latest_version: String,
      app_names: T::Array[String],
      app_count: Integer,
      token_names: T::Array[String],
      token_count: Integer,
    ).returns(T.untyped)
  end
  def for_user(user, selected_version:, latest_version:, app_names: [], app_count: app_names.size, token_names: [], token_count: token_names.size)
    set_common_vars(selected_version: selected_version, latest_version: latest_version)
    @user = T.let(user, T.nilable(User))
    @app_count = T.let(app_count, T.nilable(Integer))
    @app_names = T.let(app_names.first(5), T.nilable(T::Array[String]))
    @token_count = T.let(token_count, T.nilable(Integer))
    @token_names = T.let(token_names.first(5), T.nilable(T::Array[String]))
    @personal_github_apps_url = T.let("#{GitHub.url}/settings/apps", T.nilable(String))
    @oauth_apps_url = T.let("#{GitHub.url}/settings/developers", T.nilable(String))
    @fine_grained_tokens_url = T.let("#{GitHub.url}/settings/personal-access-tokens", T.nilable(String))
    @classic_tokens_url = T.let("#{GitHub.url}/settings/tokens", T.nilable(String))

    premail(
      to: user_email(user),
      subject: "Your API calls may be affected by breaking changes in a newer version",
    )
  end

  sig do
    params(
      org: Organization,
      selected_version: String,
      latest_version: String,
      app_names: T::Array[String],
      app_count: Integer,
    ).returns(T.untyped)
  end
  def for_org(org, selected_version:, latest_version:, app_names: [], app_count: app_names.size)
    set_common_vars(selected_version: selected_version, latest_version: latest_version)
    @org = T.let(org, T.nilable(Organization))
    @app_count = T.let(app_count, T.nilable(Integer))
    @app_names = T.let(app_names.first(5), T.nilable(T::Array[String]))
    @org_github_apps_url = T.let("#{GitHub.url}/organizations/#{org.display_login}/settings/apps", T.nilable(String))
    @org_oauth_apps_url = T.let("#{GitHub.url}/organizations/#{org.display_login}/settings/applications", T.nilable(String))

    premail(
      from: github_noreply(org),
      bcc: admin_emails(org),
      subject: "Your API calls may be affected by breaking changes in a newer version",
    )
  end

  sig do
    params(
      business: Business,
      selected_version: String,
      latest_version: String,
      app_names: T::Array[String],
      app_count: Integer,
    ).returns(T.untyped)
  end
  def for_business(business, selected_version:, latest_version:, app_names: [], app_count: app_names.size)
    set_common_vars(selected_version: selected_version, latest_version: latest_version)
    @business = T.let(business, T.nilable(Business))
    @app_count = T.let(app_count, T.nilable(Integer))
    @app_names = T.let(app_names.first(5), T.nilable(T::Array[String]))
    @enterprise_apps_url = T.let("#{GitHub.url}/enterprises/#{business.slug}/settings/apps", T.nilable(String))

    premail(
      bcc: business_emails(business),
      subject: "Your API calls may be affected by breaking changes in a newer version",
    )
  end

  private

  sig do
    params(
      selected_version: String,
      latest_version: String,
    ).void
  end
  def set_common_vars(selected_version:, latest_version:)
    @selected_version = T.let(selected_version, T.nilable(String))
    @latest_version = T.let(latest_version, T.nilable(String))
    @selected_version_retirement_date = T.let(formatted_retirement_date(selected_version), T.nilable(String))
    @changelog_url = T.let(
      "https://docs.github.com/rest/overview/api-versions#about-api-versioning",
      T.nilable(String),
    )
    @breaking_changes_url = T.let(
      "https://docs.github.com/rest/about-the-rest-api/breaking-changes",
      T.nilable(String),
    )
    @footer_links = T.let(
      [{ url: @changelog_url, text: "API versioning docs" }],
      T.nilable(T::Array[T::Hash[Symbol, T.nilable(String)]]),
    )
  end

  sig { params(selected_version: String).returns(String) }
  def formatted_retirement_date(selected_version)
    retirement_date = Api::Versioning.retirement_date(selected_version)
    raise ArgumentError, "Unable to determine retirement date for API version #{selected_version}" if retirement_date.nil?

    retirement_date.iso8601
  end
end
