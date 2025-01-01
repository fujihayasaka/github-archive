# typed: strict
# frozen_string_literal: true

class Restorable
  # Public: Restoration scenario class for a repository's visibility change event. Records the repository's stars and
  # watchers that will be lost after the visibility change has been completed and provides a mechanism for restoring
  # them later if the change is undone.
  #
  # Usage:
  #
  #   repo = Repository.find(1)
  #
  #   # To begin storing restoration data for a repository
  #   restorable = Restorable::VisibilityChangedRepository.ensure_started(repo)
  #
  #   # To store restoration data of a specific type
  #   restorable = Restorable::VisibilityChangedRepository.continue(repo)
  #   Star.for_repository(repo).find_in_batches(batch_size: BATCH_SIZE) do |star_batch|
  #     # Also accepts StarEntities from Stars.domain accessors
  #     restorable.save_stars(stars)
  #   end
  #   restorable.save_stars_complete
  #
  class VisibilityChangedRepository < ApplicationRecord::Domain::Restorables
    include ::Repositories::BelongsToRepository
    include Restorable::IPrivateVisibilityChangedRepository

    belongs_to :restorable
    belongs_to_repository_via_domain

    validates :restorable, presence: true, uniqueness: true
    validates :repository, presence: true

    # Internal: Primary scope for finding most recent restorable settings for a repository.
    #
    # repo_id - A Repository ID.
    scope :most_recent, -> (repo_id) { where({ repository_id: repo_id }).order(id: :desc) }

    # Internal: Maximum number of restorable records to return in repository queries.
    # This prevents excessive memory usage when many restorable records exist for a repository.
    MAX_RESTORABLE_RESULTS = 100

    TYPES = [
      :restorable_repository_stars,
      # :restorable_watched_repositories,
      # :restorable_custom_watched_repositories,
      # :restorable_watched_repository_threads,
    ]

    # Public: Ensure that an initialized restoration is in progress for a repository. This will return an existing
    # restoration if one is already underway or create a new one if necessary.
    #
    # This is to be called within the repository change orchestration job before any of the clean-up jobs have been
    # enqueued. Stars and watchers that are destroyed as a consequence of the visibility change operation will create
    # restorable type records associated with this restoration model.
    #
    # Because a restoration in progress will be returned if one is found, multiple visibility change operations in
    # rapid succession may associate their removed stars and watchers with the same restorable. The specific
    # restorable that type records are linked with primarily serves as a way to identify which records need to be
    # purged once they expire. When multiple visibility changes collide, their restorable timestamps would be quite
    # close regardless.
    #
    # Outside of the restorables package, use the domain accessor instead:
    #
    #   Restorables.domain.visibility_changed_repositories.ensure_started(repo)
    sig { params(repository: ::Repositories::IRepository).returns(IPrivateVisibilityChangedRepository) }
    def self.ensure_started(repository)
      # Check for an already-in-progress existing restoration and return that if it exists.
      existing = continue(repository)
      return existing if existing.saving?

      new(repository: repository) do |instance|
        instance.create_restorable!
        instance.save!
      end
    end

    # Public: Return a restoration that is currently underway for a repository. If none exist, a null object will
    # be returned instead.
    #
    # This is to be called within background jobs that destroy stars and watchers as a consequence of a repository
    # having its visibility changed.
    #
    # Outside of the restorable packwerk package, use the domain accessor instead:
    #
    #   Restorables.domain.visibility_changed_repositories.continue(repo)
    sig { params(repository: ::Repositories::IRepository).returns(IPrivateVisibilityChangedRepository) }
    def self.continue(repository)
      instance = most_recent(repository.id).first
      if instance&.saving?
        instance
      else
        NullVisibilityChangedRepository.new
      end
    end

    # Public: Return the most recent restoration for a repository. If none exist, a null object will be returned
    # instead.
    #
    # Outside of the restorables packwerk package, use the domain accessor instead:
    #
    #   Restorables.domain.current_visibility_change_restoration(repo)
    sig { params(repository: ::Repositories::IRepository).returns(IPrivateVisibilityChangedRepository) }
    def self.current(repository)
      if vcr = Restorable::VisibilityChangedRepository.most_recent(repository).first
        T.must(vcr.restorable).type_states.load
        vcr
      else
        Restorable::NullVisibilityChangedRepository.new
      end
    end

    sig do
      params(repository: ::Repositories::IRepository)
        .returns(T::Array[Restorable::IPrivateVisibilityChangedRepository])
    end
    def self.restorable_for_repository(repository)
      where(repository_id: repository.id)
        .limit(MAX_RESTORABLE_RESULTS)
        .order(id: :desc)
        .includes(restorable: :type_states)
        .to_a
        .select(&:restorable?)
    end

    sig do
      params(repository: ::Repositories::IRepository)
        .returns(T::Array[Restorable::IPrivateVisibilityChangedRepository])
    end
    def self.restoring_for_repository(repository)
      where(repository_id: repository.id)
        .limit(MAX_RESTORABLE_RESULTS)
        .order(id: :desc)
        .includes(restorable: :type_states)
        .to_a
        .select(&:restoring?)
    end

    # Public: Is this restoration in the process of saving records?
    #
    # An instance will be in this state after the repository visibility change has been started and before all of the
    # jobs that clean up stars and watchers from users who no longer have access to the repository have completed. At
    # that point, the instance will transition to the #restorable? state.
    sig { override.returns(T::Boolean) }
    def saving?
      T.must(restorable).saving?(TYPES)
    end

    # Public: Is this restoration ready to be restored?
    #
    # An instance will be in this state once all of the background jobs that process stars and watchers from users
    # who no longer have access to the repository have been completed and all restorable data has been persisted.
    sig { override.returns(T::Boolean) }
    def restorable?
      T.must(restorable).saved?(TYPES)
    end

    # Public: Is this restoration in the process of restoring records?
    #
    # An instance will be in this state after the repository visibility change has been undone and the restoration
    # process has been started. It will remain in this state until all of the background jobs that restore stars and
    # watchers have completed. At that point, the instance will transition to the #restored? state.
    sig { override.returns(T::Boolean) }
    def restoring?
      T.must(restorable).restoring?(TYPES)
    end

    # Public: Is this restoration completed?
    #
    # An instance will be in this state once all of the background jobs that restore stars and watchers have been
    # completed and all restorable data has been persisted.
    sig { override.returns(T::Boolean) }
    def restored?
      T.must(restorable).restored?(TYPES)
    end

    sig { override.params(stars: T::Enumerable[StarEntity]).void }
    def save_stars(stars)
      Restorable::RepositoryStar.backup(restorable: restorable, stars: stars)
    end

    # Public: Mark restorable_repository_stars as saved.
    sig { override.void }
    def save_stars_complete
      T.must(restorable).saved(:restorable_repository_stars)
    end

    # Public: Restore all linked Restorable types for this instance.
    #
    # This method calls the restore method on each linked Restorable type. This is used to restore the repository's
    # stars and watchers after a visibility change has been undone.
    #
    # Returns nothing. The receiver will be in a restoring? state after this method returns.
    sig { override.void }
    def restore
      return unless restorable?

      Restorable::RepositoryStar.restore(restorable: restorable)

      # Allows us to use #updated_at to determine when the current restoration was started.
      touch
    end

    # Public: Cancel an ongoing restoration process.
    #
    # This method finds all restorable types that are currently in the restoring state
    # and sets them back to saved state, effectively canceling the restoration process.
    #
    # Returns nothing.
    sig { override.void }
    def cancel
      return unless restoring?

      # Get all type states that are currently in the restoring state
      restoring_states = T.must(restorable).type_states.where(state: :restoring)

      # Update each state back to saved
      restoring_states.each do |type_state|
        type_state.update_attribute(:state, :saved)
      end
    end
  end
end
