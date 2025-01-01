# typed: strict
# frozen_string_literal: true

module ProjectsClassicSunset
  extend T::Helpers

  SUNSET_REST_API_FLAG = :projects_classic_rest_api_deprecation
  SUNSET_GRAPHQL_API_FLAG = :projects_classic_graphql_deprecation
  SUNSET_WEBHOOKS_FLAG = :projects_classic_webhooks_deprecation

  # This is a support/staff-only flag to allow overriding the Projects (classic) sunset in the rare situation we need
  # to still allow it to be accessible.
  SUNSET_OVERRIDE_FLAG = :projects_classic_sunset_override

  # When the REST API was "announced" as deprecated
  REST_API_DEPRECATION_DATE = T.let(Time.utc(2024, 5, 23).freeze, Time)

  # When the REST API will be sunset
  REST_API_SUNSET_DATE = T.let(Time.utc(2025, 4, 1).freeze, Time)

  # Where to go to learn more about the Projects (classic) REST API sunset
  REST_API_DEPRECATION_INFO_URL = T.let("https://github.blog/changelog/2024-05-23-sunset-notice-projects-classic/".freeze, String)

  # Message to display when the REST API has actually been sunset
  REST_API_SUNSET_MESSAGE = T.let("Projects (classic) has been deprecated in favor of the new Projects experience.".freeze, String)

  # URL to link to when the REST API is sunset
  REST_API_SUNSET_DOCUMENTATION_URL = T.let("https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project/using-the-api-to-manage-projects".freeze, String)

  sig { params(entity: T.nilable(User)).returns(T::Boolean) }
  def self.rest_api_enabled?(entity)
    return false if GitHub.enterprise?

    return true if entity&.feature_enabled?(SUNSET_OVERRIDE_FLAG)
    return false if entity&.feature_enabled?(SUNSET_REST_API_FLAG)

    true
  end

  sig { params(entity: T.nilable(User)).returns(T::Boolean) }
  def self.graphql_api_enabled?(entity)
    return false if GitHub.enterprise?

    return true if entity&.feature_enabled?(SUNSET_OVERRIDE_FLAG)
    return false if entity&.feature_enabled?(SUNSET_GRAPHQL_API_FLAG)

    true
  end

  sig { returns(T::Boolean) }
  def self.webhooks_enabled?
    return false if GitHub.enterprise?
    return false if GitHub.flipper[SUNSET_WEBHOOKS_FLAG].enabled?
    true
  end
end
