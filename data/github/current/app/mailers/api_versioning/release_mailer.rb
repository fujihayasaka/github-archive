# typed: strict
# frozen_string_literal: true

# Sends release-day notifications about new GitHub REST API calendar
# versions. Dispatched by `ApiVersioning::UserReleaseNotificationJob`
# on the day a new version ships.
#
# Sibling of `ApiVersioning::DeprecationMailer` — the two classes do not
# share an inheritance chain, but they share the primer mailer layout
# and the API-versioning docs link in the footer.
class ApiVersioning::ReleaseMailer < ApplicationMailer
  self.mailer_name = "mailers/api_versioning_release"

  helper :application

  layout "layouts/primer_layout"

  # Release-day notification to a single user, sent by
  # `ApiVersioning::UserReleaseNotificationJob`. Renders out of
  # `app/views/mailers/api_versioning_release/for_user.{html,text}.erb`.
  #
  # @param user [User]
  # @param latest_version [String] the freshly released calendar version
  # @param deprecating_versions [Hash{String => String}] still-pending
  #   deprecations as version => ISO 8601 retirement date, excluding
  #   `latest_version`.
  sig do
    params(
      user: User,
      latest_version: String,
      deprecating_versions: T::Hash[String, String],
    ).returns(T.untyped)
  end
  def for_user(user, latest_version:, deprecating_versions: {})
    set_common_vars(latest_version: latest_version, deprecating_versions: deprecating_versions)
    @user = T.let(user, T.nilable(User))

    premail(
      to: user_email(user),
      subject: "A new GitHub REST API version is available: #{latest_version}",
    )
  end

  private

  sig do
    params(
      latest_version: String,
      deprecating_versions: T::Hash[String, String],
    ).void
  end
  def set_common_vars(latest_version:, deprecating_versions:)
    @latest_version = T.let(latest_version, T.nilable(String))
    @deprecating_versions = T.let(deprecating_versions, T.nilable(T::Hash[String, String]))
    @changelog_url = T.let("https://docs.github.com/rest/overview/api-versions#about-api-versioning", T.nilable(String))
    @footer_links = T.let([
      { url: @changelog_url, text: "API versioning docs" },
    ], T.nilable(T::Array[T::Hash[Symbol, T.nilable(String)]]))
  end
end
