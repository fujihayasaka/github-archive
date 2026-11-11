# typed: strict
# frozen_string_literal: true

require "react_payload"

class Stafftools::Users::OrganizationRuleInsightsDashboardController < StafftoolsController
  include Repos::Rules::Concerns::InsightsDashboard

  before_action :ensure_user_exists
  before_action :ensure_org_not_user
  before_action do
    T.bind(self, Stafftools::Users::OrganizationRuleInsightsDashboardController)
    rule_insights_dashboard_org_enabled(source: T.cast(this_user, Organization), user: current_user)
  end

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Memex,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Ballast,
    ApplicationRecord::RepositoriesPushes, only: [:index]

  depends_on_clusters ApplicationRecord::Copilot, only: [:index], optional: true

  sig { returns(String) }
  def self.react_bundle_name
    "rule-insights-dashboard"
  end

  sig { void }
  def index
    org = this_user
    return render_404 unless org&.organization?

    respond_with_react(
      payload: StafftoolsOrgDashboardRoutePayload.new(
        source: T.cast(org, Organization),
        user: current_user,
        filter: {
          ruleset_name: params[:ruleset],
          evaluate_status: params[:evaluate_status],
          created: params[:created],
        },
        insights_path: stafftools_user_organization_rules_insights_path(this_user),
      ),
      nested_payloads: -> { [StafftoolsOrgLayoutRoutePayload.new] },
      app_payload_generator: -> { { is_stafftools: true } },
      title: "Rule Insights Dashboard",
      layout: "layouts/stafftools/organization/overview",
      page_data: {
        selected_link: :organization_rule_insights_dashboard,
      },
    )
  end

  sig { void }
  def layout # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        render_react_json(payload: StafftoolsOrgLayoutRoutePayload.new)
      end
    end
  end

  class StafftoolsOrgDashboardRoutePayload < OrgDashboardRoutePayload
    sig { override.returns(String) }
    def route_id
      "stafftoolsOrgDashboardRoute"
    end
  end

  class StafftoolsOrgLayoutRoutePayload < OrgLayoutRoutePayload
    sig { override.returns(String) }
    def route_id
      "stafftoolsOrgLayoutRoute"
    end
  end
end
