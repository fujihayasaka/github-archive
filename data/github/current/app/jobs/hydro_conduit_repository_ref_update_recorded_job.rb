# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# This job listens to Hydro messages for repository ref update recorded events,
# and publishes them to the conduit topic.
class HydroConduitRepositoryRefUpdateRecordedJob < HydroMessageJob
  queue_as :hydro_conduit_repository_ref_update_recorded

  retry_on_dirty_exit

  # Public: process a Hydro message
  sig { void }
  def perform
    actor_id, repository_id, push_id = message.values_at(:actor_id, :repository_id, :push_id)
    actor = User.find_by(id: actor_id)
    repository = if FeatureFlag.vexi.enabled?(:repos_by_id_jobs, default: false)
      Repositories.domain.by_id(repository_id)
    else
      Repository.find_by(id: repository_id)
    end

    return unless repository && push_id

    payload = {
      actor: actor ? Hydro::EntitySerializer.user(actor) : nil,
      repository: Hydro::EntitySerializer.repository(repository),
      repository_owner: Hydro::EntitySerializer.user(repository.owner),
      push_id: push_id,
    }
    GitHub.sync_hydro_publisher.publish(payload, schema: "github.v1.RepositoryPushConduit")
  end
end
