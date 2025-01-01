# typed: true
# frozen_string_literal: true

class Memexes::SidePanelItemController < Memexes::Controller
  include MemexesHelper
  include HierarchyHelper
  include Memexes::MemexSidePanelItemDependency
  include ApplicationController::VerifiedFetchDependency

  # cluster dependencies analysis will be enabled for this non-get requests
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Memexes::SidePanelItemController#edit_comment",
    "Memexes::SidePanelItemController#update",
    "Memexes::SidePanelItemController#update_state",
    "Memexes::SidePanelItemController#update_reaction",
  ]

  # global critical dependencies, needed for all actions
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Collab,
    ApplicationRecord::Iam

  # Any error types defined by MemexSidePanel::Item should be handled here
  rescue_from MemexSidePanel::Item::NotFoundError, with: :not_found_error
  rescue_from MemexSidePanel::Item::UnsupportedError, with: :unsupported_method_error
  rescue_from MemexSidePanel::Item::PermissionError, with: :incorrect_permissions_error
  rescue_from MemexSidePanel::Item::InvalidParamsError, with: :invalid_params_error

  before_action :require_this_memex
  before_action :user_has_read_access
  before_action :user_has_item_read_access
  before_action :user_has_item_write_access, only: [:update, :update_state]

  around_action :instrument_tasklist_block_add_around_action, only: [:update]

  allow_verified_fetch only: [:edit_comment, :update, :update_state, :update_reaction]

  # Safe because :require_this_memex and :user_has_item_read_access ensures this_memex and this_item are not nil
  private def resource_for_conditional_access
    return :no_resource_for_conditional_access unless this_memex && this_item # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    T.must(this_item).resource_for_conditional_access
  end

  # Safe because :require_this_memex and :user_has_item_read_access ensures this_memex and this_item are not nil
  private def target_for_conditional_access
    return :no_target_for_conditional_access unless this_memex && this_item # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    T.must(this_item).target_for_conditional_access
  end

  depends_on_clusters ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories, only: [:show]
  depends_on_clusters ApplicationRecord::Iam,
    ApplicationRecord::Ballast,
    ApplicationRecord::Spokes,
    ApplicationRecord::Notify,
    ApplicationRecord::Mysql2, only: [:show], optional: true

  def show
    render(json: T.must(this_item).show(
      omit_comments: ActiveModel::Type::Boolean.new.cast(underscored_params[:omit_comments]),
      omit_capabilities: ActiveModel::Type::Boolean.new.cast(underscored_params[:omit_capabilities]))
    )
  end

  depends_on_clusters ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories, only: [:edit_comment]
  depends_on_clusters ApplicationRecord::Permissions,
    ApplicationRecord::Spokes,
    ApplicationRecord::Notify,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::Mysql2, only: [:edit_comment], optional: true

  def edit_comment # rubocop:todo GitHub/UseRestfulActions
    comment = T.must(this_item).edit_comment(
      underscored_params.require(:comment_id),
      underscored_params.require(:body)
    )
    return render_json_error(error: "Issue cannot be updated", status: :bad_request) unless comment
    render(json: comment)
  end

  depends_on_clusters ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories, only: [:update_state]
  depends_on_clusters ApplicationRecord::Permissions,
    ApplicationRecord::Spokes,
    ApplicationRecord::Notify,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::Mysql2, only: [:update_state], optional: true

  def update_state # rubocop:todo GitHub/UseRestfulActions
    ok = T.must(this_item).update_state(underscored_params[:state], state_reason: underscored_params[:state_reason])
    return head :no_content if ok
    render_json_error(error: "Issue state cannot be updated to #{underscored_params[:state]}", status: :bad_request)
  end

  depends_on_clusters ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories, only: [:update_reaction]
  depends_on_clusters ApplicationRecord::Spokes, only: [:update_reaction], optional: true

  def update_reaction # rubocop:todo GitHub/UseRestfulActions
    T.must(this_item).update_reaction(underscored_params.require(:command), underscored_params.require(:reaction),
      comment_id: underscored_params[:comment_id])
    head :no_content
  end

  depends_on_clusters ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories, only: [:update]
  depends_on_clusters ApplicationRecord::Permissions,
    ApplicationRecord::Ballast,
    ApplicationRecord::Spokes,
    ApplicationRecord::Notify,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::Mysql2, only: [:update], optional: true

  def update
    if underscored_params[:tasklist_blocks_operation]
      issue = this_item.try(:item)
      current_repo = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
        T.cast(Repositories.domain.by_id(underscored_params[:repository_id].to_i), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
      else
        Repository.find_by(id: underscored_params[:repository_id])
      end
      operation = TasklistBlocks::Operation.from(underscored_params[:tasklist_blocks_operation], current_repository: current_repo, current_user: current_user)
      return unless operation
      text = operation.call(underscored_params[:update][:body])
      underscored_params[:update][:body] = text

      instrument_tasklist_block_operation(operation: operation, actor: current_user, repository: current_repo, issue: issue)
    end

    if params[:tasklist_blocks_operation_tracker]
      operation_array = JSON.parse(params[:tasklist_blocks_operation_tracker])
      instrument_tasklist_block_md_to_ui_operation(operations: operation_array, actor: current_user, repository: current_repository, issue: issue)
    end

    render(json: T.must(this_item).update(underscored_params.require(:update)))
  end

  depends_on_clusters ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories, only: [:suggestions]
  depends_on_clusters ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Permissions, only: [:suggestions], optional: true
  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::Iam, only: [:suggestions], optional: true

  def suggestions # rubocop:todo GitHub/UseRestfulActions
    suggestion_type = underscored_params.require(:suggestions_type)
    suggestions = get_suggestions(suggestion_type, T.must(this_item).suggestions_target(suggestion_type))
    render(json: { suggestions: suggestions })
  end

  private

  def instrument_tasklist_block_add_around_action
    issue = this_item.try(:item)
    return yield unless issue

    tasklists_before = issue.body_result_tasklists.count
    yield
    tasklists_after = issue.body_result_tasklists.count

    tasklists_added = tasklists_after - tasklists_before
    if tasklists_added > 0
      repository = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
        Repositories.domain.by_id(underscored_params[:repository_id].to_i)
      else
        Repository.find_by(id: underscored_params[:repository_id])
      end
      tasklists_added.times do
        instrument_tasklist_block_add(actor: current_user, repository: repository, issue: issue)
      end
    end
  end

  def user_has_item_read_access
    render_404 unless this_item&.viewer_can_read?
  end

  # this is a lower fidelity check that those made in the SidePanelItemDependency for a more generalized check
  # for more granular checks, see the update methods in that module
  # this is also meant to check access to the item itself, not the memex columns of the item
  def user_has_item_write_access
    return render_404 unless this_item
    unless T.must(this_item).viewer_can_update?
      incorrect_permissions_error(StandardError.new("User does not have permission to update item"))
    end
  end
end
