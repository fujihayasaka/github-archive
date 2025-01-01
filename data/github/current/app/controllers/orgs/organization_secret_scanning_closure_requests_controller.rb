# typed: strict
# frozen_string_literal: true

class Orgs::OrganizationSecretScanningClosureRequestsController < Orgs::SecurityCenter::AbstractSecurityCenterController
  include SecretScanning::Constants
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
  only: [:index, :closure_request_requesters, :closure_request_approvers, :counts]

  depends_on_clusters  ApplicationRecord::SecurityOverviewAnalytics,
  ApplicationRecord::Notify,
  optional: true,
  only: [:index]

  before_action :organization_read_required
  before_action :check_closure_request_list_access

  sig { returns(String) }
  def self.react_bundle_name
    "delegated-bypass"
  end

  sig { void }
  def index
    required_repo_permission = :resolve_secret_scanning_alerts
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
        base_exemption_url: "../../../security/secret-scanning/",
        request_types: [SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE],
        repo_exemptions_base_url_suffix: "security/secret-scanning/",
        required_repo_permission:,
      ),
      app_payload_generator: -> { Exemptions::ReactPayload.app_payload(current_organization, SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE) },
      title: "Security · Secret Scanning Alert Dismissal Requests · #{current_organization.name_with_display_owner}",
      page_data: {
        data: {
          selected_tab: :organization_secret_scanning_closure_requests,
          backfill_in_progress: false,
        }
      },
      layout: "layouts/security_center/with_sidebar",
      disable_ssr: true,
    )
  end

  sig { void }
  def closure_request_requesters # rubocop:todo GitHub/UseRestfulActions
    render json: helpers.filter_suggestions(RulesEngine::Suggestions.bypass_requests_requesters_for(current_organization, SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE))
  end

  sig { void }
  def closure_request_approvers # rubocop:todo GitHub/UseRestfulActions
    render json: helpers.filter_suggestions(RulesEngine::Suggestions.bypass_requests_approvers_for(current_organization, SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE))
  end

  sig { void }
  def counts # rubocop:todo GitHub/UseRestfulActions
    count = current_organization.token_scanning_closure_request_count
    response = {
      # Because we currently only call this endpoint once for the current org, we're hardcoding the expected format.
      "item-0": render_to_string(Primer::Beta::Counter.new(count: count, limit: 5_000, hide_if_zero: true), layout: false)
    }
    respond_to do |format|
      format.json do
        render json: response
      end
    end
  end

  private

  sig { void }
  def check_closure_request_list_access
    return render_404 if current_user.nil?

    render_404 unless SecretScanning::Features::Org::DelegatedClosures.new(current_organization).user_can_review_closure_requests?(current_user)
  end
end
