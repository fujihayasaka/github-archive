# typed: true
# frozen_string_literal: true

module DependencyGraphPlatform
  autoload :AlertableDependent, "dependency_graph_platform/alertable_dependent"
  autoload :AlertableDependency, "dependency_graph_platform/alertable_dependency"
  autoload :AlertableManifest, "dependency_graph_platform/alertable_manifest"
  autoload :AllRepositoriesWithVersionRangeQuery, "dependency_graph_platform/all_repositories_with_version_range_query"
  autoload :FetchVulnerableDependenciesForRepositoryQuery, "dependency_graph_platform/fetch_vulnerable_dependencies_for_repository_query"
  autoload :Twirp, "dependency_graph_platform/twirp"

  # Helper to publish a manifest reset event.
  #   trigger - :RESET_TRIGGER_STAFFTOOLS or :RESET_TRIGGER_CHATOPS
  #   action   - :RESET_ACTION_REDETECT to reparse the repositories manifests, :RESET_ACTION_CLEAR to remove all manifest data.
  #
  # Note: this method uses GitHub.aqueduct_fallback_hydro_publisher to trade latency for increased reliability.
  def self.publish_manifest_reset_event(repository:, actor:, trigger:, action:)
    payload = {
      request_context: Hydro::EntitySerializer.request_context(GitHub.context),
      actor: Hydro::EntitySerializer.user(actor),
      repository: Hydro::EntitySerializer.repository(repository),
      owner: Hydro::EntitySerializer.user(repository.owner),
      trigger: Hydro::EntitySerializer.enum(
        type: Hydro::Schemas::Github::Dependencygraph::V1::ResetManifests::ResetTrigger,
        value: trigger,
        default: :RESET_TRIGGER_UNKNOWN
      ),
      action: Hydro::EntitySerializer.enum(
        type: Hydro::Schemas::Github::Dependencygraph::V1::ResetManifests::ResetAction,
        value: action,
        default: :RESET_ACTION_UNKNOWN
      ),
    }

    GitHub.aqueduct_fallback_hydro_publisher.publish(
      payload,
      schema: "github.dependencygraph.v1.ResetManifests",
      partition_key: repository.id,
    )
  end

  # Helper to publish a manifest reset event for orphaned repos.
  #   trigger - :RESET_TRIGGER_STAFFTOOLS or :RESET_TRIGGER_CHATOPS
  #   action   - :RESET_ACTION_REDETECT to reparse the repositories manifests, :RESET_ACTION_CLEAR to remove all manifest data.
  #
  # Note: this method uses GitHub.aqueduct_fallback_hydro_publisher to trade latency for increased reliability.
  def self.publish_orphaned_manifest_reset_event(repository_id:, actor:, trigger:, action:)
    payload = {
      request_context: Hydro::EntitySerializer.request_context(GitHub.context),
      actor: Hydro::EntitySerializer.user(actor),
      repository: Hydro::EntitySerializer.null_repository(repository_id),
      trigger: Hydro::EntitySerializer.enum(
        type: Hydro::Schemas::Github::Dependencygraph::V1::ResetManifests::ResetTrigger,
        value: trigger,
        default: :RESET_TRIGGER_UNKNOWN
      ),
      action: Hydro::EntitySerializer.enum(
        type: Hydro::Schemas::Github::Dependencygraph::V1::ResetManifests::ResetAction,
        value: action,
        default: :RESET_ACTION_UNKNOWN
      ),
    }

    GitHub.aqueduct_fallback_hydro_publisher.publish(
      payload,
      schema: "github.dependencygraph.v1.ResetManifests",
      partition_key: repository_id,
    )
  end

  # Helper to publish a manifest enroll event.
  #
  # Note: this method uses GitHub.aqueduct_fallback_hydro_publisher to trade latency for increased reliability.
  def self.publish_manifest_enroll_event(repository:, actor:)
    payload = {
      request_context: Hydro::EntitySerializer.request_context(GitHub.context),
      actor: Hydro::EntitySerializer.user(actor),
      repository: Hydro::EntitySerializer.repository(repository),
      owner: Hydro::EntitySerializer.user(repository.owner),
    }

    GitHub.aqueduct_fallback_hydro_publisher.publish(
      payload,
      schema: "github.dependencygraph.v1.EnrollManifests",
      partition_key: repository.id,
    )
  end
end
