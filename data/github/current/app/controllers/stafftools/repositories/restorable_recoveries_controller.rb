# typed: strict
# frozen_string_literal: true

class Stafftools::Repositories::RestorableRecoveriesController < Stafftools::RepositoriesController
  sig { void }
  def create
    restoration_started = Restorables.domain.visibility_changed_repositories.restore_from(
      current_repository,
      actor: current_user,
    )

    unless restoration_started
      flash[:error] = "This repository does not have any data available to restore at this time. " \
        "Please try again later."
      redirect_to :back
      return
    end

    flash[:notice] = "Star and watcher restoration has been started."
    redirect_to :back
  end

  sig { void }
  def destroy
    Restorables.domain.visibility_changed_repositories.cancel_restorations(current_repository, actor: current_user)
    flash[:notice] = "Star and watcher restoration has been cancelled."
    redirect_to :back
  end
end
