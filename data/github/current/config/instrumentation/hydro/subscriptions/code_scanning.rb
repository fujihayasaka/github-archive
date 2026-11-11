# typed: true
# frozen_string_literal: true

# These are Hydro event subscriptions related to Code Scanning.

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("code_scanning.new_analysis") do |payload|
    repo_id = payload[:repository_id]
    payload.freeze
    GitHub.sync_hydro_publisher.publish(payload, schema: "code_scanning.v0.Analysis", topic: "code_scanning.v0.NewAnalysis", partition_key: repo_id)
  end

  subscribe("code_scanning.codeql_database_upload") do |payload|
    partition_key = payload[:repository].id
    message = {
      repository: serializer.repository(payload[:repository]),
      actor: serializer.user(payload[:actor]),
      uploaded_at: payload[:uploaded_at],
      language: payload[:language],
      size: payload[:size],
      oid: payload[:oid]
    }
    publish(message,
      schema: "code_scanning.v0.CodeqlDatabaseUpload",
      topic: "code_scanning.v0.CodeqlDatabaseUpload",
      partition_key: partition_key)
  end

  subscribe("code_scanning.codeql_database_download") do |payload|
    partition_key = payload[:repository].id
    message = {
      repository: serializer.repository(payload[:repository]),
      actor: serializer.user(payload[:actor]),
      downloaded_at: payload[:downloaded_at],
      language: payload[:language],
      size: payload[:size],
      oid: payload[:oid]
    }
    publish(message,
      schema: "code_scanning.v0.CodeqlDatabaseDownload",
      topic: "code_scanning.v0.CodeqlDatabaseDownload",
      partition_key: partition_key)
  end

  subscribe("code_scanning.remote_query_run") do |payload|
    partition_key = payload[:controller_repository].id
    message = {
      controller_repository: serializer.repository(payload[:controller_repository]),
      actor: serializer.user(payload[:actor]),
      created_at: payload[:created_at],
      language: payload[:language],
      repositories_count: payload[:repositories_count],
    }
    publish(message,
      schema: "code_scanning.v0.RemoteQueryRun",
      topic: "code_scanning.v0.RemoteQueryRun",
      partition_key: partition_key)
  end

  subscribe("code_scanning.codeql_bulk_builder_status") do |payload|
    partition_key = payload[:repository_id]
    publish(payload,
      schema: "code_scanning.v0.CodeqlBulkBuilderStatus",
      topic: "code_scanning.v0.CodeqlBulkBuilderStatus",
      partition_key: partition_key)
  end

  subscribe("code_scanning.tool_status") do |payload|
    partition_key = payload[:repository_id]
    delivery_origin_status = payload[:delivery_origin_status].transform_values do |status|
      tool_status_to_symbol(status)
    end
    message = {
      status_trigger: payload[:status_trigger],
      repository_id: payload[:repository_id],
      ref: payload[:ref],
      tool_name: payload[:tool_name],
      status: tool_status_to_symbol(payload[:status]),
      messages: serialise_tool_status_messages(payload[:messages]),
      total_extracted: payload[:total_extracted].to_h,
      languages_extracted: payload[:languages_extracted].to_h,
      delivery_origins: payload[:delivery_origins],
      delivery_origin_status: delivery_origin_status,
    }
    publish(message,
      schema: "hydro.schemas.code_scanning.v0.ToolStatus",
      topic: "code_scanning.v0.ToolStatus",
      partition_key: partition_key)
  end

  subscribe("code_scanning.enable") do |payload|
    message = {
      repository_id: payload[:repository_id],
      feature_enabled: true
    }

    publish(
      message,
      schema: "code_scanning.v0.CodeScanningFeatureToggled",
      topic: "github.code_scanning.v0.CodeScanningFeatureToggled",
      partition_key: payload[:repository_id],
      topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 },
    )
  end

  subscribe("code_scanning.disable") do |payload|
    message = {
      repository_id: payload[:repository_id],
      feature_enabled: false
    }

    publish(
      message,
      schema: "code_scanning.v0.CodeScanningFeatureToggled",
      topic: "github.code_scanning.v0.CodeScanningFeatureToggled",
      partition_key: payload[:repository_id],
      topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 },
    )
  end

  subscribe("browser.code_scanning_autofix.patch_copied") do |payload|
    next unless payload[:type] == "code_scanning"

    message =
      payload.slice(:repository_id, :alert_number, :pull_request_id, :pull_request_number)
      .merge(event_type: :AUTOFIX_EVENT_TYPE_PATCH_COPIED)

    publish(
      message,
      schema: "code_scanning.v0.AutofixEvent",
      topic: "code_scanning.v0.AutofixEvent",
      partition_key: payload[:repository_id],
    )
  end

  subscribe("browser.code_scanning_autofix.diff_lines_copied") do |payload|
    next unless payload[:type] == "code_scanning"

    message =
      payload.slice(:repository_id, :alert_number, :pull_request_id, :pull_request_number)
      .merge(event_type: :AUTOFIX_EVENT_TYPE_DIFF_LINES_COPIED)

    publish(
      message,
      schema: "code_scanning.v0.AutofixEvent",
      topic: "code_scanning.v0.AutofixEvent",
      partition_key: payload[:repository_id],
    )
  end

  subscribe("code_scanning.autofix_event") do |payload|
    publish(
      payload,
      schema: "code_scanning.v0.AutofixEvent",
      topic: "code_scanning.v0.AutofixEvent",
      partition_key: payload[:repository_id],
    )
  end

  subscribe("code_scanning.autofix_remediation_intent_event") do |payload|
    publish(
      payload,
      schema: "code_scanning.v0.AutofixRemediationIntentEvent",
      topic: "code_scanning.v0.AutofixRemediationIntentEvent",
      partition_key: payload[:repository_id],
    )
  end

  subscribe("code_scanning.autofix_feedback") do |payload|
    publish(
      payload,
      schema: "code_scanning.v0.AutofixFeedback",
      topic: "code_scanning.v0.AutofixFeedback",
      partition_key: payload[:repository_id],
    )
  end

  def tool_status_to_symbol(status)
    case status
    when CodeScanning::Status::SUCCESS
      :SUCCESS
    when CodeScanning::Status::ATTENTION
      :ATTENTION
    when CodeScanning::Status::DANGER
      :DANGER
    else
      :UNKNOWN
    end
  end

  # messages are CodeScanning::Status::Error
  def serialise_tool_status_messages(messages)
    messages.map do |message|
      {
        title: message.title,
        # message.message is an ActiveSupport::SafeBuffer. This can't
        # be serialised and overrides to_s to return itself so we need
        # to use to_str instead
        message: message.message.to_str.dup.force_encoding("utf-8").scrub!,
        level: tool_status_to_symbol(message.level),
        analysis_id: message.analysis_id
      }
    end
  end

  subscribe("code_scanning.pull_request_review_comment_reply") do |payload|
    publish(
      GitHub::StreamProcessors::EnvelopeGenerator.new.transform_message_value(payload),
      schema: "github.v1.PullRequestReviewCommentCreate", # we re-use this schema
      topic: "code_scanning.v0.CodeScanningReviewCommentReply",
      partition_key: payload[:repository][:id],
    )
  end

  subscribe("code_scanning.pull_request_review_comment_resolve") do |payload|
    publish(
      GitHub::StreamProcessors::EnvelopeGenerator.new.transform_message_value(payload),
      schema: "github.pull_requests.v1.PullRequestReviewThreadResolveOrUnresolve", # we re-use this schema
      topic: "code_scanning.v0.CodeScanningReviewResolve",
      partition_key: payload[:repository][:id],
    )
  end

  subscribe("code_scanning.pull_request_review_comment_unresolve") do |payload|
    publish(
      GitHub::StreamProcessors::EnvelopeGenerator.new.transform_message_value(payload),
      schema: "github.pull_requests.v1.PullRequestReviewThreadResolveOrUnresolve", # we re-use this schema
      topic: "code_scanning.v0.CodeScanningReviewUnresolve",
      partition_key: payload[:repository][:id],
    )
  end

  subscribe("code_scanning.repository_metrics") do |payload|
    message = {
      repository_id: payload[:repository_id],
      organization_id: payload[:organization_id],
      ghas_enabled: payload[:ghas_enabled],
      code_scanning_enabled: payload[:code_scanning_enabled],
      private_repository: payload[:private_repository],
      metric_created_at: payload[:metric_created_at],
    }
    publish(message, schema: "code_scanning.v0.RepositoryMetrics")
  end

  subscribe("code_scanning.alerts_assignment") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      repository: serializer.repository(payload[:repository]),
      assignees: serializer.users(payload[:assignees]),
      code_scanning_alerts: payload[:code_scanning_alerts],
    }
    publish(
      message,
      schema: "code_scanning.v0.AlertsAssignment",
      topic: "code_scanning.v0.AlertsAssignment",
      partition_key: payload[:repository][:id],
    )
  end
end
