# typed: strict
# frozen_string_literal: true

module Discussions
  class UnblockUserFromCommentFormComponent < ApplicationComponent
    extend T::Sig

    sig { params(discussion_or_comment: T.any(Discussion, DiscussionComment), repository: Repository).void }
    def initialize(discussion_or_comment:, repository:)
      @discussion_or_comment = discussion_or_comment
      @repository = repository
    end

    sig { returns(T.any(Discussion, DiscussionComment)) }
    attr_reader :discussion_or_comment

    sig { returns(Repository) }
    attr_reader :repository

    private

    sig { returns(String) }
    def target_class
      discussion_or_comment.is_a?(Discussion) ? "Discussion" : "Comment"
    end

    sig { returns(String) }
    def form_path
      organization_settings_blocked_user_path(
        repository.owner_display_login,
        login: discussion_or_comment.author_display_login,
        content_id: discussion_or_comment.global_relay_id,
      )
    end
  end
end
