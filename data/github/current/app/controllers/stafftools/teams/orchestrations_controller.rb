# typed: true
# frozen_string_literal: true

class Stafftools::Teams::OrchestrationsController < StafftoolsController
  include Stafftools::Users::ControllerLayoutMethods

  before_action :ensure_user_exists
  before_action :ensure_org_not_user
  before_action :ensure_team_exists
  before_action :orchestration_required, only: :show

  layout "layouts/stafftools/organization/security"

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Accounts,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:index, :show]

  def index
    render "stafftools/teams/orchestrations/index", locals: {
      orchestrations: recent_orchestrations
    }
  end

  def show
    render "stafftools/teams/orchestrations/show", locals: {
      orchestration: orchestration
    }
  end

  private

  def orchestration_required
    render_404 unless orchestration.present?
  end

  memoize def orchestration
    TeamOrchestration.find_by(id: params[:id])
  end

  memoize def recent_orchestrations
    TeamOrchestration
      .where(team_id: this_team.id)
      .includes(:team)
      .order("id DESC")
      .paginate(page: current_page)
  end
end
