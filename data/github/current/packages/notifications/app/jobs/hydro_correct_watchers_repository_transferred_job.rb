# typed: true
# frozen_string_literal: true

class HydroCorrectWatchersRepositoryTransferredJob < Repositories::RepositoryHydroMessageJob
  queue_as :hydro_correct_watchers_repository_transferred

  # Public: process a Hydro message
  #
  # Returns nothing
  def perform
    with_write do
      repository.correct_watchers
    end
  end
end
