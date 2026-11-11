# typed: true
# frozen_string_literal: true

class HydroCorrectWatchersRepositoryTransferredJob < Repositories::RepositoryHydroMessageJob
  include HydroWaitForReplicasTrait

  wait_for_replicas ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories

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
