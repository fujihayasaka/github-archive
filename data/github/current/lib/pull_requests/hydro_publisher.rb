# typed: strict
# frozen_string_literal: true

class PullRequestHydroPublisher
  sig do
    params(
      pull_request_id: T.nilable(Integer),
      repository_id: T.nilable(Integer),
      change: Symbol,
      index_name: T.nilable(String),
      cluster_name: T.nilable(String),
      routing_value: T.nilable(String),
      caller_location: T.nilable(String),
      es_result: T.nilable(String),
      es_version: T.nilable(Integer)
    ).void
  end
  def self.publish_changed(
    pull_request_id:,
    repository_id:,
    change:,
    index_name: nil,
    cluster_name: nil,
    routing_value: nil,
    caller_location: nil,
    es_result: nil,
    es_version: nil
  )
    change_enum = map_change_to_enum(change)

    # Feature flag to control hydro publishing for PR index deletions
    return unless FeatureFlag.vexi.enabled?(:publish_pr_es_deletion_to_hydro, default: false)

    message = {
      pull_request_id: pull_request_id,
      repository_id: repository_id,
      change: change_enum,
      occurred_at: Time.now.utc,
    }

    message[:index_name] = index_name if index_name
    message[:cluster_name] = cluster_name if cluster_name
    message[:routing_value] = routing_value if routing_value

    # Add search metadata if any metadata fields are present
    if caller_location || es_result || es_version
      metadata = {}
      metadata[:caller_location] = caller_location if caller_location
      metadata[:es_result] = es_result if es_result
      metadata[:es_version] = es_version if es_version
      message[:search_metadata] = metadata
    end

    publisher = GitHub.aqueduct_fallback_hydro_publisher
    start_time = GitHub::Dogstats.monotonic_time

    result = publisher.publish(
      message,
      schema: "hydro.schemas.github.search.v0.PullRequestChanged"
    )

    elapsed = GitHub::Dogstats.duration(start_time)
    GitHub.dogstats.distribution("pull_requests.publish_change.publish_attempt", elapsed, tags: ["success:#{result}", "change:#{change}", "index:#{index_name || 'unknown'}"])

    if !result
      GitHub.logger.warn("Failed to publish pull request index change to Hydro", {
        pull_request_id: pull_request_id,
        repository_id: repository_id,
        change: change,
      })
    end
  end

  sig { params(change: Symbol).returns(Symbol) }
  private_class_method def self.map_change_to_enum(change)
    case change
    when :created
      :CREATED
    when :updated
      :UPDATED
    when :deleted
      :DELETED
    else
      :UNKNOWN
    end
  end
end
