# typed: true
# frozen_string_literal: true

class RegistryTwo::RepositoryItemsController < RegistryTwo::Controller
  MAX_PAGES = 100
  PER_PAGE = 50

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
  only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  before_action :get_metadata, only: :index

  def index
    total_count = owner.visible_repositories_for(current_user).size
    page = params[:page].to_i

    return render_404 unless page && page > 0

    repositories = owner.visible_repositories_for(current_user)
      .order(:id)
      .paginate(
        page: page,
        per_page: PER_PAGE,
        total_entries: [total_count, MAX_PAGES * PER_PAGE].min,
      )

    respond_to do |format|
      format.html do
        render(Packages::RepositoryItemsComponent.new(
          package: @metadata.package,
          next_page: page + 1,
          owner: owner,
          repositories: repositories,
          total_count: total_count
        ), layout: false)
      end
    end
  end
end
