# frozen_string_literal: true

class AutofixSuggestionJob < ApplicationRecord
  AUTOFIX_SUPPORTED_LANGUAGES = [
    Languages::JAVASCRIPT,
  ].freeze

  ALLOWED_CONCLUSIONS = [
    GitHub::CheckRun::Conclusion::SUCCESS,
    GitHub::CheckRun::Conclusion::FAILURE,
  ].freeze

  belongs_to :pull_request
  has_one :repo, through: :pull_request

  has_one :suggested_fix, inverse_of: :autofix_suggestion_job, dependent: :destroy

  validates :pull_request_id, presence: true, uniqueness: { scope: :target_sha }
  validates :target_sha, presence: true, length: { maximum: 40 }
  validate :sarif_content_is_hash?

  delegate :affected_file_paths,
           :dependency_declaration_location,
           :level,
           :message,
           to: :sarif

  def sarif_content_is_hash?
    return if sarif_content.nil?
    return if sarif_content.is_a? Hash

    errors.add(:sarif_content, "sarif_content must be saved as a Hash")
  end

  def sarif_content=(content)
    case content
    when String
      super(JSON.parse(content))
    when Hash, NilClass
      super(content)
    else
      raise ArgumentError, "#sarif_content must be a Hash or String"
    end
  end

  def sarif
    @sarif ||= Sarif.new(sarif_content)
  end

  # Set the stage and autofix_job's telemetry attributes into
  # Dependabot::Logger context for the duration of the inner block,
  # and record the outcome of running the inner block
  def observe_stage(stage:, &block)
    raise "Stage block not provided" unless block
    raise "Unexpected autofix stage" unless Stages::ALL_STAGES.include?(stage)

    Dependabot::Logger.log_context({ stage: stage, **telemetry_attributes }) do
      result = yield
      AutofixSuggestionJob::Stages.record_success(stage: stage)
      result
    rescue StandardError => e
      AutofixSuggestionJob::Stages.record_error(stage: stage, error: e)
      raise
    end
  end

  def complete_github_check_run(conclusion:)
    raise "Unexpected autofix check run conclusion" unless ALLOWED_CONCLUSIONS.include?(conclusion)
    return if check_run_id.nil?

    client = GitHubHelpers::ClientWithRetries.new(account: repo.account)
    client.update_check_run(
      repo.github_id,
      check_run_id,
      {
        status: GitHub::CheckRun::Status::COMPLETED,
        conclusion: conclusion,
        completed_at: Time.current.utc.iso8601,
      }
    )
  end

  def telemetry_attributes
    {
      "gh.dependabot_api.autofix_suggestion_job.id": id,
      "gh.dependabot_api.autofix_suggestion_job.sha": target_sha,
      "gh.dependabot_api.pull_request.id": pull_request&.id,
      "gh.repo.id": repo&.github_id,
      "gh.pull_request.number": pull_request&.github_number,
      "gh.owner.id": repo&.account&.github_id,
      "gh.check_run.id": check_run_id,
    }.compact
  end
end
