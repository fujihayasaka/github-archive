# typed: true
# frozen_string_literal: true

class Repos::CodeScanning::AssigneesController < AbstractRepositoryController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include CodeScanning::AlertsSerializer
  include CodeScanning::ControllerAccessChecks

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
          next nil unless current_repository.copilot_swe_agent_enabled?(current_user) && CodeScanning::AutofixService.agentic_autofix_padawan_integration_enabled?(current_repository)
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

    is_copilot_assignment_new = false
    copilot_swe_agent_bot = T.let(nil, T.nilable(Bot))
    result = T.let(nil, T.nilable(Turboscan::Proto::Result))

    # Determine if the Copilot SWE agent is being newly assigned
    # by checking the current assignees of the alert.
    if current_repository.copilot_swe_agent_enabled?(current_user)
      copilot_swe_agent_bot = ::Apps::Privileged.integration(:copilot_swe_agent).bot

      if assignees.include?(copilot_swe_agent_bot)
        alert_response = GitHub::Turboscan.alert(
          repository_id: current_repository.id,
          number: alert_number,
        )

        if alert_response&.data&.result.present?
          result = T.must(alert_response&.data&.result)

          is_copilot_assignment_new = result.assigned_user_ids.none? do |assignee_id|
            assignee_id == copilot_swe_agent_bot.id
          end
        end
      end
    end

    request = ::Turboscan::Proto::SetAssigneesForAlertsRequest.new(
      repository_id:,
      alert_numbers: [alert_number],
      user_ids: assignees.map(&:id),
      operation_type: ::Turboscan::Proto::SetAssigneesForAlertsOperationType::SET_ASSIGNEES_FOR_ALERTS_OPERATION_TYPE_REPLACE,
      actor_id: current_user.id,
      actor: current_user.display_login,
      org_id: current_repository.owner_id,
      org: current_repository.owner.display_login,
      business_id: current_repository.owner.business&.id,
      business: current_repository.owner.business&.slug,
      repository_nwo: current_repository.name_with_display_owner
    )

    response = GitHub::Turboscan.set_assignees_for_alerts(request.to_h)

    if response.blank? || response.error.present?
      if response&.error&.code == :not_found
        return render status: 422, json: { message: "Could not find the alert" }
      end
      return render status: 500, json: { message: "Could not set the assignees" }
    end


    emit_copilot_assignment_event(copilot_swe_agent_bot:, result:) if is_copilot_assignment_new

    render json: {
      assignees: assignees.map { |assignee| serialized_assignee(assignee) },
    }
  end

  private

  def emit_copilot_assignment_event(copilot_swe_agent_bot: Bot, result: Turboscan::Proto::Result)
    alerts_with_autofix_suggestions = CodeScanning::AlertAssignment.build_alerts_assignment_alerts(repository: T.must(current_repository), alert_numbers: [result.number], alert_titles: {
      result.number => result.rule&.short_description,
    })
    return unless alerts_with_autofix_suggestions.present?

    # Emit an analytics event for the alert assignment to Copilot
    GlobalInstrumenter.instrument("code_scanning.alerts_assignment", {
      repository: current_repository,
      code_scanning_alerts: alerts_with_autofix_suggestions.values,
      actor: current_user,
      assignees: [copilot_swe_agent_bot]
    })
  end
end
