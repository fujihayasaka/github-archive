# frozen_string_literal: true

module PrioritizedJobs
  module CreatePullRequestOnGitHub
    class Default < ApplicationJob
      class ErrorWithReason < StandardError
        attr_reader :reason, :error_type, :error_details

        def initialize(message, reason:, error_type:, error_details: nil)
          super(message)
          @reason = reason
          @error_type = error_type
          @error_details = error_details
        end
      end

      class HaltJobError < ErrorWithReason
        DEFAULT_ERROR_TYPE = "pull_request_creation_halted"
        def initialize(message, reason:, error_type: DEFAULT_ERROR_TYPE, error_details: nil)
          super
        end
      end

      class FailJobError < ErrorWithReason
        DEFAULT_ERROR_TYPE = "pull_request_creation_failure"
        def initialize(message, reason:, error_type: DEFAULT_ERROR_TYPE, error_details: nil)
          super
        end
      end

      class RetryJobError < ErrorWithReason
        def initialize(message, reason: nil, error_type: FailJobError::DEFAULT_ERROR_TYPE, error_details: nil)
          super
        end
      end

      class SynchronizeRepoStateError < FailJobError; end

      module ErrorHandling # rubocop:disable Metrics/ModuleLength
        include GitHub::Twirp::DependabotPullRequests::Helpers
        extend GitHub::Twirp::DependabotPullRequests::Helpers

        EXPECTED_TWIRP_ERRORS = [
          resolve_pr_eligibility_result_symbol(EligibilityResult::RESULT_BASE_NOT_UP_TO_DATE),
          resolve_pr_eligibility_result_symbol(EligibilityResult::RESULT_EXISTING_BRANCH_HAS_MULTIPLE_COMMITS),
          resolve_pr_eligibility_result_symbol(EligibilityResult::RESULT_UNMERGED_PR_EXISTS),
          resolve_pr_eligibility_result_symbol(EligibilityResult::RESULT_USER_EDITED_BRANCH_EXISTS),
          resolve_api_error_symbol(APIErrorType::ERROR_TYPE_DEPENDABOT_CANNOT_WRITE),
          resolve_api_error_symbol(APIErrorType::ERROR_TYPE_GIT),
          resolve_api_error_symbol(APIErrorType::ERROR_TYPE_PROTECTED_BRANCH_UPDATE),
          resolve_api_error_symbol(APIErrorType::ERROR_TYPE_RATE_LIMITED),
          resolve_api_error_symbol(APIErrorType::ERROR_TYPE_RECORD_INVALID),
          resolve_api_error_symbol(APIErrorType::ERROR_TYPE_REPO_ARCHIVED),
          resolve_api_error_symbol(APIErrorType::ERROR_TYPE_REPO_DISABLED),
          resolve_api_error_symbol(APIErrorType::ERROR_TYPE_REPO_EMPTY),
          resolve_api_error_symbol(APIErrorType::ERROR_TYPE_REPO_LOCKED),
          resolve_api_error_symbol(APIErrorType::ERROR_TYPE_REPO_NOT_FOUND),
          resolve_api_error_symbol(APIErrorType::ERROR_TYPE_REPO_OVER_SIZE_QUOTA),
          resolve_api_error_symbol(APIErrorType::ERROR_TYPE_REPO_RULE_VIOLATION),
        ].freeze

        EXPECTED_SHOULD_NOT_CREATE_PR_ERRORS = %w(
          edited_pull_request_exists
          open_pull_request_limit_exceeded
        ).freeze

        PRESENTABLE_ERRORS = [
          resolve_api_error_symbol(APIErrorType::ERROR_TYPE_GIT),
          resolve_api_error_symbol(APIErrorType::ERROR_TYPE_UNEXPECTED_ERROR),
          resolve_api_error_symbol(APIErrorType::ERROR_TYPE_REPO_OVER_SIZE_QUOTA),
          resolve_api_error_symbol(APIErrorType::ERROR_TYPE_REPO_RULE_VIOLATION),
          resolve_api_error_symbol(APIErrorType::ERROR_TYPE_PROTECTED_BRANCH_UPDATE),
          resolve_pr_eligibility_result_symbol(EligibilityResult::RESULT_BASE_NOT_UP_TO_DATE),
          resolve_pr_eligibility_result_symbol(EligibilityResult::RESULT_UNMERGED_PR_EXISTS),
          resolve_pr_eligibility_result_symbol(EligibilityResult::RESULT_EXISTING_BRANCH_HAS_MULTIPLE_COMMITS),
          resolve_pr_eligibility_result_symbol(EligibilityResult::RESULT_USER_EDITED_BRANCH_EXISTS),
          Octokit::UnprocessableEntity,
        ].freeze

        def handle_twirp_error(error)
          return if error.blank?

          increment_metric("create_pull_request.twirp_api_error", tags: { error: error.code })
          Dependabot::Logger.error(
            msg: error.message,
            error: error.code,
            error_message: error.details,
            error_metadata: error.meta,
          )

          error_class = if error.is_a?(GitHub::Twirp::DependabotPullRequests::TransientTwirpError)
                          RetryJobError
                        else
                          FailJobError
                        end
          raise error_class.new(error.message, reason: error.code, error_details: {
                                  http_status_code: error.http_status_code,
                                })
        end

        def handle_api_error(error)
          return if error.blank?

          increment_metric("create_pull_request.api_error",
                           tags: { error: error.type, pull_request_was_created: error.pull_request_was_created? })
          Dependabot::Logger.error(msg: error.message, error: error.type, error_message: error.details)

          message = "#{error.message}: #{error.details}"
          case error
          when GitHub::Twirp::DependabotPullRequests::RepoStateServiceError
            raise SynchronizeRepoStateError.new(message, reason: error.type)
          when GitHub::Twirp::DependabotPullRequests::TransientServiceError
            raise RetryJobError.new(message, reason: error.type)
          else
            raise FailJobError.new(message, reason: error.type)
          end
        end

        def handle_can_create_pull_request_result(result)
          result = resolve_pr_eligibility_result_number(result)
          return if result == EligibilityResult::RESULT_OK

          result_symbol = resolve_pr_eligibility_result_symbol(result)
          case result
          when EligibilityResult::RESULT_BASE_NOT_UP_TO_DATE
            raise FailJobError.new("This job's base commit is not up to date",
                                   reason: result_symbol)
          when EligibilityResult::RESULT_EXISTING_BRANCH_HAS_MULTIPLE_COMMITS
            raise FailJobError.new("Branch contains incompatible changes",
                                   reason: result_symbol)
          when EligibilityResult::RESULT_UNMERGED_PR_EXISTS
            raise FailJobError.new("PR for branch already exists",
                                   reason: result_symbol)
          when EligibilityResult::RESULT_USER_EDITED_BRANCH_EXISTS
            raise FailJobError.new("Branch contains non-Dependabot commits",
                                   reason: result_symbol)
          else
            raise StandardError.new, "Unexpected result from can_create_pull_request: #{result_symbol}"
          end
        end

        def trace_missing_pending_pr(exception)
          Dependabot::Logger.log_exception(exception, { "code.namespace": "CreatePullRequestOnGitHub" })
          MetricsClient.increment("create_pull_request.pending_pull_request_gone")
        end

        def run_failure_hooks(error)
          pending_pr.transition_to(:abandoned)

          # log to splunk and datadog
          Dependabot::Logger.log_exception(error, msg: "PR error handled, stopping job.")
          increment_metric("create_pull_request.error_handled", tags: failure_metric_tags(error:))

          error_type = error.respond_to?(:error_type) ? error.error_type : FailJobError::DEFAULT_ERROR_TYPE
          details = error_details(error:)

          unless error_already_recorded?(type: error_type, details: details)
            update_job.update_job_errors.create!(error_type: error_type, error_details: details)
          end

          # Mark RepositoryDependencyUpdate as errored in dotcom if the job has
          # already been processed
          return unless update_job.github_request?

          NotifyGitHubOfFailureJob.send_errors_for(update_job)
        end

        def error_already_recorded?(type:, details:)
          update_job.update_job_errors.any? { |e| e.error_type == type && e.error_details == details }
        end

        def failure_metric_tags(error:)
          reason = error_reason(error:)
          return {} if reason.nil?

          {
            error: reason,
            expected: error_expected?(error),
          }
        end

        def error_expected?(error)
          return false unless error.respond_to?(:reason)
          return true if EXPECTED_SHOULD_NOT_CREATE_PR_ERRORS.include?(error.reason)

          EXPECTED_TWIRP_ERRORS.include?(error.reason)
        end

        def error_details(error:)
          return error.error_details if error.try(:error_details).present?
          return { message: error.message } if error_is_presentable?(error:)

          nil
        end

        def error_reason(error:)
          return error.reason if error.is_a?(ErrorWithReason)

          error.class.name.underscore
        end

        def error_is_presentable?(error:)
          return true if PRESENTABLE_ERRORS.include?(error)
          return false unless error.is_a?(ErrorWithReason)

          PRESENTABLE_ERRORS.include?(error.reason)
        end

        def synchronize_repo_state(error:)
          increment_metric("create_pull_request.error_handled", tags: failure_metric_tags(error:))
          Dependabot::Logger.log_exception(error, msg: "PR error handled, syncing repo state.")

          result = SynchronizeRepoState.new(
            repo: update_job.update_config.repo,
            event_source: "job.create_pull_request",
          ).run

          raise RetryJobError.new(error.message, reason: error_reason(error:)) if result.success?

          run_failure_hooks(error)
        end
      end
    end
  end
end
