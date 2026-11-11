# typed: strict
# frozen_string_literal: true

module Discussions
  class EditHistory::ListComponent < ApplicationComponent
    sig { params(editable: T.any(Discussion, DiscussionComment)).void }
    def initialize(editable:)
      @editable = editable
    end

    private

    sig { returns(T.any(Discussion, DiscussionComment)) }
    attr_reader :editable

    sig { returns(T::Array[T.any(DiscussionEdit, DiscussionCommentEdit)]) }
    memoize def edits
      association = editable.is_a?(Discussion) ? :discussion : :discussion_comment
      editable.
        user_content_edits.
        includes(:editor, :deleted_by, association => :repository).
        order(id: :desc).to_a
    end

    sig { returns(T::Boolean) }
    memoize def includes_created?
      editable.async_includes_created_edit?.sync
    end

    sig { returns(Integer) }
    memoize def edit_count
      if includes_created?
        edits.count - 1
      else
        edits.count
      end
    end

    sig { returns(T.nilable(Integer)) }
    memoize def created_edit_id
      return unless includes_created?
      edits.last&.id
    end

    sig { returns(T.nilable(Integer)) }
    memoize def latest_edit_id
      edits.first&.id
    end

    sig { returns(User) }
    memoize def ghost_user
      User.ghost
    end
  end
end
