# typed: true
# frozen_string_literal: true

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
    only: [:index, :show, :dashboard, :dashboard_issues, :dashboard_pulls, :deferred, :dashboard_deferred, :dashboard_issues_deferred, :dashboard_pulls_deferred]

  def index
    # ideally we would only be returning the payload for the
    # respective child route. currently we are returning the
    # entire payload for all leaf routes, as well as the parent.
    render_react_app(
      payload: {
        **layout_route_payload,
        **index_route_payload
      },
      data_router_enabled: true
    )
  end

  def show
    param = params[:param]
    if param == "3"
      render_404
    else
      render_react_app(
        payload: {
          **layout_route_payload,
          **show_route_payload(param)
        },
        data_router_enabled: true
      )
    end
  end

  def dashboard # rubocop:todo GitHub/UseRestfulActions
    render_react_app(
      payload: {
        **layout_route_payload,
        **dashboard_route_payload,
      },
      data_router_enabled: true
    )
  end

  def dashboard_issues # rubocop:todo GitHub/UseRestfulActions
    render_react_app(
      payload: {
        **layout_route_payload,
        **dashboard_route_payload,
        **dashboard_issues_route_payload,
      },
      data_router_enabled: true
    )
  end

  def dashboard_pulls # rubocop:todo GitHub/UseRestfulActions
    render_react_app(
      payload: {
        **layout_route_payload,
        **dashboard_route_payload,
        **dashboard_pulls_route_payload,
      },
      data_router_enabled: true
    )
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

  def layout_route_payload
    {
      reactSandboxFutureLayoutRoute: {
        mainQuery: {
          someField: "A message from Rails!",
          serverTime: Time.now,
          tabCounts: { "1": 10, "2": 20, "3": 30 }
        },
      }
    }
  end

  def index_route_payload
    {
      reactSandboxFutureIndexRoute: {
          mainQuery: {
            someField: "A message from Rails for index",
            serverTime: Time.now,
          },
          title: "ReactSandboxFuture Index",
        }
    }
  end

  def show_route_payload(param)
    {
      reactSandboxFutureIdRoute: {
        mainQuery: {
          someField: "A message from Rails for show #{param}",
          serverTime: Time.now,
        },
        title: "ReactSandboxFuture Show (#{param})",
      }
    }
  end

  def dashboard_route_payload
    {
      reactSandboxFutureDashboardRoute: {
        mainQuery: {
          user: current_user.display_login
        },
        title: "ReactSandboxFuture Dashboard",
      }
    }
  end

  def dashboard_issues_route_payload
    title = "ReactSandboxFuture Dashboard Issues"
    if params[:state]
      title += " (#{params[:state]})"
    end

    {
      reactSandboxFutureDashboardIssuesRoute: {
        mainQuery: {
          open: Issue.where(user_id: current_user.id, has_pull_request: false, state: "open").count,
          closed: Issue.where(user_id: current_user.id,  has_pull_request: false, state: "closed").count
        },
        title: title,
      }
    }
  end

  def dashboard_pulls_route_payload
    {
      reactSandboxFutureDashboardPullsRoute: {
        mainQuery: {
          open:  Issue.where(user_id: current_user.id, has_pull_request: true, state: "open").count,
          closed:  Issue.where(user_id: current_user.id, has_pull_request: true, state: "closed").count
        },
        title: "ReactSandboxFuture Dashboard Pulls",
      }
    }
  end

  def deferred_payload(param)
    {
      someDeferredField: "Mocked deferred from params: id=#{param}",
      deferredLoadedAt: Time.now
    }
  end

  def deferred_dashboard_payload
    {
      tabCounts: {
        openIssues: Issue.where(user_id: current_user.id, has_pull_request: false, state: "open").count,
        openPulls: Issue.where(user_id: current_user.id, has_pull_request: true, state: "open").count,
      }
    }
  end

  def deferred_dashboard_issues_payload
    state = params[:state] || :open
    {
      issues: Issue.where(user_id: current_user.id, has_pull_request: false, state: state).limit(10).map do |issue|
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
      pulls: Issue.where(user_id: current_user.id, has_pull_request: true, state: state).limit(10).map do |issue|
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
    render_404 unless GitHub.flipper[:react_sandbox].enabled?(current_user)
  end
end
