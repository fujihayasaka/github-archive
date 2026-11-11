# frozen_string_literal: true

Rails.application.reloader.to_prepare do
  Rails.application.config.active_job.custom_serializers += [
    HydroHandlers::DependencyGraph::GraphChangesSerializer,
    HydroHandlers::GitHub::DependencyUpdateSerializer,
    HydroHandlers::GitHub::RepositorySerializer,
    HydroHandlers::GitHub::SecurityVulnerabilitySerializer,
    HydroHandlers::GitHub::UserSerializer,
  ]
end
