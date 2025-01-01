# typed: true
# frozen_string_literal: true

module TemplateEditorHelper
  class FieldEditor
    attr_reader :preview_block, :editor_block

    def initialize(field)
      @field = field
    end

    def preview(&block)
      @preview_block = block
    end

    def editor(&block)
      @editor_block = block
    end
  end

  extend T::Helpers

  requires_ancestor { ApplicationController::AuthenticatedSystem }

  def can_commit_to_this_branch?(repository, branch)
    can_commit_to_branch_status(repository, branch) != :blocked
  end

  def can_commit_to_branch_status(repository, branch)
    BranchRuleEvaluator.branch_commitability_status(repository, current_user, branch)
  end

  def will_create_branch?(repository, branch)
    return true unless can_commit_to_this_branch?(repository, branch)
    branch != repository.default_branch
  end
end
