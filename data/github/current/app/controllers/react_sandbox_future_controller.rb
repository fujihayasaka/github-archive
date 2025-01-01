# rubocop:disable GitHub/UseRestfulActions
# typed: true
# frozen_string_literal: true

require "react_payload"

class ReactSandboxFutureController < ApplicationController
  before_action :require_feature_flags
  before_action :login_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Ballast,
    ApplicationRecord::IssuesPullRequests,
    only: [:layout, :index, :show, :client_error,  :dashboard, :dashboard_issues, :dashboard_pulls, :deferred, :dashboard_deferred, :dashboard_issues_deferred, :dashboard_pulls_deferred]

  class ShowPayload < ReactPayload::Base
    def route_id
      "reactSandboxFutureIdRoute"
    end

    sig { params(message: String).void }
    def initialize(message)
      @message = message
      @server_time = Time.now
    end

    def payload
      {
        someField: @message,
        serverTime: @server_time,
      }
    end
  end

  class LayoutPayload < ReactPayload::Base
    def route_id
      "reactSandboxFutureLayoutRoute"
    end

    sig { params(message: String, tab_counts: T::Hash[String, Integer]).void }
    def initialize(message, tab_counts)
      @message = message
      @server_time = Time.now
      @tab_counts = tab_counts
    end

    def payload
      {
        someField:  @message,
        serverTime: @server_time,
        tabCounts: @tab_counts
      }
    end
  end

  class IndexPayload < ReactPayload::Base
    def route_id
      "reactSandboxFutureIndexRoute"
    end

    sig { params(message: String, protobuf_date: Google::Protobuf::Timestamp).void }
    def initialize(message, protobuf_date)
      @message = message
      @server_time = Time.now
      @protobuf_date = protobuf_date
    end

    def payload
      {
        someField:  @message,
        serverTime: @server_time,
        protobufDate: @protobuf_date
      }
    end
  end

  class DashboardPayload < ReactPayload::Base
    def route_id
      "reactSandboxFutureDashboardRoute"
    end

    sig { params(user: String).void }
    def initialize(user)
      @user = user
    end

    def payload
      {
        user: @user,
      }
    end
  end

  class DashboardIssuesPayload < ReactPayload::Base
    def route_id
      "reactSandboxFutureDashboardIssuesRoute"
    end

    sig { params(open: Integer, closed: Integer).void }
    def initialize(open, closed)
      @open = open
      @closed = closed
    end

    def payload
      {
        open: @open,
        closed: @closed,
      }
    end
  end

  class DashboardPullsPayload < ReactPayload::Base
    def route_id
      "reactSandboxFutureDashboardPullsRoute"
    end

    sig { params(open: Integer, closed: Integer).void }
    def initialize(open, closed)
      @open = open
      @closed = closed
    end

    def payload
      {
        open: @open,
        closed: @closed,
        feedbackUrl: "https://github.com"
      }
    end
  end

  class DashboardDiscussionsPayload < ReactPayload::Base
    def route_id
      "reactSandboxFutureDashboardDiscussionsRoute"
    end

    sig { params(open: Integer, closed: Integer).void }
    def initialize(open, closed)
      @open = open
      @closed = closed
    end

    def payload
      {
        open: @open,
        closed: @closed,
      }
    end
  end

  class ClientErrorPayload < ReactPayload::Base
    def route_id
      "reactSandboxFutureClientErrorRoute"
    end

    sig { params(message: String).void }
    def initialize(message)
      @message = message
    end

    def payload
      { message: @message }
    end
  end

  def index
    title = "ReactSandboxFuture Index"
    payload = IndexPayload.new(
      "A message from Rails for index",
      Google::Protobuf::Timestamp.new(seconds: Time.parse("2024-06-12T00:15:18.972754Z").to_i)
    )
    respond_to do |format|
      format.html do
        layout_payload = LayoutPayload.new(layout_message, tab_counts)
        render_react_html(title: title, payload: payload, nested_payloads: [layout_payload])
      end
      format.json do
        render_react_json(title: title, payload: payload)
      end
    end
  end

  def layout # rubocop:todo GitHub/UseRestfulActions
    payload = LayoutPayload.new(layout_message, tab_counts)
    respond_to do |format|
      format.json do
        render_react_json(payload: payload)
      end
    end
  end

  def show
    param = params[:param]
    if param == "3"
      render_404
    else
      title = "ReactSandboxFuture Show (#{param})"
      payload = ShowPayload.new("A message from Rails for show #{param}")
      respond_to do |format|
        format.html do
          layout_payload = LayoutPayload.new(layout_message, tab_counts)
          render_react_html(title: title, payload: payload, nested_payloads: [layout_payload])
        end
        format.json do
          render_react_json(title: title, payload: payload)
        end
      end
    end
  end

  def client_error
    payload = ClientErrorPayload.new("Stubbed client_error action from controller")
    respond_with_react(
      title: "ReactSandboxFuture Client Error",
      payload: payload,
      nested_payloads: -> { [
        LayoutPayload.new(layout_message, tab_counts)
      ]
      },
    )
  end

  def dashboard # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        payload = DashboardPayload.new(current_user.display_login)
        render_react_json(payload: payload)
      end
    end
  end

  def dashboard_issues # rubocop:todo GitHub/UseRestfulActions
    title = "ReactSandboxFuture Dashboard Issues"
    if params[:state]
      title += " (#{params[:state]})"
    end

    payload = DashboardIssuesPayload.new(
      Issue.where(user_id: current_user.id, has_pull_request: false, state: "open").count, # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      Issue.where(user_id: current_user.id,  has_pull_request: false, state: "closed").count # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    )
    respond_to do |format|
      format.html do
        layout_payload = LayoutPayload.new(layout_message, tab_counts)
        dashboard_payload = DashboardPayload.new(current_user.display_login)
        render_react_html(title: title, payload: payload, nested_payloads: [layout_payload, dashboard_payload])
      end
      format.json do
        render_react_json(title: title, payload: payload)
      end
    end
  end

  def dashboard_pulls # rubocop:todo GitHub/UseRestfulActions
    title = "ReactSandboxFuture Dashboard Pulls"
    payload = DashboardPullsPayload.new(
      Issue.where(user_id: current_user.id, has_pull_request: true, state: "open").count, # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      Issue.where(user_id: current_user.id, has_pull_request: true, state: "closed").count # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    )
    respond_to do |format|
      format.html do
        layout_payload = LayoutPayload.new(layout_message, tab_counts)
        dashboard_payload = DashboardPayload.new(current_user.display_login)
        render_react_html(title: title, payload: payload, nested_payloads: [layout_payload, dashboard_payload])
      end
      format.json do
        render_react_json(title: title, payload: payload)
      end
    end
  end

  def dashboard_discussions
    title = "ReactSandboxFuture Dashboard Discussions"
    payload = DashboardDiscussionsPayload.new(30, 1)
    respond_to do |format|
      format.html do
        layout_payload = LayoutPayload.new(layout_message, tab_counts)
        dashboard_payload = DashboardPayload.new(current_user.display_login)
        render_react_html(title: title, payload: payload, nested_payloads: [layout_payload, dashboard_payload])
      end
      format.json do
        render_react_json(title: title, payload: payload)
      end
    end
  end

  def deferred # rubocop:todo GitHub/UseRestfulActions
    # simulate some latency, this will take 1-3 seconds
    sleep 1 + (2 * rand)
    param = params[:param]
    payload = deferred_payload(param)

    render json: payload
  end

  def dashboard_deferred # rubocop:todo GitHub/UseRestfulActions
    # simulate some latency, this will take 1-3 seconds
    sleep 1 + (2 * rand)
    payload = deferred_dashboard_payload

    render json: payload
  end

  def dashboard_issues_deferred # rubocop:todo GitHub/UseRestfulActions
    sleep 1 + (2 * rand)
    render json: deferred_dashboard_issues_payload
  end

  def dashboard_pulls_deferred # rubocop:todo GitHub/UseRestfulActions
    sleep 1 + (2 * rand)
    render json: deferred_dashboard_pulls_payload
  end

  private

  def layout_message
    "A message from Rails!"
  end

  def tab_counts
    { "1": 10, "2": 20, "3": 30 }
  end

  def deferred_payload(param)
    {
      someDeferredField: "Mocked deferred from params: id=#{param}",
      deferredLoadedAt: Time.now
    }
  end

  def deferred_dashboard_payload
    data = {
      tabCounts: {
        openIssues: Issue.where(user_id: current_user.id, has_pull_request: false, state: "open").count,
        openPulls: Issue.where(user_id: current_user.id, has_pull_request: true, state: "open").count,
      }
    }
    data[:tabCounts][:openDiscussions] = 3
    data
  end

  def deferred_dashboard_issues_payload
    state = params[:state] || :open
    {
      issues: Issue.where(user_id: current_user.id, has_pull_request: false, state: state).limit(10).map do |issue| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        {
          id: issue.id,
          title: issue.title,
          url: issue.url(include_host: false),
          state: issue.state
        }
      end
    }
  end

  def deferred_dashboard_pulls_payload
    state = params[:state] || :open
    {
      pulls: Issue.where(user_id: current_user.id, has_pull_request: true, state: state).limit(10).map do |issue| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        {
          id: issue.id,
          title: issue.title,
          url: issue.url(include_host: false),
          state: issue.state
        }
      end
    }
  end

  def set_default_nav_breadcrumb
    set_nav_breadcrumb ContextRegion::ReactSandboxFutureCrumb.new
  end

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def require_feature_flags
    render_404 unless FeatureFlag.vexi.enabled?(:react_sandbox, current_user, default: false)
  end

end
