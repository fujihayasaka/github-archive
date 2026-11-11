# typed: true
# frozen_string_literal: true

class Stafftools::Orgs::DeletionsController < StafftoolsController
  depends_on_clusters \
    ApplicationRecord::Mysql1,
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
    render "stafftools/organizations/deletions/index", layout: "stafftools", locals: {
      deleted_orgs: orgs.paginate(
        page: current_page,
        per_page: RESULTS_PER_PAGE,
        total_entries: total_entries
      )
    }
  end

  private

  memoize def orgs
    if params[:query].present?
      deleted_orgs_search_results
    else
      deleted_orgs
    end
  end

  sig { returns ActiveRecord::Relation }
  memoize def deleted_orgs
    Organization
      .includes(:profile, :soft_deleted_organization)
      .soft_deleted
      .order("soft_deleted_organizations.created_at DESC")
  end

  sig { returns T::Array[Organization] }
  memoize def deleted_orgs_search_results
    Organization.search(params[:query], deleted: true)
  end

  memoize def total_entries
    if params[:query].present?
      deleted_orgs_search_results.size
    else
      # Avoid expensive default will_paginate COUNT query
      SoftDeletedOrganization.count
    end
  end
end
