# typed: true
# frozen_string_literal: true

require_relative "helpers"

module GitHub
  module Twirp
    class DependabotPullRequests
      class ServiceError < StandardError
        extend T::Sig
        include DependabotPullRequests::Helpers
        extend DependabotPullRequests::Helpers

        # Error types that trigger synching the repo state to Dependabot.
        REPO_STATE_ERROR_TYPES = [
          APIErrorType::ERROR_TYPE_REPO_NOT_FOUND,
          APIErrorType::ERROR_TYPE_REPO_ARCHIVED,
          APIErrorType::ERROR_TYPE_REPO_DISABLED,
          APIErrorType::ERROR_TYPE_DEPENDABOT_CANNOT_WRITE,
          APIErrorType::ERROR_TYPE_REPO_EMPTY,
          APIErrorType::ERROR_TYPE_REPO_LOCKED,
        ].freeze

        # Non-transient errors that are unlikely to be resolved with a retry.
        # Includes repo resync errors which may be retried only after a repo state sync.
        NON_TRANSIENT_ERROR_TYPES = [
          APIErrorType::ERROR_TYPE_REPO_OVER_SIZE_QUOTA,
          APIErrorType::ERROR_TYPE_REPO_RULE_VIOLATION,
          APIErrorType::ERROR_TYPE_RECORD_INVALID,
          APIErrorType::ERROR_TYPE_PROTECTED_BRANCH_UPDATE,
          APIErrorType::ERROR_TYPE_REQUEST_TOO_LARGE,
        ].freeze

        sig do
          params(
            message: String,
            error: MonolithTwirp::Dependabot::PullRequests::V1::Error,
            pull_request: T.nilable(MonolithTwirp::Dependabot::PullRequests::V1::PullRequest)
          ).returns(ServiceError)
        end
        def self.for_error(message, error, pull_request = nil)
          case resolve_api_error_number(error.type)
          when APIErrorType::ERROR_TYPE_DEPENDABOT_NOT_INSTALLED
            DependabotNotInstalledError.new(message, error, pull_request)
          when *REPO_STATE_ERROR_TYPES
            RepoStateServiceError.new(message, error, pull_request)
          when *NON_TRANSIENT_ERROR_TYPES
            ServiceError.new(message, error, pull_request)
          else
            TransientServiceError.new(message, error, pull_request)
          end
        end

        sig { returns(MonolithTwirp::Dependabot::PullRequests::V1::Error) }
        attr_reader :error

        sig { returns(T.nilable(MonolithTwirp::Dependabot::PullRequests::V1::PullRequest)) }
        attr_reader :pull_request

        sig do
          params(
            message: String,
            err: MonolithTwirp::Dependabot::PullRequests::V1::Error,
            pull_request: T.nilable(MonolithTwirp::Dependabot::PullRequests::V1::PullRequest)
          ).void
        end
        def initialize(message, err, pull_request = nil)
          @error = err
          @pull_request = pull_request
          super(message)
        end

        sig { returns(String) }
        def details
          error.message
        end

        sig { returns(Symbol) }
        def type
          resolve_api_error_symbol(@error.type)
        end

        sig { returns(T::Boolean) }
        def pull_request_was_created?
          return false if pull_request.blank?

          T.must(pull_request).github_number.positive?
        end
      end

      class DependabotNotInstalledError < ServiceError; end
      class RepoStateServiceError < ServiceError; end
      class TransientServiceError < ServiceError; end
    end
  end
end
