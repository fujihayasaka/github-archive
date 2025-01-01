# typed: true
# frozen_string_literal: true

class Stafftools::Users::Repositories::PagesController < StafftoolsController
  include Stafftools::Users::ControllerLayoutMethods

  before_action :ensure_user_exists

  layout :content_layout

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab

  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Spokes,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    optional: true

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = ["Stafftools::Users::Repositories::PagesController#update"]

  PAGE_SIZE = 100

  def show
    return render_404 unless endpoint_enabled?

    page = [1, params[:repo_page].to_i].max

    soft_deleted_pages_repos = this_user.repositories.includes(:page).joins(:page)
      .select(:name, :owner_login, :public, :source_id, page: [:public, :deleted_at, :repository_id])
      .where.not(page: { deleted_at: nil })
      .order(:name)
      .paginate(page: page, per_page: PAGE_SIZE)

    render(
      "stafftools/users/repositories/pages/show",
      locals: {
        user: this_user,
        soft_deleted_pages_repos: soft_deleted_pages_repos,
        supports_pages: supports_pages?,
        supports_private_pages: supports_private_pages?,
        supports_pages_of_private_repos: supports_pages_of_private_repos?,
      }
    )
  end

  def update
    return head(:not_found) unless endpoint_enabled?

    RestoreSoftDeletedPagesJob.perform_later(this_user)

    redirect_to stafftools_user_repositories_pages_path(this_user), notice: "Restore job queued"
  end

  private

  def endpoint_enabled?
    return false if GitHub.single_or_multi_tenant_enterprise?
    return false unless GitHub.pages_enabled?
    true
  end

  def supports_pages?
    this_user.plan_supports?(:pages)
  end

  def supports_private_pages?
    this_user.plan_supports?(:private_pages)
  end

  def supports_pages_of_private_repos?
    this_user.plan_supports?(:pages, visibility: :private)
  end
end
