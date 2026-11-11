# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::EnterpriseTeams::OrchestrationsController < Stafftools::Businesses::BusinessBaseController
  skip_before_action :dotcom_required
  before_action :enterprise_team_required
  before_action :orchestration_required, only: :show

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Accounts,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:index, :show]

  def index
    render "stafftools/businesses/enterprise_teams/orchestrations/index", locals: {
      orchestrations: recent_orchestrations
    }
  end

  def show
    render "stafftools/businesses/enterprise_teams/orchestrations/show", locals: {
      orchestration: orchestration
    }
  end

  private

  def enterprise_team_required
    render_404 unless this_enterprise_team.present?
  end

  def orchestration_required
    render_404 unless orchestration.present?
  end

  memoize def this_enterprise_team
    this_business.business_teams.find_by(id: params[:enterprise_team_id])
  end
  helper_method :this_enterprise_team

  memoize def orchestration
    TeamOrchestration.find_by(id: params[:orchestration_id])
  end

  memoize def recent_orchestrations
    TeamOrchestration
      .where(team_id: this_enterprise_team.id)
      .includes(:team)
      .order("id DESC")
      .paginate(page: current_page, per_page: DEFAULT_PAGE_SIZE)
  end
end
