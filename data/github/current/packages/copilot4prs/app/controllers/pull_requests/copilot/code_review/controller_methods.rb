# typed: true
# frozen_string_literal: true

module PullRequests::Copilot::CodeReview::ControllerMethods
  extend T::Helpers
  extend ActiveSupport::Concern

  include GitHub::Memoizer

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, T.class_of(ApplicationController))
  end

  sig { params(comment: PullRequestReviewComment, parent: PullRequestReviewComment).returns(T.nilable(T::Boolean)) }
  private def should_chat_within_this_thread?(comment:, parent:)
    chat_with_comments_enabled? &&
      pull_request_reviewer_bot.present? &&
      !authored_by_copilot?(comment:) &&
      reply_to_copilot_thread?(parent:)
  end

  sig { returns(T::Boolean) }
  private def chat_with_comments_enabled?
    FeatureFlag.vexi.enabled?(:ccr_chat_with_comments, current_user, default: false) &&
      FeatureFlag.vexi.enabled?(:ccr_chat_with_comments, current_repository, default: false)
  end

  sig { params(comment: PullRequestReviewComment).returns(T::Boolean) }
  private def authored_by_copilot?(comment:)
    comment.user_id == T.must(pull_request_reviewer_bot).id
  end

  sig { params(parent: PullRequestReviewComment).returns(T::Boolean) }
  private def reply_to_copilot_thread?(parent:)
    parent.user_id == T.must(pull_request_reviewer_bot).id
  end

  sig { returns(T.nilable(Bot)) }
  memoize private def pull_request_reviewer_bot
    pull_request_reviewer_app&.bot
  end

  sig { returns(T.nilable(Integration)) }
  private def pull_request_reviewer_app
    ::Apps::Privileged.integration(:copilot_pull_request_reviewer)
  end
end
