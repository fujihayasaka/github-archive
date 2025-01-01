# typed: true
# frozen_string_literal: true

# These are Hydro event subscriptions related to Code quality.

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("code_quality.pr_finding_autofix_event") do |payload|
    publish(
      payload,
      schema: "code_quality.v0.PrFindingAutofixEvent",
      topic: "code_quality.v0.PrFindingAutofixEvent",
      partition_key: payload[:repository_id],
    )
  end

  subscribe("browser.code_scanning_autofix.patch_copied") do |payload|
    return unless payload[:type] == "code_quality"

    message =
      payload.slice(:repository_id, :pull_request_id, :pull_request_number, :review_comment_id, :finding_stable_id)
      .merge(event_type: :AUTOFIX_EVENT_TYPE_PATCH_COPIED)

    publish(
      message,
      schema: "code_quality.v0.PrFindingAutofixEvent",
      topic: "code_quality.v0.PrFindingAutofixEvent",
      partition_key: payload[:repository_id],
    )
  end

  subscribe("browser.code_scanning_autofix.diff_lines_copied") do |payload|
    return unless payload[:type] == "code_quality"

    message =
      payload.slice(:repository_id, :pull_request_id, :pull_request_number, :review_comment_id, :finding_stable_id)
      .merge(event_type: :AUTOFIX_EVENT_TYPE_DIFF_LINES_COPIED)

    publish(
      message,
      schema: "code_quality.v0.PrFindingAutofixEvent",
      topic: "code_quality.v0.PrFindingAutofixEvent",
      partition_key: payload[:repository_id],
    )
  end

  subscribe("code_quality.autofix_feedback") do |payload|
    publish(
      payload,
      schema: "code_quality.v0.AutofixFeedback",
      topic: "code_quality.v0.AutofixFeedback",
      partition_key: payload[:repository_id],
    )
  end

  subscribe("code_quality.pull_request_finding") do |payload|
    publish(
      payload,
      schema: "code_quality.v0.PullRequestFinding",
      topic: "code_quality.v0.PullRequestFinding",
      partition_key: payload[:repository_id],
    )
  end

  subscribe("code_quality.toggled") do |payload|
    publish(
      payload,
      schema: "github.code_quality.v1.CodeQualityFeatureToggled",
      topic: "github.code_quality.v1.CodeQualityFeatureToggled",
      partition_key: payload[:repository_id],
    )
  end
end
