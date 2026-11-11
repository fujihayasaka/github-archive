# typed: strict
# frozen_string_literal: true

require "react_payload"

class Orgs::Rules::InsightsDashboardController < Orgs::Controller
  include Repos::Rules::Concerns::InsightsDashboard

  before_action do
    T.bind(self, Orgs::Rules::InsightsDashboardController)
    rule_insights_dashboard_org_enabled(source: current_organization, user: current_user)
  end
  before_action :org_ref_rules_manager_only
  before_action :ensure_trade_restrictions_allows_org_settings_access

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Memex,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::RepositoriesPushes, only: [:index]

  depends_on_clusters ApplicationRecord::Copilot, only: [:index], optional: true

  sig { returns(String) }
  def self.react_bundle_name
    "rule-insights-dashboard"
  end

  sig { void }
  def index
    respond_with_react(
      payload: OrgDashboardRoutePayload.new(
        source: current_organization,
        user: current_user,
        filter: {
          ruleset_name: params[:ruleset],
          evaluate_status: params[:evaluate_status],
          created: params[:created],
        },
        insights_path: organization_rule_insights_path(current_organization),
      ),
      nested_payloads: -> { [OrgLayoutRoutePayload.new] },
      title: "Dashboard",
      layout: "layouts/settings/rules",
      page_data: {
        selected_link: :org_rule_insights_dashboard,
        sidebar: :policies,
      },
    )
  end

  sig { void }
  def layout # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        render_react_json(payload: OrgLayoutRoutePayload.new)
      end
    end
  end
end
