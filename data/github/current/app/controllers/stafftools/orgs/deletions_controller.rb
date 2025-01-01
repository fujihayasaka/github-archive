# typed: true
# frozen_string_literal: true

class Stafftools::Orgs::DeletionsController < StafftoolsController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:index]

  RESULTS_PER_PAGE = 30

  sig { void }
  def index
    return render_404 if GitHub.single_business_environment?

    orgs = params[:query].present? ? deleted_orgs_search_results : deleted_orgs
    render "stafftools/organizations/deletions/index", layout: "stafftools", locals: {
      deleted_orgs: orgs.paginate(page: current_page, per_page: RESULTS_PER_PAGE)
    }
  end

  private

  sig { returns ActiveRecord::Relation }
  memoize def deleted_orgs
    Organization.includes(
      :profile,
      :soft_deleted_organization
    ).soft_deleted.merge(SoftDeletedOrganization.order(created_at: :desc))
  end

  sig { returns T::Array[Organization] }
  memoize def deleted_orgs_search_results
    Organization.search(params[:query], deleted: true)
  end
end
