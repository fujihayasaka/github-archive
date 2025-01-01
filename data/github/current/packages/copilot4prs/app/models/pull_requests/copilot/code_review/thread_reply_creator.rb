# typed: true
# frozen_string_literal: true

module PullRequests::Copilot::CodeReview
  class ThreadReplyCreator
    ERROR_COMMENTS = "Copilot encountered an error and was unable to reply to this thread. You can try again by submitting a new comment."

    sig do
      params(
        bot: Bot,
        comment: T::Hash[T.untyped, T.untyped],
        pull: PullRequest,
        return_with_error: T::Boolean,
        thread: PullRequestReviewThread,
      ).void
    end
    def initialize(bot:, comment:, pull:, return_with_error:, thread:)
      @bot = bot
      @comment = comment
      @pull = pull
      @return_with_error = return_with_error
      @thread = thread
    end

    sig { returns(T::Boolean) }
    def create
      ActiveRecord::Base.connected_to(role: :writing) do
        log("Creating reply for thread #{thread.id} on pull request #{pull.id}")
        reply = thread.build_reply(user: bot, body: comment["body"])

        if return_with_error
          log("Returning with error, setting reply body to error message")
          reply.body = ERROR_COMMENTS
          reply.submit!

          if reply.persisted?
            log("Reply was posted successfully with error message")
            return true
          else
            log("Reply was not posted successfully with error message")
            return false
          end
        elsif comment.empty?
          log("comment is empty, not submitting reply")

          if reply.body.present?
            log("comment is empty, but reply body is present, submitting reply")
            reply.submit!

            if reply.persisted?
              log("Reply was posted successfully with existing body")
              return true
            else
              log("Reply was not posted successfully with existing body")
              return false
            end
          end

          log("comment is empty and reply body is not present, not submitting reply")
          return false
        end

        log("Submitting reply with body: #{reply.body}")
        reply.submit!

        if reply.persisted?
          log("Reply was posted successfully")
          true
        else
          log("Reply was not posted successfully")
          log("Reply errors: #{reply.errors.full_messages.join(', ')}")
          false
        end
      end
    end

    private

    sig { returns(Bot) }
    attr_reader :bot

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    attr_reader :comment

    sig { returns(PullRequest) }
    attr_reader :pull

    sig { returns(PullRequestReviewThread) }
    attr_reader :thread

    sig { returns(T::Boolean) }
    attr_reader :return_with_error

    sig { params(message: String).void }
    def log(message)
      GitHub.logger.info("copilot_code_review_reply_creator: #{message}",
        "gh.pull_request.id" => pull.id,
        "gh.pull_request.url" => pull.url,
        "gh.pull_request_review_thread.id" => thread.id,
        "gh.request_id" => GitHub.context[:request_id]
      )
    end
  end
end
