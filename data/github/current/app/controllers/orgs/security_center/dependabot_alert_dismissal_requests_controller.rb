# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::DependabotAlertDismissalRequestsController < Orgs::SecurityCenter::AbstractSecurityCenterController
  include Repos::RulesHelper
  include Dependabot::DelegatedAlertDismissal

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
    only: [:index, :dismissal_request_requesters, :dismissal_request_approvers]

  depends_on_clusters ApplicationRecord::SecurityOverviewAnalytics,
    ApplicationRecord::Notify,
    optional: true,
    only: [:index]

  before_action :organization_read_required
  before_action :check_dismissal_request_list_access

  sig { returns(String) }
  def self.react_bundle_name
    "delegated-bypass"
  end

  sig { void }
  def index
    render_react_app(
      payload: rules_bypass_requests_payload(
        viewing_source: T.must(current_organization),
        filter: {
          approver: params[:approver],
          requester: params[:requester],
          time_period: params[:time_period],
          request_status: params[:request_status],
          repository: params[:repository],
          organization: nil,
        },
        page: params[:page].to_i,
        base_exemption_url: "/orgs/#{T.must(current_organization).display_login}/security/dependabot/",
        request_types: [Dependabot::SecurityProduct::DelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE],
        repo_exemptions_base_url_suffix: "security/dependabot/",
        required_repo_permission: nil
      ),
      app_payload_generator: -> { Exemptions::ReactPayload.app_payload(T.must(current_organization), Dependabot::SecurityProduct::DelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE) },
      title: "Security · Dependabot Alert Dismissal Requests · #{T.must(current_organization).name_with_display_owner}",
      page_data: {
        data: {
          selected_tab: :organization_dependabot_alert_dismissal_requests,
          backfill_in_progress: false,
        }
      },
      layout: "layouts/security_center/with_sidebar",
      disable_ssr: true,
    )
  end

  sig { void }
  def dismissal_request_requesters # rubocop:todo GitHub/UseRestfulActions
    render json: helpers.filter_suggestions(RulesEngine::Suggestions.bypass_requests_requesters_for(T.must(current_organization), Dependabot::SecurityProduct::DelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE))
  end

  sig { void }
  def dismissal_request_approvers # rubocop:todo GitHub/UseRestfulActions
    render json: helpers.filter_suggestions(RulesEngine::Suggestions.bypass_requests_approvers_for(T.must(current_organization), Dependabot::SecurityProduct::DelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE))
  end

  private

  sig { void }
  def check_dismissal_request_list_access
    return render_404 if current_organization.nil?
    return render_404 if current_user.nil?
    render_404 unless delegated_closures.user_can_review_closure_requests?(T.must(current_user))
  end
end
