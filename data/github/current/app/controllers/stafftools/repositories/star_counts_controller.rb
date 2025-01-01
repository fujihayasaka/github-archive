# typed: true
# frozen_string_literal: true

class Stafftools::Repositories::StarCountsController < Stafftools::RepositoriesController
  def create
    old_count = current_repository.stargazer_count
    new_count = Stars.domain.repository_star_count(current_repository.id)
    if new_count == old_count
      flash[:notice] = "No change to make for #{current_repository.name_with_display_owner}'s current star count of #{old_count}."
    else
      Repositories.domain.update_stargazer_count(repository_id: current_repository.id, count: new_count)
      flash[:notice] = "Changed #{current_repository.name_with_display_owner}'s star count from #{old_count} to #{new_count}."
    end
    redirect_back(fallback_location: overview_stafftools_repository_path(current_repository.owner_display_login,
      current_repository))
  end
end
