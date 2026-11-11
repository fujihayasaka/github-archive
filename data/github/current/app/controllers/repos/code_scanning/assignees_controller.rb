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
    alert_number = params[:number].to_i
    repository_id = current_repository.id

    assignee_ids = Array(params[:assignee_ids]).select(&:present?).uniq

    if assignee_ids.size > CodeScanning::AlertAssignment::ASSIGNEE_LIMIT
      return render status: 422, json: { message: "You can only assign 10 users to an alert" }
    end

    assignees = User.where(type: %w[User Bot], id: assignee_ids)
      .includes(:profile)
      .to_a
    if assignees.size != assignee_ids.size
      return render status: 422, json: { message: "One or more assignees do not exist" }
    end

    alert_response = T.let(nil, T.nilable(Twirp::ClientResp[::Turboscan::Proto::AlertResponse]))

    is_copilot_assignment_new = T.let(false, T::Boolean)
    copilot_swe_agent_bot = T.let(nil, T.nilable(Bot))
    result = T.let(nil, T.nilable(Turboscan::Proto::Result))

    authorized_assignees = Promise.all(assignees.map do |assignee|
      if assignee.is_a?(Bot)
        # The bot is the Copilot SWE agent, so we need to check if Copilot is being newly assigned
        copilot_swe_agent_integration = ::Apps::Privileged.integration(:copilot_swe_agent)
        if T.must(assignee.integration) == T.must(copilot_swe_agent_integration)
          copilot_swe_agent_bot = copilot_swe_agent_integration.bot
          alert_response = GitHub::Turboscan.alert(
            repository_id: current_repository.id,
            number: alert_number,
          )

          if alert_response&.data&.result.present?
            result = T.must(alert_response&.data&.result)

            is_copilot_assignment_new = result.assigned_user_ids.none? do |assignee_id|
              assignee_id == copilot_swe_agent_bot&.id
            end
          else
            return render status: 500, json: { message: "Could not get alert information" }
          end

          # If Copilot is already assigned, consider it an authorized assignee regardless
          # of other checks. This allows users to control when to unassign it.
          # Since we do not emit the Copilot assignment event when Copilot is already
          # assigned, it is okay to ignore the other checks in this scenario.
          next assignee if !is_copilot_assignment_new

          # If Copilot is being newly assigned, we need to check:
          # * if the copilot_security_alert_assignee_options feature flag is enabled
          # * if the Copilot SWE agent is enabled for the repository
          # * if there is a suggested fix available for the alert and it is not outdated
          next nil unless current_repository.owner.feature_flag_enabled?(:copilot_security_alert_assignee_options, default: false)
          next nil unless current_repository.copilot_swe_agent_enabled?(current_user)

          begin
            suggested_fix_alert = CodeScanning::AutofixSuggestion.fetch_all_suggested_fix_alerts(
              repository: current_repository,
              alert_numbers: [alert_number],
              head_commit_oid: result.most_recent_instance&.commit_oid
            )[alert_number]
          rescue CodeScanning::AutofixError => e
            Failbot.report!(e)
          end
          next nil if suggested_fix_alert&.suggested_fix.nil?
          next nil if suggested_fix_alert&.suggested_fix&.outdated
        end

        # The bot cannot be assigned to alerts
        unless ::Apps::Privileged.capable?(:is_assignable, app: assignee.integration)
          next nil
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
      user_ids: authorized_assignees.map(&:id),
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

    if copilot_swe_agent_bot && is_copilot_assignment_new && authorized_assignees.include?(copilot_swe_agent_bot)
      emit_copilot_assignment_event(copilot_swe_agent_bot:, result:)
    end

    render json: {
      assignees: authorized_assignees.map { |assignee| serialized_assignee(assignee) },
      isCopilotAssignmentNew: is_copilot_assignment_new,
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
