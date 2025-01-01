# typed: strict
# frozen_string_literal: true

class Copilot::PullRequestReviewBannersController < AbstractRepositoryController

  include ApplicationController::VerifiedFetchDependency
  include CopilotAuthHelper
  include ReactHelper

  before_action :require_feature
  before_action :require_xhr
  before_action :login_required
  before_action :require_readable_head_repo
  before_action :set_default_format, only: :show
  before_action :require_websocket_channel, only: :show

  allow_verified_fetch only: [:create, :destroy]

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    only: [:show]

  sig { void }
  def show
    respond_to do |format|
      format.json do
        show_banner = PullRequests::Copilot::PullRequestReviewBannerComponent.render?(viewer: current_user,
          copilot_user: current_copilot_user, pull_request: pull_request)
        json = show_banner ? react_props.merge({ render: true }) : { render: false }
        render json: json
      end
      format.html do
        stats.record_render("compare/copilot_review_banner") do
          render_react_partial name: "copilot-pr-review-banner", props: react_props, ssr: false
        end
      end
    end
  end

  sig { void }
  def create
    instrument_banner_open
    head :ok
  end

  sig { void }
  def destroy
    instrument_banner_dismiss
    head :ok
  end

  private

  sig { returns T::Hash[Symbol, T.untyped] }
  def react_props
    props = react_copilot_api_props.merge(
      pull_request.present? ? react_props_for_pull_request : react_props_for_comparison
    ).merge(optional_react_props)
    props[:signedWebsocketChannel] = websocket_channel
    props
  end

  sig { returns T::Hash[Symbol, T.untyped] }
  def optional_react_props
    props = {}

    thread_name = params[:thread_name]
    if thread_name.present?
      props[:threadName] = thread_name
    end

    location = params[:location]
    if location.present?
      props[:location] = location
    end

    files_excluded = params[:files_excluded]
    if files_excluded.present?
      props[:filesExcluded] = files_excluded
    end

    props
  end

  sig { returns T.nilable(String) }
  memoize def websocket_channel
    return params[:channel] if params[:channel].present?
    GitHub::WebSocket::Channels.signed_pull_request(pull_request) if pull_request
  end

  sig { void }
  def require_websocket_channel
    head(:bad_request) if websocket_channel.blank?
  end

  sig { returns T::Hash[Symbol, T.untyped] }
  def react_props_for_comparison
    base_repo_id = current_repository.id
    head_repo_id = head_repository&.id || base_repo_id

    {
      baseRevision: params[:base_sha],
      headRevision: params[:head_sha],
      baseRepoId: base_repo_id,
      headRepoId: head_repo_id,
      analyticsPath: copilot_pull_request_review_banner_path(params[:user_id], params[:repository],
        base_sha: params[:base_sha], head_sha: params[:head_sha], head_repo_id: params[:head_repo_id]),
    }
  end

  sig { returns T::Hash[Symbol, T.untyped] }
  def react_props_for_pull_request
    {
      pullRequestId: params[:pull_request_node_id].presence || pull_request&.global_relay_id,
      analyticsPath: copilot_pull_request_review_banner_path(params[:user_id], params[:repository],
        pull_request_node_id: params[:pull_request_node_id], pull_request_id: params[:pull_request_id]),
    }
  end

  sig { returns T::Hash[Symbol, T.untyped] }
  def react_copilot_api_props
    {
      apiURL: copilot_api_url,
      ssoOrganizations: sso_organizations,
    }
  end

  sig { returns(String) }
  memoize def copilot_api_url
    Copilot::SKUIsolation.for_user(current_user).api.endpoint
  end

  sig { returns PageStats }
  def stats
    PageStats.new(controller_name: controller_name, action_name: action_name, viewer: current_user, pjax: pjax?)
  end

  sig { void }
  def require_feature
    render_404 unless user_feature_enabled?(:copilot_reviews)
  end

  sig { void }
  def require_xhr
    head(:not_acceptable) unless request&.xhr?
  end

  sig { returns T.nilable(Repository) }
  memoize def head_repository
    head_repo_id = params[:head_repo_id]
    return if head_repo_id.blank?

    Repositories::Public.find_active(head_repo_id)
  end

  sig { void }
  def require_readable_head_repo
    if params[:head_repo_id].present?
      render_404 unless head_repository&.readable_by?(current_user)
    end
  end

  sig { void }
  def instrument_banner_open
    current_user = T.must_because(self.current_user) { "#login_required before_action ensures non-nil" }
    round_trip_time_ms = params[:round_trip_time_ms]
    GlobalInstrumenter.instrument("copilot.pull_request.pre_review.open_chat",
      analytics_tracking_id: current_user.analytics_tracking_id,
      round_trip_time_ms: round_trip_time_ms.present? ? round_trip_time_ms.to_i : nil,
    )
  end

  # Valid enum values from lib/hydro/schemas/github/copilot/v2/copilot_pull_request_pre_review_banner_dismiss_pb.rb
  UNKNOWN_DISMISS_BUTTON = "UNKNOWN"
  BANNER_DISMISS_BUTTONS = T.let([UNKNOWN_DISMISS_BUTTON, "X", "DISMISS"].freeze, T::Array[String])

  sig { void }
  def instrument_banner_dismiss
    dismiss_button = params[:button]
    unless BANNER_DISMISS_BUTTONS.include?(dismiss_button)
      dismiss_button = UNKNOWN_DISMISS_BUTTON
    end
    current_user = T.must_because(self.current_user) { "#login_required before_action ensures non-nil" }
    GlobalInstrumenter.instrument("copilot.pull_request.pre_review.banner_dismiss",
      analytics_tracking_id: current_user.analytics_tracking_id,
      error: params[:error].to_s.downcase == "true",
      dismiss_button: dismiss_button,
    )
  end

  sig { returns T.nilable(PullRequest) }
  memoize def pull_request
    if params[:pull_request_id].present?
      pull = PullRequest.find(params[:pull_request_id])
      pull if pull.readable_by?(current_user)
    elsif params[:pull_request_node_id].present?
      begin
        typed_object_from_id([Platform::Objects::PullRequest], params[:pull_request_node_id])
      rescue Platform::Errors::NotFound
        nil
      end
    end
  end

  sig { void }
  def set_default_format
    request&.format = :html if params[:format].blank?
  end
end
