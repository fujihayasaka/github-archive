# typed: true
# frozen_string_literal: true

class Repos::DependabotAlerts::AssigneesController < AbstractRepositoryController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include DependabotAlerts::AlertsSerializer

  allow_verified_fetch only: [:update]

  before_action :require_ghas
  before_action :check_dependabot_alerts_write
  before_action :parse_json_params, only: [:update]

  def update
    alert = current_repository.repository_vulnerability_alerts.find_by(number: params.require(:number))
    return render status: 404, json: { message: "Alert not found" } unless alert

    assignee_ids = Array(params[:assignee_ids]).select(&:present?).uniq

    users = User.where(type: %w[User Bot], id: assignee_ids).includes(:profile).to_a
    if users.size != assignee_ids.uniq.size
      return render status: 422, json: { message: "One or more assignees do not exist" }
    end

    begin
      alert.update_assignees(users, current_user)
    rescue ActiveRecord::RecordInvalid => e
      return render status: 422, json: { message: e.message }
    end

    render json: {
      assignees: users.map { |assignee| serialized_assignee(assignee) },
    }
  end

  private

  sig { void }
  def require_ghas
    render_404 unless Dependabot.ghas_available?(current_repository.owner)
  end

  sig { void }
  def check_dependabot_alerts_write
    render_404 unless current_repository&.can_resolve_vulnerability_alerts?(current_user)
  end
end
