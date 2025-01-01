# typed: true
# frozen_string_literal: true

module PullRequests::Copilot::CodeReview
  class ThreadReplyProcessor
    REACTION_CONTENT = "eyes"

    sig do
      params(
        actor_id: Integer,
        copilot: Bot,
        pull_request_id: Integer,
        pull_request_review_comment_id: Integer,
        pull_request_review_id: Integer,
        pull_request_review_thread_id: Integer,
        repository_id: Integer,
      ).void
    end
    def initialize(
      actor_id:,
      copilot:,
      pull_request_id:,
      pull_request_review_comment_id:,
      pull_request_review_id:,
      pull_request_review_thread_id:,
      repository_id:
    )
      @actor_id = actor_id
      @copilot = copilot
      @pull_request_id = pull_request_id
      @pull_request_review_comment_id = pull_request_review_comment_id
      @pull_request_review_id = pull_request_review_id
      @pull_request_review_thread_id = pull_request_review_thread_id
      @repository_id = repository_id
    end

    sig do
      params(
        actor_id: Integer,
        copilot: Bot,
        pull_request_id: Integer,
        pull_request_review_comment_id: Integer,
        pull_request_review_id: Integer,
        pull_request_review_thread_id: Integer,
        repository_id: Integer,
      ).void
    end
    def self.process(
      actor_id:,
      copilot:,
      pull_request_id:,
      pull_request_review_comment_id:,
      pull_request_review_id:,
      pull_request_review_thread_id:,
      repository_id:
    )
      new(
        actor_id:,
        copilot:,
        pull_request_id:,
        pull_request_review_comment_id:,
        pull_request_review_id:,
        pull_request_review_thread_id:,
        repository_id:,
      ).process
    end

    sig { void }
    def process
      log("Processing CopilotCodeReviewThreadReplyRequested event")
      react_to_comment
      instrument_event
      notify_socket_subscribers
      log("Processing completed successfully")
    end

    private

    sig { returns(Integer) }
    attr_reader(
      :actor_id,
      :pull_request_id,
      :pull_request_review_comment_id,
      :pull_request_review_id,
      :pull_request_review_thread_id,
      :repository_id,
    )

    sig { returns(Bot) }
    attr_reader :copilot

    sig { void }
    def react_to_comment
      log("reacting to pull request review comment with content: #{REACTION_CONTENT}")
      ::PullRequestReviewCommentReaction.react(
        content: REACTION_CONTENT,
        subject_id: pull_request_review_comment_id,
        user: copilot,
      )
      log("reaction added successfully")
    end

    sig { void }
    def instrument_event
      log("instrumenting CopilotCodeReviewThreadReplyRequested event")
      GlobalInstrumenter.instrument(
        "copilot_code_review_agent.v0.CopilotCodeReviewThreadReplyRequested",
        {
          actor_id:,
          pull_request_id:,
          pull_request_review_comment_id:,
          pull_request_review_id:,
          pull_request_review_thread_id:,
          repository_id:,
        },
      )
      log("event instrumented successfully")
    end

    sig { void }
    def notify_socket_subscribers
      log("notifying socket subscribers for pull request review thread")
      thread = PullRequestReviewThread.find_by(id: pull_request_review_thread_id)
      return unless thread
      log("notifying socket subscribers: Found thread with id: #{thread.id}")

      pull_request_review = thread.pull_request_review
      return unless pull_request_review
      log("notifying socket subscribers: Found pull request review with id: #{pull_request_review.id}")

      pull_request_review.notify_socket_subscribers
      log("socket subscribers notified successfully")
    end

    sig { params(message: String).void }
    def log(message)
      GitHub.logger.info("copilot_code_review_process: #{message}",
        "gh.pull_request.id" => pull_request_id,
        "gh.pull_request_review.id" => pull_request_review_id,
        "gh.pull_request_review_comment.id" => pull_request_review_comment_id,
        "gh.pull_request_review_thread.id" => pull_request_review_thread_id,
        "gh.repository.id" => repository_id,
        "gh.request_id" => GitHub.context[:request_id],
        "gh.user.id" => actor_id,
      )
    end
  end
end
