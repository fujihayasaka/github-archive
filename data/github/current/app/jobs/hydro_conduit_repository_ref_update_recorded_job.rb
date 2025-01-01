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
    repository = Repository.find_by(id: repository_id)

    return unless repository && push_id

    emit_dogstats
    payload = {
      actor: actor ? Hydro::EntitySerializer.user(actor) : nil,
      repository: Hydro::EntitySerializer.repository(repository),
      repository_owner: Hydro::EntitySerializer.user(repository.owner),
      push_id: push_id,
    }
    GitHub.sync_hydro_publisher.publish(payload, schema: "github.v1.RepositoryPushConduit")
  end

  private

  def emit_dogstats
    if created?
      GitHub.dogstats.increment("conduit.push_event_create")
    elsif deleted?
      GitHub.dogstats.increment("conduit.push_event_delete")
    else
      GitHub.dogstats.increment("conduit.push_event_push")
    end
  end

  def created?
    message[:before] == GitHub::NULL_OID
  end

  def deleted?
    message[:after] == GitHub::NULL_OID
  end
end
