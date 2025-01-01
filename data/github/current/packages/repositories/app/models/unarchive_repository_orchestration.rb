# typed: false
# frozen_string_literal: true

class UnarchiveRepositoryOrchestration < RepositoryOrchestration
  include GitHub::Memoizer

  validate :can_unarchive?, on: :create

  def can_unarchive?
    owner = repository.owner
    if owner.organization? && owner.archived?
      return errors.add(:repository, :owner, message: "Owner is archived")
    end
    repository.maintained = true
    repository.archived_at = nil

    repository.skip_search_index_sync = true

    if !repository.valid?
      repository.errors.each do |error|
        errors.add(:repository, error.attribute, message: error.full_message)
      end
    end
  end

  step :unarchive_repository, transaction: true do
    repository.save!

    data[:auth_version] = repository.increment_auth_version
  end

  job_start

  step :publish_unarchived do
    message = self.class.build_hydro_event_message(repository_id)
    message.merge!(actor_id: data[:actor_id])
    publish_hydro_event(message: message, schema: "github.repositories.v1.Unarchived")
  end

  step :instrument_unarchive do
    repository.instrument(:unarchived, actor: actor)
    # Instrumentation to publish hydro event
    GlobalInstrumenter.instrument("repository.archived_status_changed", {
      repository_id: repository.id,
      repository_global_id: repository.global_relay_id,
      is_archived: false,
      actor_id: actor.id,
    })

    GlobalInstrumenter.instrument("search_indexing.repository_changed", {
      change: :UNARCHIVED,
      repository: repository,
      auth_version: data[:auth_version],
    })
  end

  step :redetect_manifest do
    # Start manifest redetection process for dependency graph
    RepositoryDependencyManifestInitializationJob.perform_later(repository.id) if repository.dependency_graph_enabled?
  end

  step :update_search_index do
    # Reindex issues, discussions, and PRs to update archived attributes
    Search.add_to_search_index("bulk_issues", repository.id, "purge" => true)
    Search.add_to_search_index("bulk_discussions", repository.id, "purge" => true)
    Search.add_to_search_index("bulk_pull_requests", repository.id, "purge" => true)

    repository.synchronize_search_index
  end

  step :toggle_security_product_services do
    SecurityProduct::ServiceManager.new(repository).toggle_services_on_repository_state_changed(actor: actor)
  end

  attr_writer :actor

  private

  def actor
    return @actor if defined?(@actor)

    @actor = User.find_by_id(data[:actor_id])
  end
end
