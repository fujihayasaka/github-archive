# typed: true
# frozen_string_literal: true

module Comments
  class CommentEditHistoryLogComponent < ApplicationComponent
    include AvatarHelper
    include BotHelper

    EDITS_LIMIT = 100

    attr_reader :comment

    def initialize(comment:)
      @comment = comment
    end

    def render?
      edits.present?
    end

    memoize def edits
      if viewer_can_read_user_content_edits?
        edits_query.limit(EDITS_LIMIT)
      else
        edits_query.none
      end
    end

    def edit_count
      includes_created_edit ? edits_total_count - 1 : edits_total_count
    end

    memoize def edits_total_count
      edits_query.count
    end

    memoize def includes_created_edit
      # `edits` originally ordered by ID DESC
      # which means that the first edit (creation) will be the last in the `edits` array
      # UserContentEditable#include_created_edits? is true when the first edit's creation date equals to the 2nd edit's creation date
      # Hence we do `edits#reverse`; this way we won't change the implementation of UserContentEditable#include_created_edits?
      # which might break behaviour at other call sites
      # For a special case when number of edits exceeding EDITS_LIMIT, we don't want to include the preloaded content_edits
      # Instead we would like to execute the extra comment#user_content_edits at UserContentEditable#include_created_edits?
      # to ensure that the first edit (of creation) is included at the list of edits ,and hence we have an accurate result
      preloaded_edits = edits_total_count <= EDITS_LIMIT ? edits.reverse : nil
      comment.includes_created_edit?(content_edits: preloaded_edits)
    end

    private

    def edits_query
      if comment.is_a?(PullRequest)
        comment.issue.user_content_edits.includes(:editor, :deleted_by).order(id: :desc)
      else
        comment.user_content_edits.includes(:editor, :deleted_by).order(id: :desc)
      end
    end

    def viewer_can_read_user_content_edits?
      comment.viewer_can_read_user_content_edits?(current_user)
    end
  end
end
