# typed: true
# frozen_string_literal: true

module PullRequests
  class CommentActionsComponent < ApplicationComponent
    include ApplicationComponent::Rescuable

    rescue_from StandardError, with: :nothing

    sig { params(repository: T.nilable(Repository), comment: Issue::Adapter::CommentAdapter).void }
    def initialize(repository:, comment:)
      @repository = repository
      @comment = comment
    end

    sig { returns(T::Array[CommentAction::Record]) }
    memoize def custom_actions
      CommentAction.for(repository: T.must(@repository), comment_type:, comment_id:)
    end

    sig { returns(T::Boolean) }
    def render?
      repo_may_display_comment_actions? &&
        author_may_post_comment_actions? &&
        pull_request_comment? &&
        has_copilot_chat_access? #TODO: maybe we should still render links?
      # TODO: Check sentry extension is enabled
    end

    private

    sig { returns(T::Boolean) }
    def repo_may_display_comment_actions?
      @repository&.feature_enabled?(:display_comment_actions) ||
        @repository&.owner&.feature_enabled?(:display_comment_actions) ||
        false
    end

    sig { returns(T::Boolean) }
    def author_may_post_comment_actions?
      comment_author&.feature_enabled?(:may_post_comment_actions) || false
    end

    sig { returns(T::Boolean) }
    def pull_request_comment? = !!@comment.pull_request

    sig { returns(T::Boolean) }
    def has_copilot_chat_access?
      current_copilot_user_v2&.dotcom_chat_enabled? || false
    end

    sig { returns(String) }
    def comment_type = "IssueComment"

    sig { returns(Integer) }
    def comment_id = @comment.database_id

    sig { returns(T.nilable(User)) }
    def comment_author = @comment.author
  end
end
