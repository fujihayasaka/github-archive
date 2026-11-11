# typed: true
# frozen_string_literal: true

# Corrects the watchers list when a repository is transferred between owners. Calls
# repository.correct_watchers within a write context to reconcile subscription state.
#
# Enqueued by: Aqueduct Hydro Message Bridge from the github.repositories.v1.Transferred
# Hydro message (published by Git infrastructure babeld/spokes on repository transfer).
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
