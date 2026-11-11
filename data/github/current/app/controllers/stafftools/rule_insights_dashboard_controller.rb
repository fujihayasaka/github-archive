# typed: strict
# frozen_string_literal: true

require "react_payload"

class Stafftools::RuleInsightsDashboardController < StafftoolsController
  include Repos::Rules::Concerns::InsightsDashboard

  before_action :ensure_repo_exists
  before_action do
    T.bind(self, Stafftools::RuleInsightsDashboardController)
    rule_insights_dashboard_enabled(source: current_repository, user: current_user)
  end

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Memex,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::RepositoriesPushes, only: [:index]

  depends_on_clusters ApplicationRecord::Copilot, only: [:index], optional: true

  sig { returns(String) }
  def self.react_bundle_name
    "rule-insights-dashboard"
  end

  sig { void }
  def index
    branch = if params[:ref] == "all"
      nil
    elsif params[:ref].present?
      params[:ref]
    else
      current_repository.default_branch
    end

    respond_with_react(
      payload: StafftoolsDashboardRoutePayload.new(
        source: current_repository,
        user: current_user,
        filter: {
          branch: branch,
          ruleset_name: params[:ruleset],
          evaluate_status: params[:evaluate_status],
          created: params[:created],
        },
        insights_path: stafftools_repository_repository_rule_insights_path,
      ),
      nested_payloads: -> { [StafftoolsLayoutRoutePayload.new] },
      app_payload_generator: -> { { is_stafftools: true } },
      title: "Rule Insights Dashboard",
      layout: "layouts/stafftools/repository/overview",
      page_data: {
        selected_link: :repository_rule_insights_dashboard,
      },
    )
  end

  sig { void }
  def layout # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        render_react_json(payload: StafftoolsLayoutRoutePayload.new)
      end
    end
  end

  class StafftoolsDashboardRoutePayload < DashboardRoutePayload
    sig { override.returns(String) }
    def route_id
      "stafftoolsDashboardRoute"
    end
  end

  class StafftoolsLayoutRoutePayload < LayoutRoutePayload
    sig { override.returns(String) }
    def route_id
      "stafftoolsLayoutRoute"
    end
  end
end
