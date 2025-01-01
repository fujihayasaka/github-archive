# typed: true
# frozen_string_literal: true

class Stafftools::RepositoryFilesController < StafftoolsController
  before_action :ensure_repo_exists
  before_action :ensure_file_exists, except: :index

  layout "layouts/stafftools/repository/collaboration"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show],
    optional: true

  def index
    @files = RepositoryFile.where(repository_id: current_repository.id).
      order("name ASC").
      limit(25).
      page(params[:page] || 1)
    render "stafftools/repository_files/index"
  end

  def show
    render "stafftools/repository_files/show"
  end

  def database # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/repository_files/database"
  end

  def destroy
    this_file.destroy

    flash[:notice] = "Deleted file '#{this_file.name}'"
    redirect_to gh_stafftools_repository_repository_files_path(current_repository)
  end

  private

  def this_file # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @this_file ||= RepositoryFile.find(params[:id])
  end
  helper_method :this_file

  def ensure_file_exists
    return render_404 if this_file.nil?
  end
end
