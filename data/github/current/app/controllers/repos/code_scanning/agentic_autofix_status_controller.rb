# typed: true
# frozen_string_literal: true

class Repos::CodeScanning::AgenticAutofixStatusController < AbstractRepositoryController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include CodeScanning::ControllerAccessChecks

  allow_verified_fetch only: [:show]

  before_action :login_required
  before_action :check_code_scanning_read

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Iam,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    return head(:not_found) if GitHub.enterprise?

    alert_number = params[:number].to_i
    return head(:bad_request) if alert_number <= 0 || alert_number > Api::App::CodeScanningHelpers::MAX_ALERT_NUMBER

    return head(:not_found) unless CodeScanning::AgenticAutofix.enabled?(current_repository, current_user)

    response = GitHub::Turboscan.alert(
      repository_id: current_repository.id,
      number: alert_number,
    )

    result = response&.data&.result
    return head(:not_found) unless result.present?

    copilot_bot_id = ::Apps::Privileged.integration(:copilot_swe_agent)&.bot&.id
    return head(:not_found) unless copilot_bot_id.present?

    is_copilot_assigned = result.assigned_user_ids.include?(copilot_bot_id)

    alert_links = CodeScanning::AlertLinks.load_for_single_alert(repository_id: current_repository.id, alert_number:)
    copilot_link = alert_links.find do |link|
      next unless link.pull_request?
      pr = T.must(link.pull_request)
      pr.repository_id == current_repository.id && pr.user_id == copilot_bot_id
    end
    copilot_pull_request = T.must(copilot_link.pull_request) if copilot_link

    state = if copilot_pull_request.present?
      "completed"
    elsif is_copilot_assigned
      "pending"
    else
      "unassigned"
    end

    copilot_pr_data = if copilot_pull_request.present?
      {
        number: copilot_pull_request.number,
        createdAt: copilot_pull_request.created_at.iso8601,
      }
    end

    render json: {
      state: state,
      copilotPullRequest: copilot_pr_data,
    }
  end
end
