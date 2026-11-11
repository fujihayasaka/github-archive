# typed: true
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("check_suite.status_changed") do |payload|
    message = {
      check_suite_id: payload[:check_suite_id],
      previous_status: payload[:previous_status],
      current_status: payload[:current_status],
      repository_id: payload[:repository_id],
      head_sha: payload[:head_sha],
      conclusion: payload[:conclusion],
      app: serializer.integration(payload[:app]),
      pull_request_ids: payload[:pull_request_ids],
      repository_owner_id: payload[:repository_owner_id],
      repository_name: payload[:repository_name],
      repository_owner_login: payload[:repository_owner_login],
    }

    publish(message, schema: "github.v1.CheckSuiteStatusChange", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("check_run.status_changed") do |payload|
    message = {
      check_run_id: payload[:check_run_id],
      previous_status: payload[:previous_status],
      current_status: payload[:current_status],
      previous_conclusion: payload[:previous_conclusion],
      current_conclusion: payload[:current_conclusion],
    }

    publish(message, schema: "github.v1.CheckRunStatusChange", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.show_annotation.click") do |payload|
    pr = PullRequest.find_by(id: payload[:pull_request_id])
    repo = if FeatureFlag.vexi.enabled?(:repos_by_id_config, default: false)
      Repositories.domain.by_id(payload[:repository_id])
    else
      Repository.find_by(id: payload[:repository_id])
    end

    message = {
      request_context: serializer.request_context(GitHub.context.to_hash,
        overrides: browser_request_context_overrides(payload)),
      pull_request: serializer.pull_request(pr),
      repository: serializer.repository(repo),
      actor: serializer.user(payload[:client][:user]),
      non_diff_entry: payload[:non_diff_entry],
    }

    publish(message, schema: "github.v1.ShowAnnotationClick", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end
end
