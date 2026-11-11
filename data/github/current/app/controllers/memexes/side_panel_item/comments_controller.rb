# typed: true
# frozen_string_literal: true

class Memexes::SidePanelItem::CommentsController < Memexes::Controller
  include MemexesHelper
  include HierarchyHelper
  include Memexes::MemexSidePanelItemDependency
  include ApplicationController::VerifiedFetchDependency

  # cluster dependencies analysis will be enabled for this non-get requests
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Memexes::SidePanelItem::CommentsController#create",
  ].freeze

  # global critical dependencies, needed for all actions
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Collab

  # Any error types defined by MemexSidePanel::Item should be handled here
  rescue_from MemexSidePanel::Item::NotFoundError, with: :not_found_error
  rescue_from MemexSidePanel::Item::UnsupportedError, with: :unsupported_method_error
  rescue_from MemexSidePanel::Item::PermissionError, with: :incorrect_permissions_error
  rescue_from MemexSidePanel::Item::InvalidParamsError, with: :invalid_params_error

  before_action :require_this_memex
  before_action :user_has_read_access
  before_action :user_has_item_read_access

  allow_verified_fetch only: [:create]

  depends_on_clusters ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Iam,
    ApplicationRecord::Repositories, only: [:create]

  depends_on_clusters ApplicationRecord::Permissions,
    ApplicationRecord::Spokes,
    ApplicationRecord::Notify,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::Mysql2, only: [:create], optional: true

  def create
    render json: T.must(this_item).comment(underscored_params.require(:comment),
      update_state: underscored_params[:update_state],
      state_reason: underscored_params[:state_reason],
    )
  end

  private

  # Safe because :require_this_memex and :user_has_item_read_access ensures this_memex and this_item are not nil
  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless this_memex && this_item # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    T.must(this_item).resource_for_conditional_access
  end

  # Safe because :require_this_memex and :user_has_item_read_access ensures this_memex and this_item are not nil
  def target_for_conditional_access
    return :no_target_for_conditional_access unless this_memex && this_item # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    T.must(this_item).target_for_conditional_access
  end

  def user_has_item_read_access
    render_404 unless this_item&.viewer_can_read?
  end
end
