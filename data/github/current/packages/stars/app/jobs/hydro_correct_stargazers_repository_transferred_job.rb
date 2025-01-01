# typed: true
# frozen_string_literal: true

class HydroCorrectStargazersRepositoryTransferredJob < Repositories::RepositoryHydroMessageJob
  queue_as :hydro_correct_stargazers_repository_transferred

  # Public: process a Hydro message
  #
  # Returns nothing
  def perform
    with_write do
      repository.correct_stargazers
    end
  end
end
