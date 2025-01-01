# typed: true
# frozen_string_literal: true

class HydroDeleteRestorableRepositoryMembershipsRepositoryTransferredJob < Repositories::RepositoryHydroMessageJob
  queue_as :hydro_delete_restorable_repository_memberships_repository_transferred

  BATCH_SIZE = 100

  # Destroy restorable repository memberships for this repository, since it has been transferred,
  # those memberships may no longer be valid.
  #
  # Returns nothing
  def perform
    Restorable::Membership.repository_memberships.where(subject_id: repository_id).in_batches(of: BATCH_SIZE) do |batch|
      Restorable::Membership.throttle do
        with_write { batch.delete_all }
      end
    end
  end
end
