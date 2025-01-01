# typed: true
# frozen_string_literal: true

module Branches
  class PaginatedView < ListView
    include ::Branches::BranchHelper

    attr_reader :selected_view

    def template_name
      "branches/paginated_view"
    end

    def title
      case selected_view
      when :all
        if search_mode?
          "Search results"
        else
          "All branches"
        end
      when :yours;  "Your branches"
      when :active; "Active branches"
      when :stale;  "Stale branches"
      else raise NotImplementedError
      end
    end

    def all_branches
      if show_default_branch?
        [
          branch_finder.default_branch,
          *selected_branches,
        ]
      else
        selected_branches
      end
    end

    def show_default_branch?
      selected_view == :all &&
        !search_mode? &&
        selected_branches.current_page == 1
    end

    def branches
      @branches ||= create_item_views(selected_branches)
    end

    def primary_branch
      create_item_view(branch_finder.default_branch, page_section: :default_branch)
    end

    private

    def selected_branches
      case selected_view
      when :all
        if search_mode?
          branch_finder.query_branches
        else
          branch_finder.all_branches
        end
      when :yours;  branch_finder.your_branches
      when :active; branch_finder.active_branches
      when :stale;  branch_finder.stale_branches
      else raise NotImplementedError
      end
    end

    def branch_finder_options
      {
        query: search_query,
        page: attributes[:page],
        limit: 20,
        branches_being_renamed: branches_being_renamed,
      }
    end
  end
end
