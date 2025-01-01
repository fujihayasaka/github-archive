# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::CodeScanningAlertDismissalRequestsController < Orgs::SecurityCenter::AbstractSecurityCenterController
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
  ApplicationRecord::Iam,
  only: [:index, :bypass_request_requesters, :bypass_request_approvers]

  depends_on_clusters  ApplicationRecord::SecurityOverviewAnalytics,
  ApplicationRecord::Notify,
  optional: true,
  only: [:index]

  before_action :organization_read_required
  before_action :verify_review_dismissal_reviewable

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
        base_exemption_url: nil,
        request_types: [CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE],
        repo_exemptions_base_url_suffix: "security/code-scanning/"
      ),
      app_payload_generator: -> { Exemptions::ReactPayload.app_payload(current_organization, CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE) },
      title: "Security · Code Scanning Alert Dismissal Requests · #{current_organization.name_with_display_owner}",
      page_data: {
        data: {
          selected_tab: :organization_code_scanning_alert_dismissal_requests,
          backfill_in_progress: false,
        }
      },
      layout: "layouts/security_center/with_sidebar",
      disable_ssr: true,
    )
  end

  sig { void }
  def bypass_request_requesters # rubocop:todo GitHub/UseRestfulActions
    render json: helpers.filter_suggestions(RulesEngine::Suggestions.bypass_requests_requesters_for(current_organization, CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE))
  end

  sig { void }
  def bypass_request_approvers # rubocop:todo GitHub/UseRestfulActions
    render json: helpers.filter_suggestions(RulesEngine::Suggestions.bypass_requests_approvers_for(current_organization, CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE))
  end

  private

  def verify_review_dismissal_reviewable
    return render_404 if current_organization.nil?
    return render_404 if current_user.nil?

    render_404 unless CodeScanning::AlertDismissalService.is_valid_org_reviewer?(org: current_organization, user: current_user)
  end
end
