# typed: strict
# frozen_string_literal: true

module CodeCoverage
  # Once Turboquality has computed the coverage overview for a pull request, it
  # signals on the CoveragePullRequestOverview topic.
  # We use this to post coverage information on the corresponding PR.
  class CoveragePullRequestOverviewProcessor < GitHub::StreamProcessors::SingleMessageProcessor
    include GitHub::StreamProcessors::TransientErrorResiliency
    include GitHub::Memoizer

    class Error < StandardError; end

    DEFAULT_GROUP_ID = "code_coverage_processed_pr_overview"
    DEFAULT_SUBSCRIBE_TO = T.let([
      /turboquality\.v0\.CoveragePullRequestOverview\Z/,
    ].freeze, T::Array[Regexp])

    options[:min_bytes] = 5.kilobytes
    options[:max_wait_time] = 0.2.seconds
    options[:max_bytes_per_partition] = 100.kilobytes
    options[:session_timeout] = 60.seconds
    options[:start_from_beginning] = false

    resolve_tenant_context do |message|
      Repositories::Public.get_active_or_deleted!(message.value[:repository_id]).owner&.business
    end

    sig { params(group_id: T.nilable(String), subscribe_to: T.nilable(T::Array[Regexp])).void }
    def setup(group_id: nil, subscribe_to: nil)
      options[:group_id] ||= DEFAULT_GROUP_ID
      options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
      self.transient_error_max_retries = 20
    end

    sig { override.params(message: GitHub::StreamProcessors::Message).returns(T.anything) }
    def process_message(message)
      overview = message.value
      repo_id = overview[:repository_id]
      pr_number = overview[:pr_number]
      logging_context.merge!(
        "gh.repo.id" => repo_id,
        "gh.pull_request.number" => pr_number,
        "gh.code_coverage.base_ref_coverage" => overview[:base_ref_coverage],
        "gh.code_coverage.head_ref_coverage" => overview[:head_ref_coverage],
        "gh.code_coverage.base_commit_sha" => overview[:base_commit_sha],
        "gh.code_coverage.head_commit_sha" => overview[:head_commit_sha],
        "gh.code_coverage.label" => overview[:label],
        "gh.code_coverage.language_name" => overview[:language_name],
        "gh.code_coverage.files_count" => overview[:files]&.length,
      )

      log_info(
        "Received new coverage pull request overview message",
        "code.function" => "process_message",
      )

      repository = T.cast(Repositories.domain.by_id(repo_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
      return if repository.nil?

      pull_request = PullRequest.with_number_and_repo(pr_number, repository)
      return if pull_request.nil?

      with_primaries ApplicationRecord::IssuesPullRequests do
        pull_request.issue&.comments&.create!(
          user: code_quality_bot,
          body: "Code Coverage message",
        )
      end
    end

    private

    sig { returns(T.untyped) }
    memoize def code_quality_bot
      bot = Apps::Privileged.attribution_only_system_identity_for(:code_quality)
      raise "GitHub Code quality bot not found" if bot.nil?

      bot
    end

    sig { params(message: String, context: T::Hash[String, T.untyped]).void }
    def log_info(message, context = {})
      GitHub.logger.info(message, logging_context.merge(context).merge(
        "code.function" => caller_locations(1, 1)&.first&.base_label || "unknown_function",
      ))
    end

    sig { params(message: String, context: T::Hash[String, T.untyped]).void }
    def log_error(message, context = {})
      GitHub.logger.error(message, logging_context.merge(context).merge(
        "code.function" => caller_locations(1, 1)&.first&.base_label || "unknown_function",
      ))
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def logging_context
      @logging_context ||= T.let({}, T.nilable(T::Hash[String, T.untyped]))
    end
  end
end
