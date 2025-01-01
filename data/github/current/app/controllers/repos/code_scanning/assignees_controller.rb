# typed: true
# frozen_string_literal: true

class Repos::CodeScanning::AssigneesController < AbstractRepositoryController
  include ScanningControllerMethods
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include CodeScanning::AlertsSerializer

  allow_verified_fetch only: [:update]

  before_action :check_code_scanning_write
  before_action :parse_json_params, only: [:update]

  def update
    return render_404 unless current_repository.code_scanning_alert_assignment_enabled?

    alert_number = params[:number].to_i
    repository_id = current_repository.id

    assignee_ids = Array(params[:assignee_ids]).select(&:present?).uniq

    if assignee_ids.size > CodeScanning::AlertAssignment::ASSIGNEE_LIMIT
      return render status: 422, json: { message: "You can only assign 10 users to an alert" }
    end

    assignees = User.where(type: %w[User Bot], id: assignee_ids).to_a
    if assignees.size != assignee_ids.size
      return render status: 422, json: { message: "One or more assignees do not exist" }
    end

    authorized_assignees = Promise.all(assignees.map do |assignee|
      if assignee.is_a?(Bot)
        # The bot cannot be assigned to alerts
        unless ::Apps::Privileged.capable?(:is_assignable, app: assignee.integration)
          next nil
        end
        # The bot is the Copilot SWE agent, so we need to check if the repository has it enabled
        if T.must(assignee.integration) == T.must(::Apps::Privileged.integration(:copilot_swe_agent))
          next nil unless current_repository.copilot_swe_agent_enabled?(current_user)
        end

        # The bot is installed globally and can be assigned to alerts
        unless ::Apps::Privileged.capable?(:installed_globally, app: assignee.integration)
          installation = IntegrationInstallation.with_repository(current_repository).includes(integration: :bot)

          if installation.nil? || installation.repository_ids(repository_ids: [current_repository.id]).none?
            # The bot does not have access to the repository
            next nil
          end
        end
        assignee
      else
        current_repository.async_code_scanning_allowed?(:write_code_scanning, assignee).then do |allowed|
          if allowed
            assignee
          else
            nil
          end
        end
      end
    end).sync.filter(&:present?)

    if authorized_assignees.size != assignees.size
      return render status: 422, json: { message: "One or more assignees cannot be assigned to this alert" }
    end

    request = ::Turboscan::Proto::SetAssigneesForAlertsRequest.new(
      repository_id:,
      alert_numbers: [alert_number],
      user_ids: assignees.map(&:id),
      operation_type: ::Turboscan::Proto::SetAssigneesForAlertsOperationType::SET_ASSIGNEES_FOR_ALERTS_OPERATION_TYPE_REPLACE,
    )

    response = GitHub::Turboscan.set_assignees_for_alerts(request.to_h)

    if response.blank? || response.error.present?
      if response&.error&.code == :not_found
        return render status: 422, json: { message: "Could not find the alert" }
      end
      return render status: 500, json: { message: "Could not set the assignees" }
    end

    render json: {
      assignees: assignees.map { |assignee| serialized_assignee(assignee) },
    }
  end
end
