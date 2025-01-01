# typed: true
# frozen_string_literal: true

module PullRequests
  class ForkCleanupView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    attr_reader :pull, :head_branch_deleteable, :head_label

    def action_class
      head_branch_safely_deleteable? ? "branch-action-state-merged" : "branch-action-state-closed-dirty"
    end

    def head_branch_deleteable?
      head_branch_deleteable
    end

    def head_branch_safely_deleteable?
      pull.head_ref_safely_deleteable_by?(current_user)
    end

    def head_branch_unsafely_deleteable?
      pull.head_ref_unsafely_deleteable_by?(current_user)
    end
  end
end
