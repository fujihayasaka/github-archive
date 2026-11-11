# typed: true
# frozen_string_literal: true

class Repositories::PartialsController < AbstractRepositoryController
  include ApplicationController::PartialRenderWithLayoutDependency
  include Repos::DataRouterDependency
  include ApplicationController::VerifiedFetchDependency
  include JsonDependency
  include Registry::QueryHelper
  include ControllerMethods::Codespaces

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = ["Repositories::PartialsController#file_tree"].freeze
  CONDITIONAL_ACCESS_BYPASS_PUBLIC_REPO_ACTIONS = %w(layout file_tree_layout header sidebar file_tree sidebar_all sidebar_about sidebar_releases sidebar_sponsors sidebar_deployments sidebar_packages sidebar_used_by sidebar_contributors sidebar_languages sidebar_suggested_workflows sidebar_citation sidebar_cta).freeze

  layout false

  before_action :no_cache, :set_html_safe_nonce
  before_action :parse_json_params, only: [:file_tree]
  before_action :require_codeview_sidebar_feature_flag, only: [:sidebar_all, :sidebar_about, :sidebar_releases, :sidebar_sponsors, :sidebar_deployments, :sidebar_packages, :sidebar_used_by, :sidebar_contributors, :sidebar_languages, :sidebar_suggested_workflows, :sidebar_citation, :sidebar_cta]
  before_action :require_combined_sidebar_payload_feature_flag, only: [:sidebar_all]
  before_action :require_codeview_header_feature_flag, only: [:header_lists]

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
    ApplicationRecord::Authnd,
    optional: true,
    only: [:header, :sidebar, :sidebar_all, :sidebar_about, :sidebar_releases, :sidebar_sponsors, :sidebar_deployments, :sidebar_packages, :sidebar_used_by, :sidebar_contributors, :sidebar_languages, :sidebar_suggested_workflows, :sidebar_citation, :sidebar_cta, :header_lists]
  )

  depends_on_clusters(
    ApplicationRecord::Authnd,
    only: [:sidebar_all, :sidebar_about, :sidebar_releases, :sidebar_sponsors, :sidebar_packages, :sidebar_used_by, :sidebar_contributors, :sidebar_languages, :sidebar_suggested_workflows, :sidebar_cta, :header, :header_lists]
  )

  depends_on_clusters(
    ApplicationRecord::RepositoriesPushes,
    only: [:layout],
  )

  depends_on_clusters(
    ApplicationRecord::Copilot,
    optional: true,
    only: [:layout],
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

  def header_lists # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        payload = GitHub.dogstats.distribution_time("repos.payload.time", tags: ["payload_type: codeview_header_lists"]) do
          header = Repos::CodeViewHeader::CodeViewHeader.new(view_model: nil, current_user: current_user, current_repository: current_repository)
          header.user_lists_payload.serialize
        end
        render json: payload
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
          sidebar = Repos::CodeViewSidebar::CodeViewSidebar.new(
            view_model: view,
            current_user: current_user,
            current_repository: current_repository,
          )
          sidebar_data = sidebar.about_payload.serialize

          if Repos::CodeViewHeader.enabled?(current_user)
            header = Repos::CodeViewHeader::CodeViewHeader.new(
              view_model: view,
              current_user: current_user,
              current_repository: current_repository,
            )

            header_data = header.header_payload.serialize
            sidebar_data.merge(header_data)
          else
            sidebar_data
          end
        end
        render json: payload
      end
    end
  end

  def sidebar_releases # rubocop:todo GitHub/UseRestfulActions
    render_sidebar_section("codeview_sidebar_releases") { |s| s.releases_payload }
  end

  def sidebar_sponsors # rubocop:todo GitHub/UseRestfulActions
    render_sidebar_section("codeview_sidebar_sponsors") { |s| s.sponsors_payload }
  end

  def sidebar_deployments # rubocop:todo GitHub/UseRestfulActions
    hint_env_names = Array(params[:environments]).map(&:to_s).first(4).presence
    render_sidebar_section("codeview_sidebar_deployments") { |s| s.deployments_payload(hint_env_names: hint_env_names) }
  end

  def sidebar_packages # rubocop:todo GitHub/UseRestfulActions
    render_sidebar_section("codeview_sidebar_packages") { |s| s.packages_payload }
  end

  def sidebar_used_by # rubocop:todo GitHub/UseRestfulActions
    render_sidebar_section("codeview_sidebar_used_by") { |s| s.used_by_payload }
  end

  def sidebar_contributors # rubocop:todo GitHub/UseRestfulActions
    render_sidebar_section("codeview_sidebar_contributors") { |s| s.contributors_payload }
  end

  def sidebar_languages # rubocop:todo GitHub/UseRestfulActions
    render_sidebar_section("codeview_sidebar_languages") { |s| s.languages_payload }
  end

  def sidebar_suggested_workflows # rubocop:todo GitHub/UseRestfulActions
    render_sidebar_section("codeview_sidebar_suggested_workflows") { |s| s.suggested_workflows_payload }
  end

  def sidebar_citation # rubocop:todo GitHub/UseRestfulActions
    render_sidebar_section("codeview_sidebar_citation") { |s| s.citation_payload }
  end

  def sidebar_cta # rubocop:todo GitHub/UseRestfulActions
    render_sidebar_section("codeview_sidebar_cta") { |s| s.cta_payload }
  end

  # Returns a single combined payload for lazy-loaded sidebar sections
  def sidebar_all # rubocop:todo GitHub/UseRestfulActions
    hint_env_names = Array(params[:environments]).map(&:to_s).first(4).presence

    respond_to do |format|
      format.json do
        view = create_view_model(
          Files::OverviewView,
          user: current_user,
          repository: current_repository,
          commit: current_commit,
          page_title: page_title,
          source_url: request.url,
          location: controller_name + "#" + action_name,
          cap_view_filter: cap_view_filter,
        )

        payload = GitHub.dogstats.distribution_time("repos.payload.time", tags: ["payload_type: codeview_sidebar_all"]) do
          sidebar = Repos::CodeViewSidebar::CodeViewSidebar.new(
            view_model: view,
            current_user: current_user,
            current_repository: current_repository,
            user_session: user_session,
          )
          sidebar.full_sidebar_payload(hint_env_names: hint_env_names).serialize
        end

        render json: payload
      rescue GitHub::DatabaseQueryDisabler::DatabaseDisabledError
        render json: nil
      rescue StandardError => e
        Failbot.report(e, app: "code_view_sidebar_all")
        head :internal_server_error
      end
    end
  end

  private

  def render_sidebar_section(metric_tag, &block)
    respond_to do |format|
      format.json do
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

        payload = GitHub.dogstats.distribution_time("repos.payload.time", tags: ["payload_type: #{metric_tag}"]) do
          sidebar = Repos::CodeViewSidebar::CodeViewSidebar.new(
            view_model: view,
            current_user: current_user,
            current_repository: current_repository,
            user_session: user_session,
          )
          block.call(sidebar)&.serialize
        end

        render json: payload
      rescue GitHub::DatabaseQueryDisabler::DatabaseDisabledError
        render json: nil
      rescue StandardError => e
        Failbot.report(e, app: "code_view_sidebar_section")
        head :internal_server_error
      end
    end
  end

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
    unless Repos::CodeViewSidebar.enabled?(current_user)
      head :not_found
    end
  end

  def require_combined_sidebar_payload_feature_flag
    unless Repos::CodeViewSidebar.combined_payload_enabled?(current_user)
      head :not_found
    end
  end

  def route_supports_advisory_workspaces?
    case action_name
    when "layout", "file_tree", "file_tree_layout", "sidebar_about", "sidebar_all", "header", "sidebar"
      true
    else
      false
    end
  end

  def require_codeview_header_feature_flag
    unless Repos::CodeViewHeader.enabled?(current_user)
      head :not_found
    end
  end
end
