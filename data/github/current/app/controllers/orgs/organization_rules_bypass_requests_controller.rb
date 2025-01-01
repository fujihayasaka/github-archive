# typed: true
# frozen_string_literal: true

class Orgs::OrganizationRulesBypassRequestsController < Orgs::Controller
  extend T::Sig
  include ReactHelper
  include Repos::RulesHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Spokes,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
  optional: true,
  only: [:index]

  before_action :organization_admin_required
  before_action :plan_supports_enterprise_rulesets
  before_action :check_delegated_bypass_enabled

  sig { returns(String) }
  def self.react_bundle_name
    "delegated-bypass"
  end

  sig { void }
  def index
    return render_404 unless current_organization.feature_enabled?(:push_ruleset_delegated_bypass)
    render_react_app(
      payload: rules_bypass_requests_payload(
        viewing_source: current_organization,
        filter: {
          approver: params[:approver],
          requester: params[:requester],
          time_period: params[:time_period],
          request_status: params[:request_status],
          repository: params[:repository],
        },
        page: params[:page].to_i,
        base_exemption_url: nil,
        request_type: "push_ruleset_bypass"
      ),
      app_payload_generator: -> { Exemptions::ReactPayload.app_payload(current_organization, "push_ruleset_bypass") },
      title: "Settings · Bypass Requests · #{current_organization.name_with_display_owner}",
      page_data: {
        selected_link: :org_rules_bypass_requests
      },
      layout: "layouts/settings/rules",
      ssr: false,
    )
  end

  def bypass_request_requesters # rubocop:todo GitHub/UseRestfulActions
    render json: filter_suggestions(RulesEngine::Suggestions.bypass_requests_requesters_for(current_organization))
  end

  def bypass_request_approvers # rubocop:todo GitHub/UseRestfulActions
    render json: filter_suggestions(RulesEngine::Suggestions.bypass_requests_approvers_for(current_organization))
  end

  private

  def check_delegated_bypass_enabled
    current_organization.delegated_bypass_enabled? || render_404
  end

  def plan_supports_enterprise_rulesets
    render_404 unless current_organization.plan_supports?(:enterprise_rulesets)
  end
end
