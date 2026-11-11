# typed: strict
# frozen_string_literal: true

module CodeCoverage
  # Once Turboquality has computed the coverage overview for a pull request, it
  # signals on the CoveragePullRequestOverview topic.
  # We use this to post coverage information on the corresponding PR.
  class PullRequestOverviewProcessor < GitHub::StreamProcessors::SingleMessageProcessor
    include GitHub::StreamProcessors::TransientErrorResiliency
    include GitHub::Memoizer

    class Error < StandardError; end

    class CommentUpdateError < Error
      sig { params(comment_id: Integer, validation_errors: String).void }
      def initialize(comment_id:, validation_errors:)
        super("Failed to update coverage comment #{comment_id}: #{validation_errors}")
      end
    end

    class CommentCreateError < Error
      sig { params(original_message: String).void }
      def initialize(original_message:)
        super("Failed to create coverage comment: #{original_message}")
      end
    end

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
      categories = overview[:categories] || []

      logging_context.merge!(
        "gh.repo.id" => repo_id,
        "gh.pull_request.number" => pr_number,
        "gh.code_coverage.head_commit_sha" => overview[:head_commit_sha],
        "gh.code_coverage.categories_count" => categories.length,
      )

      log_info(
        "Received new coverage pull request overview message",
        "code.function" => "process_message",
      )

      repository = T.cast(Repositories.domain.by_id(repo_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
      return if repository.nil?

      if !CodeCoverage.available?(repository)
        log_info(
          "Dropping coverage pull request overview message because code coverage is not available for the repository",
          "code.function" => "process_message",
        )
        return
      end

      pull_request = PullRequest.with_number_and_repo(pr_number, repository)
      return if pull_request.nil?

      issue = pull_request.issue
      finder = CodeCoverage::CommentFinder.new(issue:, author: code_quality_bot)

      # Search on replica first to reduce primary DB load.
      existing_comment = T.let(finder.find, T.nilable(IssueComment))

      with_primaries ApplicationRecord::IssuesPullRequests do
        existing_comment ||= finder.find

        comment = CodeCoverage::Comment.new(
          overview: overview,
          repository: repository,
          pull_request: pull_request,
          updated: existing_comment.present?,
        )

        if existing_comment
          update_existing_comment(existing_comment, comment.body)
        else
          create_new_comment(issue, comment.body)
        end
      end
    end

    private

    sig { params(existing_comment: IssueComment, new_body: String).void }
    def update_existing_comment(existing_comment, new_body)
      return if existing_comment.update_body(new_body, code_quality_bot)

      raise CommentUpdateError.new(
        comment_id: existing_comment.id,
        validation_errors: existing_comment.errors.full_messages.join(", "),
      )
    end

    sig { params(issue: Issue, body: String).void }
    def create_new_comment(issue, body)
      issue.comments.create!(
        user: code_quality_bot,
        body:,
      )
    rescue ActiveRecord::RecordInvalid => e
      raise CommentCreateError.new(original_message: e.message)
    end

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
