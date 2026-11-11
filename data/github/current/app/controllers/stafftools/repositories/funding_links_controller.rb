# typed: strict
# frozen_string_literal: true

class Stafftools::Repositories::FundingLinksController < Stafftools::RepositoriesController
  before_action :ensure_repo_exists
  before_action :sponsors_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
  only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
  only: [:show], optional: true

  layout "layouts/stafftools/repository/collaboration"

  sig { void }
  def show
    render "stafftools/repositories/funding_links/show"
  end

  sig { void }
  def create
    if current_repository.funding_links_stafftools_disabled?
      Sponsors::KV.store.del(current_repository.funding_links_stafftools_kv_prefix)
    end

    flash[:notice] = "Repository sponsor button re-enabled."
    redirect_to stafftools_repository_funding_links_path(current_repository.owner_display_login, current_repository.name)
  end

  sig { void }
  def destroy
    if !current_repository.funding_links_stafftools_disabled?
      Sponsors::KV.store.set(current_repository.funding_links_stafftools_kv_prefix, "1")
    end

    flash[:notice] = "Repository sponsor button disabled."
    redirect_to stafftools_repository_funding_links_path(current_repository.owner_display_login, current_repository.name)
  end
end
