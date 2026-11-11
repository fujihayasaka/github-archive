# typed: true
# frozen_string_literal: true

class Repositories::PartialsController < AbstractRepositoryController
  include ApplicationController::PartialRenderWithLayoutDependency
  include Repos::DataRouterDependency
  include ApplicationController::VerifiedFetchDependency
  include JsonDependency

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = ["Repositories::PartialsController#file_tree"].freeze
  CONDITIONAL_ACCESS_BYPASS_PUBLIC_REPO_ACTIONS = %w(layout file_tree_layout header sidebar file_tree sidebar_about).freeze

  layout false

  before_action :no_cache, :set_html_safe_nonce
  before_action :parse_json_params, only: [:file_tree]
  before_action :require_codeview_sidebar_feature_flag, only: [:sidebar_about]

  depends_on_clusters(
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
  )

  depends_on_clusters(
    ApplicationRecord::Billing,
    ApplicationRecord::Spokes,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::Ballast,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Notify,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Pages,
    ApplicationRecord::SecurityProductsEnablement,
    ApplicationRecord::ActionsEnvironments,
    optional: true,
    only: [:header, :sidebar]
  )

  depends_on_clusters(
    ApplicationRecord::Mysql2,
    optional: true,
    only: [:sidebar_about]
  )

  depends_on_clusters(
    ApplicationRecord::RepositoriesPushes,
    only: [:layout]
  )

  allow_verified_fetch only: [:file_tree]

  rate_limit_requests \
    max: GitHub::RateLimitedRequest::DEFAULT_RATE_LIMIT_MAX,
    ttl: GitHub::RateLimitedRequest::DEFAULT_RATE_LIMIT_TTL,
    if: :should_rate_limit_request?,
    key: :default_rate_limit_key

  def layout # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        render_react_json(
          payload: layout_route_payload
        )
      end
    end
  end

  def file_tree_layout # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        render_react_json(
          payload: file_tree_layout_payload
        )
      end
    end
  end

  def file_tree # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        render_react_json(
          payload: file_tree_payload(
            branch: params[:branch],
            start: params[:start],
            stop: params[:stop]
          )
        )
      end
    end
  end

  def header # rubocop:todo GitHub/UseRestfulActions
    view = create_view_model(
      Files::OverviewView,
      user: current_user,
      repository: current_repository,
      commit: current_commit,
      page_title: page_title,
      source_url: request.url,
      location: controller_name + "#" + action_name,
      cap_view_filter: cap_view_filter
    )

    payload = Repos::CodeViewPayloads::OverviewHeaderPayload.new(
      -> { overview_header_partial(repo: current_repository, cap_view_filter: cap_view_filter, view: view) }
    )

    respond_to do |format|
      format.json do
        render_rails_partial_payload(payload: payload)
      end
    end
  end

  def sidebar # rubocop:todo GitHub/UseRestfulActions
    view = create_view_model(
      Files::OverviewView,
      user: current_user,
      repository: current_repository,
      commit: current_commit,
      page_title: page_title,
      source_url: request.url,
      location: controller_name + "#" + action_name,
      cap_view_filter: cap_view_filter
    )

    payload = Repos::CodeViewPayloads::OverviewSidebarPayload.new(
      -> { overview_sidebar_partial(commit: current_commit, view: view) }
    )

    respond_to do |format|
      format.json do
        render_rails_partial_payload(payload: payload)
      end
    end
  end

  def sidebar_about # rubocop:todo GitHub/UseRestfulActions
    view = create_view_model(
      Files::OverviewView,
      user: current_user,
      repository: current_repository,
      commit: current_commit,
      page_title: page_title,
      source_url: request.url,
      location: controller_name + "#" + action_name,
      cap_view_filter: cap_view_filter
    )

    respond_to do |format|
      format.json do
        payload = GitHub.dogstats.distribution_time("repos.payload.time", tags: ["payload_type: codeview_sidebar_about"]) do
          sidebar = Repos::CodeViewSidebar::CodeViewSidebar.new(view_model: view, current_user: current_user, current_repository: current_repository)
          sidebar.about_payload.serialize
        end
        render json: payload
      end
    end
  end

  private

  def no_cache
    expires_now
  end

  def page_title
    "#{current_repository.name_with_display_owner}"
  end

  def should_rate_limit_request?
    !logged_in?
  end

  def set_html_safe_nonce
    response.headers["X-HTML-Safe"] = html_safe_nonce
  end

  def require_codeview_sidebar_feature_flag
    unless FeatureFlag.vexi.enabled?(:react_data_router_code_view_sidebar, current_user, default: false)
      head :not_found
    end
  end
end
