# typed: true
# frozen_string_literal: true

module CodeQuality
  class HydroRepositoryLifecycleEventJob < Repositories::RepositoryHydroMessageJob
    queue_as :hydro_code_quality_repository_lifecycle_event
    retry_on_dirty_exit

    sig { void }
    def perform
      CodeQuality::RepositoryUpdatePublisher.publish_repository_id(repository_id:)
    end
  end
end
