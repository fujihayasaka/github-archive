# typed: strict
# frozen_string_literal: true

require "react_payload"

class Repos::Rules::InsightsDashboardController < AbstractRepositoryController
  include Repos::Rules::Concerns::InsightsDashboard

  before_action do
    T.bind(self, Repos::Rules::InsightsDashboardController)
    rule_insights_dashboard_enabled(source: current_repository, user: current_user)
  end
  before_action :plan_supports_enterprise_rulesets
  before_action :ensure_user_has_edit_branch_protection
  before_action :writable_repository_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Memex,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::RepositoriesPushes, only: [:index]

  depends_on_clusters ApplicationRecord::Copilot, only: [:index], optional: true

  sig { returns(String) }
  def self.react_bundle_name
    "rule-insights-dashboard"
  end

  sig { void }
  def index
    branch = if params[:ref] == "all"
      nil # user explicitly cleared → show all branches
    elsif params[:ref].present?
      params[:ref] # specific branch selected
    else
      current_repository.default_branch # initial page load → default branch
    end

    respond_with_react(
      payload: DashboardRoutePayload.new(
        source: current_repository,
        user: current_user,
        filter: {
          branch: branch,
          ruleset_name: params[:ruleset],
          evaluate_status: params[:evaluate_status],
          created: params[:created],
        },
        insights_path: repository_rule_insights_path,
      ),
      nested_payloads: -> { [LayoutRoutePayload.new] },
      title: "Dashboard",
      layout: "layouts/settings/rules",
      page_data: {
        selected_link: :repo_rule_insights_dashboard,
        sidebar: :policies,
      },
    )
  end

  sig { void }
  def layout # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        render_react_json(payload: LayoutRoutePayload.new)
      end
    end
  end

  private

  sig { void }
  def plan_supports_enterprise_rulesets
    render_404 unless current_repository.plan_supports?(:enterprise_rulesets) || current_repository.in_organization?
  end

  sig { void }
  def ensure_user_has_edit_branch_protection
    render_404 unless current_repository.async_can_edit_repo_protections?(current_user).sync
  end
end
