# typed: true
# frozen_string_literal: true

module Comments
  class CommentAuthorAssociationComponent < ApplicationComponent
    attr_reader :comment, :repository

    def initialize(comment:)
      @comment = comment
      @repository = comment.try(:repository)
    end

    def render?
      return false unless repository
      !repository.private?
    end

    memoize def viewer_did_author?
      comment.user_id == current_user&.id
    end

    def author_association
      comment.author_association_symbol(current_user)
    end

    memoize def dismiss_first_contribution_path
      dismiss_issue_first_contribution_prompt_path(comment.repository.owner_display_login, comment.repository.name, comment.number)
    end

    memoize def dismiss_first_contribution_and_redirect_path
      dismiss_issue_first_contribution_prompt_and_redirect_path(comment.repository.owner_display_login, comment.repository.name, comment.number)
    end
  end
end
