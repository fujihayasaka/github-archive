# typed: true
# frozen_string_literal: true

class HydroUpdateDenormalizedSourceToForksJob < Repositories::RepositoryHydroMessageJob
  queue_as :hydro_update_denormalized_source_to_forks

  discard_on ActiveRecord::RecordNotFound

  # Public: process a Hydro message
  sig { void }
  def perform
    owner = repository.owner
    return unless repository.owner&.feature_flag_enabled?("partitioning_update_same_network_repos_on_create_update", default: false)

    GitHub.logger.info("HydroUpdateDenormalizedSourceToForksJob processing", {
      "messaging.topic": topic,
      "gh.repository.id": repository.id,
      "gh.repository.source_id": repository.source_id,
      "gh.owner.id": repository.owner_id,
      "gh.owner.login": owner.try(:login),
    })

    source_id = repository.source_id
    id = repository.id

    same_network_repos_denormalized_store ||= GitHub::Partitioning::Denormalization::DenormalizedStore.new(
      service: :pull_requests,
      namespace: :same_network_repos
    )

    if topic == "github.repositories.v1.Created" || topic == "github.repositories.v2.Restored"
      same_network_repos_denormalized_store.add_to_sorted_array(source_id, id)
    elsif topic == "github.repositories.v1.Deleted"
      same_network_repos_denormalized_store.delete_from_array(source_id, id)
    end
  end
end
