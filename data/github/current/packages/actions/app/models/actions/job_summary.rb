# typed: true
# frozen_string_literal: true

class Actions::JobSummary
  attr_reader :truncated, :step_summaries

  def initialize(truncated:, step_summaries:)
    # when the number of steps summaries is > the limit
    # https://github.com/github/actions-dotnet/blob/0eb8ef28c7a82fee6a96c488b7bcd10a3c4dbd69/Actions/Service/Server/ActionsStepSummaryService.cs#L145
    @truncated = truncated
    # Order isn't guaranteed by actions service, so we sort it here
    @step_summaries = step_summaries.sort_by { |s| s[:created_on] }
  end

  def is_truncated?
    # job has step truncation
    return true if @truncated

    # one or more steps are truncated
    @step_summaries.pluck(:truncated).reduce(:|)
  end

  # Accepts the Twirp response from actions service
  # The Protocol Buffer for this response is below:
  # https://github.com/github/actions-results/blob/main/proto/monolith/core/v1/job_summary_api.proto
  def self.from_results_hash(hash)
    step_summaries = hash.fetch("stepSummaries", []).map do |step_summary|
      created_on = step_summary["createdAt"] ? DateTime.parse(step_summary["createdAt"]) : DateTime.new(0)

      {
        content: ::Base64.decode64(step_summary["content"]),
        truncated: step_summary.fetch("isTruncated", false),
        created_on: created_on,
      }
    end

    new(
      truncated: hash.fetch("isTruncated", false),
      step_summaries: step_summaries,
    )
  end

  # Accepts the JSON hash response from actions service
  # https://github.com/github/actions-dotnet/blob/0eb8ef28c7a82fee6a96c488b7bcd10a3c4dbd69/Actions/Client/WebApi/Contracts/SignedSummary.cs
  # https://github.com/github/actions-dotnet/blob/0eb8ef28c7a82fee6a96c488b7bcd10a3c4dbd69/Actions/Client/WebApi/Contracts/StepSummary.cs
  def self.from_hash(hash)
    step_summaries = hash.fetch("stepSummaries", []).map do |step_summary|
      {
        step_record_id: step_summary["stepRecordId"],
        content: ::Base64.decode64(step_summary["contentBase64"]),
        # when the content of the step summary is > size limit
        # https://github.com/github/actions-dotnet/blob/0eb8ef28c7a82fee6a96c488b7bcd10a3c4dbd69/Actions/Service/Server/ActionsStepSummaryService.cs#L142
        truncated: step_summary["truncated"],
        created_on: step_summary["createdOn"] ? DateTime.parse(step_summary["createdOn"]) : DateTime.new(0),
      }
    end

    new(
      truncated: hash["truncated"],
      step_summaries: step_summaries
    )
  end
end
