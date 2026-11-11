# typed: true
# frozen_string_literal: true

class Stafftools::Orgs::OrchestrationsController < StafftoolsController
  include Stafftools::Users::ControllerLayoutMethods

  before_action :ensure_user_exists
  before_action :ensure_org_not_user
  before_action :orchestration_required, only: :show

  layout :overview_layout

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:index, :show]

  def index
    render "stafftools/organizations/orchestrations/index", locals: {
      orchestrations: recent_orchestrations
    }
  end

  def show
    render "stafftools/organizations/orchestrations/show", locals: {
      orchestration: orchestration
    }
  end

  private

  def orchestration_required
    render_404 unless orchestration.present?
  end

  memoize def orchestration
    OrganizationOrchestration.find_by(id: params[:id])
  end

  # Orchestrations directly associated with the Organizaton or its owning Business.
  memoize def recent_orchestrations
    OrganizationOrchestration
      .where(organization_id: this_user.id)
      .or(OrganizationOrchestration.where(business_id: this_user.business&.id))
      .includes(:organization)
      .order("id DESC")
      .paginate(page: current_page)
  end
end
