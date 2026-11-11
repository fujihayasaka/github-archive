# typed: strict
# frozen_string_literal: true

module Api::Serializer::PullRequest
  class DiffStats
    # This has been extracted from Api::Serializer::PullsDependency so that we maintain parity between
    # the functionality of compiling metrics on a pull request's diff between the current REST api
    # defined in dotcom and the new endpoints being built in pullsd

    include GitHub::Memoizer

    sig { params(pull_request: PullRequest).void }
    def initialize(pull_request:)
      @pull_request = pull_request
    end

    sig { returns(T::Hash[Symbol, Integer]) }
    def call
      GitHub.tracer.in_span("Api::Serializer::PullsDependency#pull_request_diff_stats_hash") do
        total_commits = 0
        additions     = 0
        deletions     = 0
        changed_files = 0

        if @pull_request.historical_comparison.valid?
          begin
            total_commits, additions, deletions, changed_files = Promise.all([
              @pull_request.async_total_commits,
              @pull_request.async_additions,
              @pull_request.async_deletions,
              @pull_request.async_changed_files
            ]).sync
          rescue GitRPC::CommandFailed, Repository::CommandFailed => boom
            Failbot.report boom, app: "github-user"
            GitHub.logger.warn("Rescue GitRPC::CommandFailed, Repository::CommandFailed", {
              "code.namespace": "Api::Serializer::PullsDependency",
              "code.function": "pull_request_diff_stats_control",
              "exception": boom,
              "error_type": "#{boom.class.name}",
            })
          end
        else
          GitHub.logger.warn("Invalid pull.historical_comparison or rescued object missing", {
            "code.namespace": "Api::Serializer::PullsDependency",
            "code.function": "pull_request_diff_stats_control",
            "gh.pull.id": @pull_request.id,
            "gh.issue.id": @pull_request.issue&.id,
          })
        end

        {
          commits: total_commits,
          additions: additions,
          deletions: deletions,
          changed_files: changed_files,
        }
      end
    end
  end
end
