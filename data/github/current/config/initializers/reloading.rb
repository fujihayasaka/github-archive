# frozen_string_literal: true

Rails.configuration.to_prepare do
  # Reload Notification service classes in dev mode
  GitHub.newsies = nil
  FeatureFlag.team_cache.clear
end
