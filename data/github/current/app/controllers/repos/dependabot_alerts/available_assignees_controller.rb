# typed: strict
# frozen_string_literal: true

class Repos::DependabotAlerts::AvailableAssigneesController < AbstractRepositoryController
  include ApplicationController::VerifiedFetchDependency
  include DependabotAlerts::AlertsSerializer

  before_action :require_ghas
  before_action :check_dependabot_alerts_write

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    only: [:index]

  sig { void }
  def index
    users = Dependabot::AlertAssignment.available_assignees(
      repository: current_repository,
      current_user: current_user,
      query: params[:query].to_s,
    )

    render json: {
      users: users.map { |user| serialized_assignee(user) }
    }
  end

  private

  sig { void }
  def require_ghas
    render_404 unless Dependabot.ghas_available?(current_repository.owner)
  end

  sig { void }
  def check_dependabot_alerts_write
    render_404 unless current_repository.can_resolve_vulnerability_alerts?(current_user)
  end
end
