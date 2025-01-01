# typed: strict
# frozen_string_literal: true

module Discussions
  class BlockFromCommentModalComponent < ApplicationComponent
    extend T::Sig

    include CommentsHelper
    include FeatureFlagHelper
    # discussion_or_comment - a Discussion or DiscussionComment
    # repository - the Repository the discussion or comment belongs to
    sig { params(discussion_or_comment: T.any(Discussion, DiscussionComment), repository: Repository).void }
    def initialize(discussion_or_comment:, repository:)
      @discussion_or_comment = discussion_or_comment
      @repository = repository
    end

    private

    sig { returns(T.any(Discussion, DiscussionComment)) }
    attr_reader :discussion_or_comment

    sig { returns(Repository) }
    attr_reader :repository

    delegate :author, to: :discussion_or_comment

    delegate :code_of_conduct, to: :repository

    sig { returns(T::Boolean) }
    def render?
      discussion_or_comment.present? && discussion.present? && repository.present? && logged_in? &&
        discussion&.repository_id == repository.id && GitHub.discussions_available_on_platform? &&
        repo_owner.present? && repo_owner.organization? && repo_owner.blocked_users_manageable_by?(current_user)
    end

    sig { returns(T::Boolean) }
    memoize def should_show_delete_discussion_radios?
      discussion_or_comment.is_a?(Discussion)
    end

    sig { returns T.nilable(Discussion) }
    memoize def discussion
      if discussion_or_comment.respond_to?(:discussion)
        discussion_or_comment.discussion
      else
        T.cast(discussion_or_comment, Discussion)
      end
    end

    sig { returns(User) }
    memoize def repo_owner
      T.must(repository.owner)
    end

    sig { returns(String) }
    def target_class
      discussion_or_comment.is_a?(Discussion) ? "Discussion" : "Comment"
    end

    sig { returns(String) }
    def form_path
      # This endpoint is gated by a Organization#blocked_users_manageable_by? check, so the form won't work for
      # any user who lacks that access.
      organization_settings_blocked_users_path(repository.owner_display_login)
    end
  end
end
