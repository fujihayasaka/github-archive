# typed: true
# frozen_string_literal: true

# These are Hydro event subscriptions for Dependency Graph.

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do

  subscribe("dependency_graph.request_snapshot") do |payload|
    message = {
      push_id: payload[:push_id],
      before_sha: payload[:before_sha],
      sha: payload[:sha],
      ref: payload[:ref],
      pushed_at: payload[:pushed_at],
      repository: serializer.repository(payload[:repository]),
      owner_name: payload[:owner_name],
      manifest_files: payload[:manifest_files],
    }

    publish(message, schema: "github.dependencygraph.v0.RequestPushSnapshot", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("dependency_graph.rich_diff.view") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      repo: serializer.repository(payload[:repo]),
      pull_request: serializer.pull_request(payload[:pull_request]),
      path: payload[:path],
      filename: payload[:filename],
      vulnerability_display_count: payload[:vulnerability_display_count],
    }

    publish(message, schema: "github.dependencygraph.v0.DependencyReviewRichDiffView", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("dependency_graph.auto_dependencies_submit") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      repository: payload[:repositories].map { |r| serializer.repository(r) },
      enrollment_status: serializer.enum(
        type: Hydro::Schemas::Github::Dependencygraph::V0::RepositoryAutoDepsEnroll::EnrollmentStatus,
        value: payload[:enrollment_status],
        default: :UNKNOWN
      ),
      runner_type: serializer.enum(
        type: Hydro::Schemas::Github::Dependencygraph::V0::RepositoryAutoDepsEnroll::RunnerType,
        value: payload[:runner_type],
        default: :CLOUD
      ),
      modified_at: Time.zone.now
    }

    publish(message, publisher: GitHub.sync_hydro_publisher, schema: "github.dependencygraph.v0.RepositoryAutoDepsEnroll")
  end

  subscribe("dependency_graph.repository_push") do |payload|
    enriched_ref_updates = payload[:updates].map do |update|
      {
        ref_name: update.ref.dup.force_encoding(Encoding::UTF_8),
        previous_ref_oid: update.before,
        current_ref_oid: update.after,
        # Push model data will not be captured with parent ref updates.
        # Ideally, Dependabot will be able to use ref update coords to
        # lookup Push models downstream if we relay them in notifications.
        # values set below are sentinel placeholders for now.
        push_id: 0,
        pushed_at: payload[:pushed_at],
      }
    end

    message = {
      request_context: serializer.request_context(payload[:request_context]),
      repository: serializer.repository(payload[:repository]),
      actor: serializer.user(payload[:actor]),
      owner: serializer.user(payload[:owner]),
      ref_updates: Array.wrap(enriched_ref_updates),
    }

    publish(message,
            publisher: GitHub.sync_hydro_publisher,
            partition_key: payload[:repository].id,
            schema: "github.dependencygraph.v1.RepositoryPush")
  end

  subscribe("dependency_graph.snapshot_processed") do |payload|
    message = {
      repository_id: payload[:repository_id],
      snapshot_id: payload[:snapshot_id],
      ref: payload[:ref],
      sha: payload[:sha],
      detector_name: payload[:detector_name],
      correlator: payload[:correlator],
      scanned_at: payload[:scanned_at],
      created_at: payload[:created_at]
    }

    publish(message, schema: "github.dependencygraph.v1.SnapshotProcessed")
  end
end
