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
    include Restorable::IVisibilityChangedRepository

    belongs_to :restorable
    belongs_to_repository_via_domain

    validates :restorable, presence: true, uniqueness: true
    validates :repository, presence: true

    # Internal: Primary scope for finding most recent restorable settings for a repository.
    #
    # repo_id - A Repository ID.
    scope :most_recent, -> (repo_id) { where({ repository_id: repo_id }).order(id: :desc) }

    TYPES = [
      :restorable_repository_stars,
      :restorable_watched_repositories,
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
    # Outside of the stars package, use the domain accessor instead:
    #
    #   Stars.domain.ensure_visibility_change_restoration_started(repo)
    sig { params(repository: ::Repositories::IRepository).returns(IVisibilityChangedRepository) }
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
    # Outside of the stars packwerk package, use the domain accessor instead:
    #
    #   Stars.domain.continue_visibility_change_restoration(repo)
    sig { params(repository: ::Repositories::IRepository).returns(IVisibilityChangedRepository) }
    def self.continue(repository)
      instance = most_recent(repository.id).first
      if instance&.saving?
        instance
      else
        NullVisibilityChangedRepository.new
      end
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

    sig { override.params(stars: T::Enumerable[StarEntity]).void }
    def save_stars(stars)
      Restorable::RepositoryStar.backup_from_stars(restorable: restorable, stars: stars)
    end

    # Public: Mark restorable_repository_stars as saved.
    sig { override.void }
    def save_stars_complete
      T.must(restorable).saved(:restorable_repository_stars)
    end
  end
end
