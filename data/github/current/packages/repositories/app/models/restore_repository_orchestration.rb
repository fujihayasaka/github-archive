# typed: false
# frozen_string_literal: true
class RestoreRepositoryOrchestration < RepositoryOrchestration
  include GitHub::Memoizer

  validate :can_restore?, on: :create

  def can_restore?
    if repository.destroyed?
      self.errors.add(:base, "Repository does not exist")
    end
    unless Repository.can_restore?(repository, override_restorable: data[:override_restorable])
      error_key = repository.errors.attribute_names.first
      error = repository.errors.messages[error_key].first
      self.errors.add(:base, error)
    end
  end

  step :acquire_namespace_lock do
    Repositories::RepositoryOwnerLock.acquire_rename_lock(owner_id: repository.owner_id)
  end

  job_start

  step :mark_deleted do
    status.message = "Restoring DB data..."

    # skip the search index synchronization that is normally done from after_commit
    # since the dgit route resolution will fail. The search index will be
    # populated separately later in this method via reindex_all
    repository.skip_search_index_sync = true

    # some records in the archived_repositories table have messed up deleted
    # values. we need to make sure the record is marked deleted = 1
    # immediately after restoring or various subsequent logic will fail.
    # See #unhide for example.
    repository.update(active: nil, owner_login: repository.owner.login)

    # Pysch (serializer lib) only allows Time, not TimeWithZone, so convert here.
    data[:deleted_at] = repository.deleted_at.to_time
  end

  step :restore_grants do
    return unless repository.in_organization?

    # restore admin-on-owner grants:
    repository.organization.dependent_added repository
  end

  step :unhide_repo do
    begin
      Repository.transaction do
        repository.unhide

        data[:auth_version] = repository.increment_auth_version
        save!
      end
    rescue ActiveRecord::RecordNotUnique
      # If we get here, it's probably because a BulkRepositoryRestoreJob tried to restore two repos with the same name
      # to the same account simultaneously
      error = "Repository already exists on this account."
      status.message = error
      return :failed, error
    end

    status.message = Restoration::RepositoryRestoreStatus::COMPLETED_MESSAGE
  end

  step :reload_routes do
    repository.dgit_reload_routes!
  end

  step :restore_network do
    # restore any archived media objects
    repository.network&.restore
  end

  step :reset_git_cache do
    # reset the git refs cache and whatnot now that the repository is back in
    # business
    repository.reset_git_cache
  end

  step :calculate_network_counts do
    # Recalculate the number of forks in the network
    repository.calculate_network_counts! unless repository.network.nil?
  end

  step :remove_outside_collaborators do
    # Remove any collaborators that no longer meet the two factor requirements of the repo on restore
    repository.remove_outside_collaborators_with_two_factor_disabled(actor)
  end

  step :instrument_search_restore do
    # re-index the repository and its resources for search
    repository.instrument_search_restore({ auth_version: data[:auth_version] })

    # instrument, publish to hydro and statsd
    repository.instrument_restore(data[:initiated_by], actor)
  end

  step :reindex_all do
    repository.reindex_all
  end

  step :publish_restored do
    message = build_hydro_event_message.merge({
      actor_id: data[:actor_id],
      deleted_at: data[:deleted_at]
    })
    publish_hydro_event(message: message, schema: "github.repositories.v2.Restored")
  end

  step :enqueue_language_analysis do
    return if data[:synchronous]

    repository.enqueue_analyze_language_breakdown
  end

  step :release_namespace_lock do
    Repositories::RepositoryOwnerLock.release_rename_lock(owner_id: repository.owner_id)
  end

  on_end_orchestration do |error_message, error_klass|
    return if data[:synchronous]
    return unless (failed? && error_message == "max attempts") || (running? && !error_klass.nil?)

    status.message = Restoration::RepositoryRestoreStatus::FAILED_MESSAGE
  end

  def self.most_recent_restore_orchestration_for(repository:)
    return nil unless repository.present?

    RestoreRepositoryOrchestration.most_recent_for_repository(repository.id).first
  end

  memoize def actor
    User.find_by_id(data[:actor_id])
  end

  memoize def status
    Restoration::RepositoryRestoreStatus.for(repository_id: repository.id)
  end
end
