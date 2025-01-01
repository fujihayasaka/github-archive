# typed: true
# frozen_string_literal: true

module Branches
  class OverviewView < ListView
    include ::Branches::BranchHelper

    def selected_view
      :overview
    end

    def template_name
      "branches/overview_view"
    end

    def all_branches
      [
        branch_finder.default_branch,
        *branch_finder.your_branches,
        *branch_finder.active_branches,
        *branch_finder.stale_branches,
      ]
    end

    def primary_branch
      create_item_view(branch_finder.default_branch, page_section: :default_branch)
    end

    def your_branches
      @your_branches ||= create_item_views(branch_finder.your_branches, page_section: :your_branches)
    end

    def active_branches
      @active_branches ||= create_item_views(branch_finder.active_branches, page_section: :active_branches)
    end

    def stale_branches
      @stale_branches ||= create_item_views(branch_finder.stale_branches, page_section: :stale_branches)
    end

    private

    def branch_finder_options
      super.merge(branches_being_renamed: branches_being_renamed)
    end
  end
end
