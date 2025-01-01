# typed: true
# frozen_string_literal: true

class Dashboards::OverviewController < ApplicationController
  # needs investigation for protected organization access
  skip_before_action :perform_conditional_access_checks # rubocop:todo GitHub/DoNotSkipCapBeforeAction

  before_action :enterprise_required

  rescue_from NameError, with: :render_404

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:count]

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index]

  stylesheet_bundle :insights

  def index
    graphs = [
      { heading: "Pull Requests", metrics: [MetricQuery::PullRequestsCreated, MetricQuery::PullRequestsMerged] },
      { heading: "Issues", metrics: [MetricQuery::IssuesCreated, MetricQuery::IssuesClosed] },
      { heading: "Issue Comments", metrics: [MetricQuery::IssueCommentsCreated] },
      { heading: "Repositories", metrics: [MetricQuery::RepositoriesCreated] },
      { heading: "Users", metrics: [MetricQuery::UsersCreated] },
      { heading: "Organizations", metrics: [MetricQuery::OrganizationsCreated] },
      { heading: "Teams", metrics: [MetricQuery::TeamsCreated] },
    ]

    render "dashboards/overview/index", locals: {
      graphs: graphs,
      period: period,
    }
  end

  def count # rubocop:todo GitHub/UseRestfulActions
    render json: MetricSet.build(params[:metrics], timespan: timespan)
  end

  private

  def period # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @period ||= timespan.period
  end

  def timespan # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @timespan ||= MetricTimespan.for(params.fetch(:period, :week)).new
  end
end
