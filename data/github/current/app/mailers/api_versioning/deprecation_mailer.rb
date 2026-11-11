# typed: strict
# frozen_string_literal: true

class ApiVersioning::DeprecationMailer < ApplicationMailer
  self.mailer_name = "mailers/api_versioning_deprecation"

  helper :application

  layout "layouts/primer_layout"

  sig do
    params(
      user: User,
      deprecation_version: String,
      deprecation_date: String,
      latest_version: String,
      subject_prefix: String,
    ).returns(T.untyped)
  end
  def for_user(user, deprecation_version:, deprecation_date:, latest_version:, subject_prefix: "Action required")
    set_common_vars(deprecation_version: deprecation_version, deprecation_date: deprecation_date, latest_version: latest_version)
    @user = T.let(user, T.nilable(User))

    premail(
      to: user_email(user),
      subject: "#{subject_prefix}: API version #{deprecation_version} will be retired on #{deprecation_date}",
    )
  end

  private

  sig do
    params(
      deprecation_version: String,
      deprecation_date: String,
      latest_version: String,
    ).void
  end
  def set_common_vars(deprecation_version:, deprecation_date:, latest_version:)
    @deprecation_version = T.let(deprecation_version, T.nilable(String))
    @deprecation_date = T.let(deprecation_date, T.nilable(String))
    @latest_version = T.let(latest_version, T.nilable(String))
    @changelog_url = T.let("https://docs.github.com/rest/overview/api-versions#about-api-versioning", T.nilable(String))
    @footer_links = T.let([
      { url: @changelog_url, text: "API versioning docs" },
    ], T.nilable(T::Array[T::Hash[Symbol, T.nilable(String)]]))
  end
end
