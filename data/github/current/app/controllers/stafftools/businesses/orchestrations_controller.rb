# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::OrchestrationsController < Stafftools::Businesses::BusinessBaseController
  skip_before_action :dotcom_required
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
    render "stafftools/businesses/orchestrations/index", locals: {
      orchestrations: recent_orchestrations
    }
  end

  def show
    render "stafftools/businesses/orchestrations/show", locals: {
      orchestration: orchestration
    }
  end

  private

  def orchestration_required
    render_404 unless orchestration.present?
  end

  memoize def orchestration
    BusinessOrchestration.find_by(id: params[:id])
  end

  memoize def recent_orchestrations
    BusinessOrchestration
      .where(business_id: this_business.id)
      .includes(:business)
      .order("id DESC")
      .paginate(page: current_page, per_page: DEFAULT_PAGE_SIZE)
  end
end
