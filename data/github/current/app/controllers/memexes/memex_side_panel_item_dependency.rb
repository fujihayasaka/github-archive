# typed: true
# frozen_string_literal: true

module Memexes
  module MemexSidePanelItemDependency
    extend ActiveSupport::Concern
    extend T::Helpers
    extend T::Sig
    include GitHub::Memoizer

    requires_ancestor { Memexes::Controller }

    def not_found_error(e)
      render_json_error(error: e.message, status: :not_found)
    end

    def unsupported_method_error(e)
      render_json_error(error: "Method is not implemented for item: #{e.message}", status: :bad_request)
    end

    def incorrect_permissions_error(e)
      render_json_error(error: e.message, status: :forbidden)
    end

    def invalid_params_error(e)
      render_json_error(error: e.message, status: :bad_request)
    end

    sig { returns(T.nilable(MemexSidePanel::Item)) }
    memoize def this_item
      case underscored_params[:kind]
      when "issue", "project_issue"
        item_id = underscored_params[:item_id]
        return nil unless item_id.present?

        repo_id = underscored_params[:repository_id]
        return nil unless repo_id.present?

        # IssueItem may have to eventually become a class that ProjectIssueItem inherits from
        # to support some project-specific functionality, for now though, we'll just use
        # IssueItem here
        MemexSidePanel::IssueItem.new(item_id, repository_id: repo_id, memex_project: this_memex,
          current_user: current_user, cap_filter: cap_filter)
      when "project_draft_issue"
        project_item_id = underscored_params[:project_item_id]
        return nil unless project_item_id.present?

        MemexSidePanel::DraftIssueItem.new(project_item_id, memex_project: this_memex, current_user: current_user)
      else
        nil
      end
    end
  end
end
