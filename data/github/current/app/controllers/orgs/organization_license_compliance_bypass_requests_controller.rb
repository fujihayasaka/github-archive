# typed: true
# frozen_string_literal: true

class Orgs::OrganizationLicenseComplianceBypassRequestsController < Orgs::SecurityCenter::AbstractSecurityCenterController
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
  ApplicationRecord::Iam,
  ApplicationRecord::RepositoriesPushes,
  only: [:index, :bypass_request_requesters, :bypass_request_approvers]

  depends_on_clusters  ApplicationRecord::SecurityOverviewAnalytics,
  ApplicationRecord::Notify,
  optional: true,
  only: [:index]

  before_action :organization_read_required
  before_action :ensure_can_view_organization_license_compliance_alerts

  sig { returns(String) }
  def self.react_bundle_name
    "delegated-bypass"
  end

  sig { void }
  def index
    render_react_app(
      payload: helpers.rules_bypass_requests_payload(
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
        base_exemption_url: nil,
        request_types: [DependencyGraph::LicenseComplianceDelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE],
        repo_exemptions_base_url_suffix: "security/license-compliance/"
      ),
      app_payload_generator: -> { Exemptions::ReactPayload.app_payload(current_organization, DependencyGraph::LicenseComplianceDelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE) },
      title: "Security · License Compliance Alert Requests · #{current_organization.name_with_display_owner}",
      page_data: {
        data: {
          selected_tab: :organization_license_compliance_bypass_requests,
          backfill_in_progress: false,
        }
      },
      layout: "layouts/security_center/with_sidebar",
      disable_ssr: true,
    )
  end

  sig { void }
  def bypass_request_requesters # rubocop:todo GitHub/UseRestfulActions
    render json: helpers.filter_suggestions(RulesEngine::Suggestions.bypass_requests_requesters_for(current_organization, DependencyGraph::LicenseComplianceDelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE))
  end

  sig { void }
  def bypass_request_approvers # rubocop:todo GitHub/UseRestfulActions
    render json: helpers.filter_suggestions(RulesEngine::Suggestions.bypass_requests_approvers_for(current_organization, DependencyGraph::LicenseComplianceDelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE))
  end

  private

  sig { void }
  def ensure_can_view_organization_license_compliance_alerts
    render_404 unless ::Permissions::LicensePolicy.can_view_organization_license_compliance_alerts?(current_user, current_organization)
  end
end
