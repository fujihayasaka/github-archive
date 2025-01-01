# typed: true
# frozen_string_literal: true

class Orgs::OrganizationSecretScanningBypassRequestsController < Orgs::Controller
  include SecretScanning::Constants
  include ReactHelper
  include Repos::RulesHelper

  depends_on_clusters ApplicationRecord::Mysql1,
  ApplicationRecord::Repositories,
  ApplicationRecord::Mysql5,
  ApplicationRecord::NotificationsEntries,
  ApplicationRecord::Mysql2,
  ApplicationRecord::Collab,
  ApplicationRecord::Copilot,
  ApplicationRecord::IamAbilities,
  ApplicationRecord::Billing,
  ApplicationRecord::Configurations,
  ApplicationRecord::Spokes,
  only: [:index, :bypass_request_requesters, :bypass_request_approvers]

  depends_on_clusters  ApplicationRecord::SecurityOverviewAnalytics,
  ApplicationRecord::Notify,
  optional: true,
  only: [:index]

  before_action :organization_read_required
  before_action :check_bypass_request_list_access

  sig { returns(String) }
  def self.react_bundle_name
    "delegated-bypass"
  end

  sig { void }
  def index
    render_react_app(
      payload: rules_bypass_requests_payload(
        viewing_source: current_organization,
        filter: {
          approver: params[:approver],
          requester: params[:requester],
          time_period: params[:time_period],
          request_status: params[:request_status],
          repository: params[:repository],
          organization: nil,
        },
        page: params[:page].to_i,
        base_exemption_url: "../../../secret_scanning/exemptions/",
        request_types: [SecretScanning::Constants::EXEMPTION_REQUEST_TYPE],
        repo_exemptions_base_url_suffix: "secret_scanning/exemptions/"
      ),
      app_payload_generator: -> { Exemptions::ReactPayload.app_payload(current_organization, EXEMPTION_REQUEST_TYPE) },
      title: "Security · Push Protection Bypass Requests · #{current_organization.name_with_display_owner}",
      page_data: {
        data: {
          selected_tab: :organization_secret_scanning_bypass_requests,
          backfill_in_progress: false,
        }
      },
      layout: "layouts/security_center/with_sidebar",
      ssr: false,
    )
  end

  sig { void }
  def bypass_request_requesters # rubocop:todo GitHub/UseRestfulActions
    render json: helpers.filter_suggestions(RulesEngine::Suggestions.bypass_requests_requesters_for(current_organization, RuleEngine::Rules::SecretScanningRule::RULE_NAME))
  end

  sig { void }
  def bypass_request_approvers # rubocop:todo GitHub/UseRestfulActions
    render json: helpers.filter_suggestions(RulesEngine::Suggestions.bypass_requests_approvers_for(current_organization, RuleEngine::Rules::SecretScanningRule::RULE_NAME))
  end

  private

  def check_bypass_request_list_access
    return render_404 if current_user.nil?

    render_404 unless SecretScanning::Features::Org::DelegatedBypass.new(current_organization).can_view_requests_list?(current_user)
  end
end
