# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength
module HandleWebhook
  class IssueComment
    include GitHub::Telemetry::Traces::Traceable

    MENTION = %r{(?<!`)[@/]dependabot(?:-bot|\[bot\])?(?:\s+please)?}i
    COMMAND_START = /(^|\.|^\*|<.*>)\s*/
    COMMENT_FINISH = /[\s.?!]*\z/m
    LINE_FINISH = /[\s.?!]*$/
    DEPENDENCY_NAME = /\S+/

    IGNORE_SINGLE_DEP_VALIDATION_REGEX =
      /
        #{MENTION}:?\s+(ignore|skip)\s*
        (this\s*major\s*version|
        this\s*minor\s*version|
        this\s*patch\s*version|
        this\s*(dependency)?|
        this\s*(package)?)
        \s*
      /ix

    # Matches comments like:
    # @dependabot ignore <dependency name> major version
    # @dependabot ignore these dependencies
    # @dependabot ignore <dependency name>
    IGNORE_MULTIPLE_DEPS_VALIDATION_REGEX =
      /
        #{MENTION}:?\s+(ignore|skip)\s*
        (these\s*(dependencies|packages)?|
        #{DEPENDENCY_NAME}\s*(major|minor|patch)?\s*version|
        #{DEPENDENCY_NAME}\s*(dependency|package)?)
        \s*
      /ix

    UNIGNORE_VALIDATION_REGEX =
      /
        #{MENTION}:?\s+unignore
        (?!.*\bthis\b|\s\*\sdependency)\s+
        (?<dep_name>#{DEPENDENCY_NAME})\s*
        (\[\s*(?<version_req>[^\]]*)\s*\])?\s*
      /ix

    IGNORE_REGEX   = /#{MENTION}:?\s+(ignore|skip).*/ix
    UNIGNORE_REGEX = /#{MENTION}:?\s+unignore.*/ix

    IGNORE_MULTIPLE_DEPS_REGEX =
      /
        #{MENTION}:?\s+
        ignore\s+these\s+(dependencies|packages)?
      /ix

    CLOSE_REGEX =
      /
        #{MENTION}:?\s+(skip|close)
        ((\s+this)|#{LINE_FINISH})?(\s+(version|release)|#{LINE_FINISH})
      /ix

    SHOW_IGNORE_CONDITIONS_REGEX =
      /
        #{MENTION}:?\s+show\s+
        (?<dep_name>#{DEPENDENCY_NAME})\s+
        ignore\s+conditions\z
      /ix

    REOPEN_REGEX = /#{MENTION}:?\s+reopen/i
    MERGE_REGEX = /#{MENTION}:?\s+merge/i
    SQUASH_AND_MERGE_REGEX = /#{MENTION}:?\s+squash(?:\s*|-)(?:(?:and|&|\+)(?:\s*|-))?merge/i
    CANCEL_MERGE_REGEX = /#{MENTION}:?\s+cancel\s+merge/i
    REBASE_REQUEST = /#{MENTION}:?\s+(rebase?|update)/i
    RECREATE_REQUEST = /#{MENTION}:?\s+recreate?/i
    HEART_REGEX = /#{MENTION}:?\s+(?:i\s+)?love\s+you/i

    # Delegate each command to a relevant handler, which contains all the logic
    REQUEST_REGEXES = {
      IGNORE_REGEX => :handle_ignore_request,
      UNIGNORE_REGEX => :handle_unignore_request,
      SHOW_IGNORE_CONDITIONS_REGEX => :handle_ignore_show_request,
      CLOSE_REGEX => :handle_close_request,
      REOPEN_REGEX => :handle_reopen_request,
      MERGE_REGEX => :handle_merge_request,
      SQUASH_AND_MERGE_REGEX => :handle_squash_and_merge_request,
      CANCEL_MERGE_REGEX => :handle_merge_cancellation_request,
      REBASE_REQUEST => :handle_rebase_request,
      RECREATE_REQUEST => :handle_recreate_request,
      HEART_REGEX => :handle_heart_request,
    }.freeze

    attr_reader :webhook_body

    def initialize(webhook_body:, headers:)
      @webhook_body = webhook_body
      @received_at = received_at(headers) || Time.now.utc
    end

    # rubocop:disable Metrics/PerceivedComplexity
    # rubocop:disable Metrics/CyclomaticComplexity
    def run
      return if webhook_body.dig(:comment, :user, :login) == "dependabot[bot]"
      return unless author_is_dependabot?
      return if webhook_body[:action] == "deleted"
      return log_and_ignore unless dependabot_pr
      return log_and_ignore unless new_comment? || edited_comment?
      return log_and_ignore if comment_body.blank?

      handle_matched_commands || log_and_ignore
    rescue Octokit::Unauthorized
      retrying ||= false
      raise if retrying

      retrying = true
      uncache_installation_client
      retry
    rescue *SynchronizeRepoState::HANDLED_ERRORS
      raise unless dependabot_pr

      SynchronizeRepoState.new(
        repo: dependabot_pr.repo,
        event_source: "webhook.issue_comments.not_found",
      ).run
    end
    # rubocop:enable Metrics/CyclomaticComplexity
    # rubocop:enable Metrics/PerceivedComplexity

    private

    def author_is_dependabot?
      [webhook_body.dig(:issue, :user, :login), webhook_body.dig(:pull_request, :user, :login)].any? do |login|
        login == "dependabot[bot]"
      end
    end

    def handle_matched_commands
      tracer.in_span("#{self.class.name}#handle_matched_commands") do
        matched_regexes.each(&method(:process_matched_command))
        matched_regexes.any?
      end
    end

    def process_matched_command(command_regex)
      handler = REQUEST_REGEXES.fetch(command_regex)

      # Audit first so any housekeeping events such as removing a Repository
      # pause happen before we react to the command itself.
      audit
      send(handler)
      track_comment_metrics(handler)
    end

    # TODO: Remove this feature_enabled? method once we're confident that unignore commands are
    # working as expected
    def feature_enabled?(feature_name)
      return false unless dependabot_pr && dependabot_pr.repo

      dependabot_pr.repo.config_feature_enabled?(feature_name)
    end

    def dependabot_pr
      return @dependabot_pr if defined? @dependabot_pr

      @dependabot_pr = ::PullRequest.joins(:repo).find_by(
        repos: { github_id: webhook_body[:repository][:id] },
        github_number: issue_number,
      )
    end

    def comment_type
      return :review if webhook_body[:review]
      return :issue_comment if webhook_body[:issue]
      return :review_comment if webhook_body.dig(:comment, :diff_hunk)

      raise "Couldn't detect webhook type: #{webhook_body}"
    end

    def comment_body
      @comment_body ||= begin
        comment_body =
          case comment_type
          when :issue_comment, :review_comment
            webhook_body.fetch(:comment).fetch(:body) || ""
          when :review
            webhook_body.fetch(:review).fetch(:body) || ""
          else
            raise "Unexpected comment type #{comment_type}"
          end

        sanitize_comment_body(comment_body)
      end
    end

    def sanitize_comment_body(body)
      body.
        gsub(/\.\s/, ".\n").tr(" ", " ").
        lines.
        take_while { |l| !l.match?(/notifications@github\.com>? wrote/) }.
        join
    end

    # This list will be processed in the order returned by this method.
    def matched_regexes
      @matched_regexes ||=
        REQUEST_REGEXES.keys.select do |regex|
          /#{COMMAND_START}#{regex}/i.match?(comment_body) ||
            /#{regex}#{COMMENT_FINISH}/i.match?(comment_body)
        end
    end

    def comment_id
      return webhook_body.dig(:review, :node_id) if comment_type == :review

      webhook_body.dig(:comment, :id)
    end

    def requester_login
      case comment_type
      when :issue_comment, :review_comment
        webhook_body.fetch(:comment).fetch(:user).fetch(:login)
      when :review
        webhook_body.fetch(:review).fetch(:user).fetch(:login)
      else
        raise "Unexpected comment type #{comment_type}"
      end
    end

    def requester_id
      case comment_type
      when :issue_comment, :review_comment
        webhook_body.fetch(:comment).fetch(:user).fetch(:id)
      when :review
        webhook_body.fetch(:review).fetch(:user).fetch(:id)
      else
        raise "Unexpected comment type #{comment_type}"
      end
    end

    def new_comment?
      %w(created submitted).include?(webhook_body[:action])
    end

    def edited_comment?
      webhook_body[:action] == "edited"
    end

    def handle_rebase_request
      tracer.in_span("#{self.class.name}#handle_rebase_request") do
        HandlePullRequestCommentJob.perform_later(
          action: "HandleWebhook::IssueComment::HandleRebaseRequest",
          requester_id: requester_id,
          keyword_args: {
            pull_request: dependabot_pr,
            requester: requester_login,
            comment_id: comment_id,
            comment_type: comment_type,
          },
        )
      end
    end

    def handle_recreate_request
      HandlePullRequestCommentJob.perform_later(
        action: "HandleWebhook::IssueComment::HandleRecreateRequest",
        requester_id: requester_id,
        keyword_args: {
          pull_request: dependabot_pr,
          requester: requester_login,
          comment_id: comment_id,
          comment_type: comment_type,
        },
      )
    end

    def handle_ignore_request
      HandlePullRequestCommentJob.perform_later(
        action: "HandleWebhook::IssueComment::HandleIgnoreRequest",
        requester_id: requester_id,
        keyword_args: {
          pull_request: dependabot_pr,
          requester: requester_login,
          comment_body: comment_body,
          comment_id: comment_id,
        },
      )
    end

    def handle_unignore_request
      HandlePullRequestCommentJob.perform_later(
        action: "HandleWebhook::IssueComment::HandleUnignoreRequest",
        requester_id: requester_id,
        keyword_args: {
          pull_request: dependabot_pr,
          requester: requester_login,
          comment_body: comment_body,
          comment_id: comment_id,
        },
      )
    end

    def handle_ignore_show_request
      HandlePullRequestCommentJob.perform_later(
        action: "HandleWebhook::IssueComment::HandleIgnoreShowRequest",
        requester_id: requester_id,
        keyword_args: {
          pull_request: dependabot_pr,
          requester: requester_login,
          comment_body: comment_body,
          comment_id: comment_id,
        },
      )
    end

    def handle_close_request
      if dependabot_pr.repo.config_feature_enabled?(:deprecate_close_command)
        msg = "Beginning January 27, 2026, Dependabot will no longer support the @dependabot close command. " \
              "Please use GitHub's native pull request controls instead. " \
              "Please see the " \
              "[changelog announcement](https://github.blog/changelog/2025-10-06-upcoming-changes-to-github-dependabot-pull-request-comment-commands/) for additional details." # rubocop:disable Layout/LineLength

        CreateComment.new(pull_request: dependabot_pr, comment_body: msg).run
      end

      return if dependabot_pr.repo.config_feature_enabled?(:disable_close_command)

      HandlePullRequestCommentJob.perform_later(
        action: "HandleWebhook::IssueComment::HandleCloseRequest",
        requester_id: requester_id,
        keyword_args: {
          pull_request: dependabot_pr,
          requester: requester_login,
        },
      )
    end

    def handle_reopen_request
      if dependabot_pr.repo.config_feature_enabled?(:deprecate_reopen_command)
        msg = "Beginning January 27, 2026, Dependabot will no longer support the @dependabot reopen command. " \
              "Please use GitHub's native pull request controls instead. " \
              "Please see the " \
              "[changelog announcement](https://github.blog/changelog/2025-10-06-upcoming-changes-to-github-dependabot-pull-request-comment-commands/) for additional details." # rubocop:disable Layout/LineLength
        CreateComment.new(pull_request: dependabot_pr, comment_body: msg).run
      end

      return if dependabot_pr.repo.config_feature_enabled?(:disable_reopen_command)

      HandlePullRequestCommentJob.perform_later(
        action: "HandleWebhook::IssueComment::HandleReopenRequest",
        requester_id: requester_id,
        keyword_args: {
          pull_request: dependabot_pr,
          requester: requester_login,
        },
      )
    end

    def handle_merge_request
      if dependabot_pr.repo.config_feature_enabled?(:deprecate_merge_command)
        msg = "Beginning January 27, 2026, Dependabot will no longer support the @dependabot merge command. " \
              "Please use GitHub's native pull request controls instead. " \
              "Please see the " \
              "[changelog announcement](https://github.blog/changelog/2025-10-06-upcoming-changes-to-github-dependabot-pull-request-comment-commands/) for additional details." # rubocop:disable Layout/LineLength
        CreateComment.new(pull_request: dependabot_pr, comment_body: msg).run
      end

      return if dependabot_pr.repo.config_feature_enabled?(:disable_merge_command)

      HandlePullRequestCommentJob.perform_later(
        action: "HandleWebhook::IssueComment::HandleMergeRequest",
        requester_id: requester_id,
        keyword_args: {
          pull_request: dependabot_pr,
          requester: requester_login,
          comment_id: comment_id,
          comment_type: comment_type,
        },
      )
    end

    def handle_squash_and_merge_request
      if dependabot_pr.repo.config_feature_enabled?(:deprecate_squash_merge_command)
        msg = "Beginning January 27, 2026, Dependabot will no longer support the " \
              "@dependabot squash and merge command. Please use GitHub's native pull request controls instead. " \
              "Please see the " \
              "[changelog announcement](https://github.blog/changelog/2025-10-06-upcoming-changes-to-github-dependabot-pull-request-comment-commands/) for additional details." # rubocop:disable Layout/LineLength
        CreateComment.new(pull_request: dependabot_pr, comment_body: msg).run
      end

      return if dependabot_pr.repo.config_feature_enabled?(:disable_squash_merge_command)

      HandlePullRequestCommentJob.perform_later(
        action: "HandleWebhook::IssueComment::HandleMergeRequest",
        requester_id: requester_id,
        keyword_args: {
          pull_request: dependabot_pr,
          requester: requester_login,
          comment_id: comment_id,
          comment_type: comment_type,
          squash_commits: true,
        },
      )
    end

    def handle_merge_cancellation_request
      if dependabot_pr.repo.config_feature_enabled?(:deprecate_cancel_merge_command)
        msg = "Beginning January 27, 2026, Dependabot will no longer support the @dependabot cancel merge command. " \
              "Please use GitHub's native pull request controls instead. " \
              "Please see the " \
              "[changelog announcement](https://github.blog/changelog/2025-10-06-upcoming-changes-to-github-dependabot-pull-request-comment-commands/) for additional details." # rubocop:disable Layout/LineLength
        CreateComment.new(pull_request: dependabot_pr, comment_body: msg).run
      end

      return if dependabot_pr.repo.config_feature_enabled?(:disable_cancel_merge_command)

      HandlePullRequestCommentJob.perform_later(
        action: "HandleWebhook::IssueComment::HandleMergeCancellationRequest",
        requester_id: requester_id,
        keyword_args: {
          pull_request: dependabot_pr,
          requester: requester_login,
          comment_id: comment_id,
          comment_type: comment_type,
        },
      )
    end

    def handle_heart_request
      HandlePullRequestCommentJob.perform_later(
        action: "HandleWebhook::IssueComment::HandleHeartRequest",
        requester_id: requester_id,
        keyword_args: {
          pull_request: dependabot_pr,
          comment_id: comment_id,
          comment_type: comment_type,
        },
      )
    end

    def issue_number
      # We use this handler for pull request review comments, too, so need to
      # handle fetching the issue number from a couple of places
      webhook_body.dig(:issue, :number) ||
        webhook_body[:pull_request][:number]
    end

    def log_and_ignore
      Dependabot::Logger.info(
        msg: "Ignoring webhook",
        "code.namespace": "IssueComment",
        comment_type: comment_type,
        "gh.actor.id": webhook_body[:sender][:id],
        "gh.repo.id": webhook_body[:repository][:id],
        action: webhook_body[:action],
        handlers: matched_regexes.to_s,
        new_comment: new_comment?,
        edited_comment: edited_comment?,
        comment_body: comment_body,
        pull_request_number: issue_number,
        dependabot_pr_id: dependabot_pr&.id,
      )
    end

    def comment_created_at
      created_path = if webhook_body.key?("review")
                       %i(review submitted_at)
                     else
                       %i(comment created_at)
                     end
      Time.parse(webhook_body.dig(*created_path).to_s).utc
    end

    def audit
      dependabot_pr.event_stream.record_event(Activity::PullRequestEvents::COMMENT)
    end

    def track_comment_metrics(handler)
      handler_name = handler.to_s.delete_prefix("handle_")
      # Any synchronous reply to the comment (e.g. reaction) has been sent.
      # An async reply (e.g. branch update, comment reply) may still be pending.

      track_comment_command(handler_name)

      # How long ago was the comment "created"?
      created_at = comment_created_at
      created_seconds_ago = (Time.now.utc - created_at).to_f
      MetricsClient.timing("issue_comment.age_at_reply", created_seconds_ago,
                           tags: slo_tags(handler_name, created_seconds_ago))

      # How old was the comment when it was received?
      received_seconds_ago = (@received_at - created_at).to_f
      MetricsClient.timing("issue_comment.age_at_receive", received_seconds_ago,
                           tags: slo_tags(handler_name, received_seconds_ago))
    rescue ArgumentError => e
      Dependabot::Exceptions.report!(e)
      Dependabot::Logger.info(
        msg: "Could not determine age of webhook",
        "code.namespace": "IssueComment",
        comment_type: comment_type,
        action: webhook_body[:action],
        "gh.actor.id": webhook_body[:sender][:id],
        comment_body: comment_body,
      )
    end

    def track_comment_command(handler_name)
      return unless feature_enabled?("comment_metrics")

      MetricsClient.increment("issue_comment.received",
                              tags: {
                                handler_name: handler_name,
                                user_type: webhook_body[:sender][:type], # Bot, User, or Organization
                                performed_via_github_app: webhook_body.dig(:comment, :performed_via_github_app, :slug),
                              })
      Dependabot::Logger.info(
        msg: "Comment command processed",
        handler: handler_name,
        "gh.repo.id": webhook_body[:repository][:id],
        "gh.actor.id": webhook_body[:sender][:id],
      )
    end

    def slo_tags(handler_name, age)
      target = case handler_name
               when "ignore_request", "merge_request",
                    "squash_and_merge_request"
                 20
               else
                 10
               end
      {
        handler: handler_name,
        slo_met: age < target,
      }
    end

    def uncache_installation_client
      GitHubHelpers.delete_cached_access_token_for(
        account: dependabot_pr.repo.account,
      )
      @installation_github_client = nil
    end

    def installation_github_client
      @installation_github_client ||=
        GitHubHelpers::ClientWithRetries.
        new(account: dependabot_pr.repo.account)
    end

    def received_at(headers)
      return unless headers

      request_start = headers["X-Request-Start"]&.delete_prefix("t=")&.to_i
      return unless request_start&.nonzero?

      Time.at(request_start / 1_000_000).utc
    end
  end
end
# rubocop:enable Metrics/ClassLength
