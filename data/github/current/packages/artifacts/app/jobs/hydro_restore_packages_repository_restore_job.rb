# typed: false
# frozen_string_literal: true

class HydroRestorePackagesRepositoryRestoreJob < Repositories::RepositoryHydroMessageJob
  include GitHub::Memoizer

  queue_as :hydro_restore_packages_repository_restore

  def perform
    with_write do
      deleted_at = Google::Protobuf::Timestamp.new(message[:deleted_at]).to_time
      repository.restore_packages(actor, deleted_at:)
    end
  end

  memoize def actor
    User.find_by_id(message[:actor_id])
  end
end
