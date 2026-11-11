# typed: strict
# frozen_string_literal: true

module CodeQuality
  # When Copilot Code Review completes generating a review for a pull request,
  # it publishes a CopilotCodeReviewGenerated message. We use this to record
  # the copilot analysis in CodeQualityPullRequestAnalyses.
  class CopilotPullRequestAnalysisProcessor < GitHub::StreamProcessors::SingleMessageProcessor
    include GitHub::StreamProcessors::TransientErrorResiliency
    include GitHub::Memoizer

    DEFAULT_GROUP_ID = "code_quality_copilot_pull_request_analysis"
    DEFAULT_SUBSCRIBE_TO = T.let([
      /copilot_code_review_agent\.v0\.CopilotCodeReviewGenerated\Z/,
    ].freeze, T::Array[Regexp])

    options[:min_bytes] = 5.kilobytes
    options[:max_wait_time] = 0.2.seconds
    options[:max_bytes_per_partition] = 100.kilobytes
    options[:session_timeout] = 60.seconds
    options[:start_from_beginning] = false

    resolve_tenant_context do |message|
      pull_request_id = message.value.dig(:metadata, :pull_request_id)
      PullRequest.find_by(id: pull_request_id)&.repository&.owner&.business
    end

    sig { params(group_id: T.nilable(String), subscribe_to: T.nilable(T::Array[Regexp])).void }
    def setup(group_id: nil, subscribe_to: nil)
      options[:group_id] ||= DEFAULT_GROUP_ID
      options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
      self.transient_error_max_retries = 20
    end

    sig { override.params(message: GitHub::StreamProcessors::Message).returns(T.anything) }
    def process_message(message)
      payload = message.value
      pull_request_id = payload.dig(:metadata, :pull_request_id)
      reviewed_commit_sha = payload.dig(:metadata, :reviewed_commit_sha)
      success = payload.dig(:status, :success)

      logging_context.merge!(
        "gh.pull_request.id" => pull_request_id,
        "git.commit.oid" => reviewed_commit_sha,
      )

      pull_request = PullRequest.find_by(id: pull_request_id)
      if pull_request.nil?
        log_info("Pull request not found, skipping")
        return message.skip("Pull request not found, skipping")
      end

      repository = pull_request.repository
      if repository.nil? || !repository.active?
        log_info("Repository not found or inactive, skipping")
        return message.skip("Repository not found or inactive, skipping")
      end

      if !FeatureFlag.vexi.enabled?(:code_quality_evaluate_ccr_comments, repository, repository.owner, default: false)
        return message.skip("Feature flag not enabled, skipping")
      end

      logging_context.merge!(
        "gh.repo.id" => repository.id,
      )

      log_info("Received CopilotCodeReviewGenerated message")

      unless success
        log_info("Review generation was not successful, skipping")
        return message.skip("Review generation was not successful, skipping")
      end

      # Validate that reviewed_commit_sha is present and looks like a commit SHA
      if reviewed_commit_sha.nil? || reviewed_commit_sha.strip.empty?
        log_info("Reviewed commit SHA missing, skipping")
        return message.skip("Reviewed commit SHA missing or invalid, skipping")
      end

      with_primaries ApplicationRecord::Notify do
        CodeQualityPullRequestAnalyses.record(
          repository:,
          pull_request:,
          commit_oid: reviewed_commit_sha,
          analysis_configuration: CodeQualityPullRequestAnalyses::COPILOT_ANALYSIS_CONFIGURATION,
        )
      end

      log_info("Recorded copilot pull request analysis")
    end

    private

    sig { params(message: String, context: T::Hash[String, T.untyped]).void }
    def log_info(message, context = {})
      GitHub.logger.info(message, logging_context.merge(context).merge(
        "code.function" => caller_locations(1, 1)&.first&.base_label || "unknown_function",
      ))
    end

    sig { returns(T::Hash[String, T.untyped]) }
    memoize def logging_context
      {
        "code.namespace" => "CodeQuality::CopilotPullRequestAnalysisProcessor"
      }
    end
  end
end
