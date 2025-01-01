# typed: true
# frozen_string_literal: true

module Memexes
  module MemexProjectItemDependency
    include MemexesHelper
    include GitHub::Memoizer
    extend ActiveSupport::Concern
    extend T::Helpers

    requires_ancestor { Memexes::Controller }

    MAX_BULK_UPDATE_SIZE = 50

    private

    def item_id
      underscored_params[:memex_project_item_id]
    end

    # When updating a single item, `item_ids` will contain the single item's id and is used to populate `these_items`
    def item_ids
      underscored_params[:memex_project_items]&.map { |item| item[:id] } || [underscored_params[:memex_project_item_id]]
    end

    # `this_item` represents the _single_ item being updated in an update request to `/items`
    def this_item
      return @this_item if defined?(@this_item)
      @this_item = this_memex
        .memex_project_items
        .includes(:content)
        .find_by(id: item_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    # `these_items` represents the _multiple_ items being updated in an update request to `/items`, however,
    # when a single item is being updated, it will contain `this_item`
    def these_items
      return @these_items if defined?(@these_items)
      @these_items = this_memex
        .memex_project_items
        .includes(:content)
        .where({ id: item_ids })
    end

    sig do
      params(
        items: T.any(ActiveRecord::AssociationRelation, T::Array[MemexProjectItem]),
        columns: T::Array[MemexProjectColumn]
      ).returns([T.nilable(MemexProjectItem::PrefilledAssociations), MemexProjectItemRedactor])
    end
    def prefill_memex_item_associations(items, columns:)
      # where we use the prefiller to fill a single item
      prefilled_associations = MemexProjectItemPrefiller.new(
        items,
        columns: columns,
        title_column: this_memex.columns.find(&:title?)
      ).prefill

      redactor = MemexProjectItemRedactor.new(
        viewer: current_user,
        items: items,
        columns: columns,
        prefilled_associations: prefilled_associations,
        cap_filter: cap_filter
      )

      [prefilled_associations, redactor]
    end

    # require the items and their dependencies to be readable by the actor
    def require_these_items
      if these_items.nil? || item_ids.nil? || these_items.length != item_ids.length # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        return render_404
      end
      if these_items.size > MAX_BULK_UPDATE_SIZE
        return render_json_error(error: "You can update a max of #{MAX_BULK_UPDATE_SIZE} items at a time",
          status: :unprocessable_entity)
      end

      these_items.each do |item|
        return render_404 unless item&.content
        next if item.draft_issue?

        issue = item_content(item)
        return render_404 unless issue&.repository
        return render_404 unless issue.readable_by?(current_user)
        return render_404 if current_user&.blocked_by?(issue.repository.owner_id)
      end
    end

    # Returns `true` if the current user has write access to the current project.
    sig { returns(T::Boolean) }
    memoize def current_user_can_write_memex
      this_memex.viewer_can_write?(current_user)
    end

    # Returns `true` if all the fields being updated are project fields (e.g. not title, labels, assignees, etc)
    sig { returns(T::Boolean) }
    memoize def all_field_updates_are_project_fields
      # This method must be called only within the items controller
      T.bind(self, Memexes::ItemsController)
      self.column_list_for_item_update.all? { |c| c[:column]&.generic_type? }
    end

    sig { void }
    def require_these_items_writable
      # This method must be called only within the items controller
      T.bind(self, Memexes::ItemsController)

      these_items.each do |item|
        return render_404 unless item&.content

        if item.draft_issue?
          return render_404 unless item.content.writable_by?(current_user)
        else
          issue = item_content(item)
          # If not authorized to update the issue, we can still allow the update if
          # all the fields being updated are project fields (e.g. not title, labels, assignees, etc) which do not
          # require access to the issue itself, and if the user has write access to the project
          if FeatureFlag.vexi.enabled?(:projects_allow_editing_project_fields_for_archived_repos, current_user, default: false) && issue.repository.archived?
            next if all_field_updates_are_project_fields && current_user_can_write_memex
          end
          authorize_content(:issue, repo: issue.repository, action_to_authorize: "update")
        end
      end
    end

    def require_these_items_editable
      these_items.each do |item|
        return render_404 unless item&.content

        if item.draft_issue?
          render_404 unless item.content.writable_by?(current_user)
        else
          render_404 unless item_content(item).editable_by?(current_user)
        end
      end
    end

    def require_these_items_labelable
      these_items.each do |item|
        unless item_content(item).labelable_by?(actor: current_user)
          return render_json_error(error: "User does not have permission to label items", status: :forbidden,
            code: "Forbidden")
        end
      end
    end

    def require_these_items_milestone_settable
      these_items.each do |item|
        unless item_content(item).can_set_milestone?(current_user)
          return render_json_error(error: "User does not have permission to set milestones", status: :forbidden,
            code: "Forbidden")
        end
      end
    end

    def require_these_items_issue_type_settable
      return render_404 unless this_memex.owner&.issue_types_enabled?

      these_items.each do |item|
        return render_404 unless item.content

        if item.pull_request?
          return render_json_error(error: "Pull requests cannot have an issue type",
            status: :unprocessable_entity)
        end

        if item.draft_issue?
          return render_json_error(error: "Draft issues cannot have an issue type",
            status: :unprocessable_entity)
        end

        # Only do these issue type checks if we're updating a single item. If there are multiple items, then rely on the issue active record callback
        # to validate each of the items (allowing us to do a partial update of the batch)
        if these_items.one?
          content = item_content(item)

          unless content.repository.owner.organization?
            return render_json_error(code: "IssueTypesDisabledForRepoOwner", error: "Issue types are not available for user-owned repositories", status: :unprocessable_entity)
          end

          unless content.can_set_type?(actor: current_user)
            return render_json_error(error: "You do not have permission to set the issue type for this item", status: :forbidden,
              code: "Forbidden")
          end
        end
      end
    end

    def require_these_items_can_set_tracked_by(parents_param)
      return unless tracks_and_tracked_by_enabled?

      these_items.each do |item|
        next if item.draft_issue?

        add, remove = item.diff_tracked_by_values(item_content(item), parents_param, current_user)

        unless item_content(item).can_set_tracked_by?(actor: current_user, parent_issues: add + remove)
          render_json_error(
            error: "User does not have permission to set tracked by to this item or the parent item",
            status: :forbidden,
            code: "Forbidden",
          )
        end
      end
    end

    def require_these_items_can_add_sub_issues(parent_issue_id)
      return unless Issue.find_by(id: parent_issue_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

      child_issue = these_items.detect { |item| item.issue? }
      return unless child_issue

      # these_items is already checked in require_these_items_writable, additionally,
      # all items being edited will have the same parent_issue_id, therefore, we only need to check once
      # that a user can access the new parent issue.
      unless item_content(child_issue).can_add_sub_issue?(actor: current_user, parent_issue_id: parent_issue_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        render_json_error(
          error: "User does not have permission to add sub-issues to this item",
          status: :forbidden,
          code: "Forbidden",
        )
      end
    end

    def require_these_items_have_issues_enabled
      these_items.each do |item|
        next if item.draft_issue?

        if item.content.is_a?(Issue) && !item_content(item).repository.has_issues?
          return render_json_error(error: "Content cannot be updated because issues are disabled for the repository",
            status: :unprocessable_entity)
        end
      end
    end

    def require_non_archived_these_items
      these_items.each do |item|
        if item.archived?
          return render_json_error(error: "This item is archived and cannot be modified.",
            status: :unprocessable_entity)
        end
      end
    end

    def require_non_draft_issue_these_items
      these_items.each do |item| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        if item&.draft_issue?
          render_json_error(error: "A content type of Issue or PullRequest is required",
            status: :unprocessable_entity)
        end
      end
    end

    def any_draft_issues?
      these_items&.any? { |item| item.draft_issue? } # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    def item_content(item = this_item)
      return if underscored_params[:content_type] == DraftIssue.name
      return if item.nil?
      item.content.is_a?(PullRequest) ? item.content.issue : item.content # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    def require_actor_can_add_assignees
      these_items.each do |item|
        next if item.draft_issue?

        unless item_content(item).assignable_by?(actor: current_user)
          render_json_error(error: "User does not have permission to assign users", status: :forbidden,
            code: "Forbidden")
        end
      end
    end

    def require_actor_can_read_issue_suggestions
      return render_404 if these_items.empty?

      these_items.each do |item|
        return render_404 unless item&.content
        issue = item_content(item)
        return render_404 unless issue&.repository
        return render_404 unless issue.repository.readable_by?(current_user)
        return render_404 if current_user.blocked_by?(issue.repository.owner_id)

        authorize_content(:issue, repo: issue.repository, action_to_authorize: "update") do |authorization|
          if authorization.first_error.kind_of?(ContentAuthorizationError::RepoArchived)
            render_json_error(code: "RepoArchived", error: authorization.first_error.message, status: :not_found)
          else
            render_json_error(error: authorization.first_error.message, status: :not_found)
          end
        end
      end
    end
  end
end
