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
      created_at: payload[:created_at],
      deadline: payload[:deadline],
      snapshot_type: serializer.enum(
        type: Hydro::Schemas::Github::Dependencygraph::V1::SnapshotProcessed::SnapshotType,
        value: payload[:snapshot_type],
        default: :SNAPSHOT_TYPE_UNKNOWN
      ),
    }

    publish(message, schema: "github.dependencygraph.v1.SnapshotProcessed")
  end

  subscribe("dependency_graph.pull_request_push") do |payload|
    message = {
      request_context: serializer.request_context(payload[:request_context]),
      repository: serializer.repository(payload[:repository]),
      owner: serializer.user(payload[:owner]),
      pull_request: payload[:pull_request],
      head_repository: serializer.repository(payload[:repository]),
      trigger_type: serializer.enum(
        type: Hydro::Schemas::Github::Dependencygraph::V1::PullRequestPush::TriggerType,
        value: payload[:trigger_type],
        default: :UNKNOWN
      ),
      previous_ref_oid: payload[:previous_ref_oid],
      current_ref_oid: payload[:current_ref_oid],
    }

    publish(message,
            publisher: GitHub.sync_hydro_publisher,
            partition_key: payload[:repository].id,
            schema: "github.dependencygraph.v1.PullRequestPush")
  end

  subscribe("update_manifest.repository") do |payload|
    # publisher must be selected by the caller (usually a job) that
    # can determine how many events are likely to be published
    publisher = payload.delete(:publisher) || GitHub.hydro_publisher

    manifest_file = {
      filename: payload[:manifest_file][:filename],
      path: payload[:manifest_file][:path],
      git_ref: payload[:manifest_file][:git_ref].to_s,
      pushed_at: payload[:manifest_file][:pushed_at],
      blob_oid: payload[:manifest_file][:blob_oid],
    }

    message = {
      repository_id: payload[:repository_id],
      owner_id: payload[:owner_id],
      repository_private: payload[:repository_private],
      repository_fork: payload[:repository_fork],
      repository_nwo:  payload[:repository_nwo],
      repository_stargazer_count:  payload[:repository_stargazer_count],
      manifest_file: manifest_file,
      is_backfill: payload.fetch(:is_backfill, false),
    }

    # if snapshot_metadata key is populated, then the manifest_file
    # is a package-lock.json and the associated package.json OID and
    # Git commit/ref data will be needed downstream for DS-API snapshot
    # submission
    if payload[:snapshot_metadata]
      snapshot_metadata = {
        associated_manifest: payload[:snapshot_metadata][:associated_manifest],
        push_id: payload[:snapshot_metadata][:push_id],
        ref: payload[:snapshot_metadata][:ref],
        commit_sha: payload[:snapshot_metadata][:commit_sha],
      }
      message[:snapshot_metadata] = snapshot_metadata
    end

    publish(message,
            topic: "github.dependencygraph.v1.RepositoryManifestFileChange",
            schema: "github.dependencygraph.v0.RepositoryManifestFileChange",
            partition_key: message[:repository_id],
            publisher: publisher,
            topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("delete_manifest.repository") do |payload|
    # publisher must be selected by the caller (usually a job) that
    # can determine how many events are likely to be published
    publisher = payload.delete(:publisher) || GitHub.hydro_publisher

    manifest_file = {
      filename: payload[:manifest_file][:filename],
      path: payload[:manifest_file][:path],
      git_ref: payload[:manifest_file][:git_ref].to_s,
      pushed_at: payload[:manifest_file][:pushed_at],
    }

    message = {
      repository_id: payload[:repository_id],
      repository_private: payload[:repository_private],
      repository_fork: payload[:repository_fork],
      manifest_file: manifest_file,
      repository_nwo: payload[:repository_nwo],
      owner_id: payload[:owner_id],
    }

    # if snapshot_metadata key is populated, then the manifest_file
    # is a package-lock.json and the associated package.json and
    # Git commit/ref data will be needed by the DS-API snapshot
    # submission PoC
    if payload[:snapshot_metadata]
      snapshot_metadata = {
        push_id: payload[:snapshot_metadata][:push_id],
        ref: payload[:snapshot_metadata][:ref],
        commit_sha: payload[:snapshot_metadata][:commit_sha],
      }
      message[:snapshot_metadata] = snapshot_metadata
    end

    Hydro::PublishRetrier.publish(message,
                                  schema: "github.dependencygraph.v0.RepositoryManifestFileDeleted",
                                  publisher: publisher,
                                  topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end
end
