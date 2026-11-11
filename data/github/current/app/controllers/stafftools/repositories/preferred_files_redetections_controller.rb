# typed: true
# frozen_string_literal: true

class Stafftools::Repositories::PreferredFilesRedetectionsController < StafftoolsController
  before_action :ensure_repo_exists

  def create
    RepositoryCheckPreferredFilesJob.perform_later(
      current_repository.id,
      current_repository.default_oid,
    )

    redirect_to(
      admin_stafftools_repository_path(
        id: current_repository.name,
        user_id: current_repository.owner,
      ),
      notice: "Preferred files redetection job enqueued",
    )
  end
end
