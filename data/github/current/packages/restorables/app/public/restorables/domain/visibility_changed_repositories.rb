# typed: strict
# frozen_string_literal: true

module Restorables
  class Domain
    class VisibilityChangedRepositories < GH::Domain::Base
      # Public: Ensures that a VisibilityChangedRepository restoration is in the saving state for a repository. Returns
      # the currently active restoration if one is underway or starts a new one if not.
      sig do
        params(repository: Repositories::IRepository)
          .returns(Restorables::IVisibilityChangedRepository)
          .checked(:always).on_failure(:raise)
      end
      def ensure_started(repository)
        Restorable::VisibilityChangedRepository.ensure_started(repository)
      end

      # Public: Returns a VisibilityChangedRepository restoration in a saving state for a repository, if one exists.
      # Otherwise, returns a null object.
      sig do
        params(repository: Repositories::IRepository)
          .returns(Restorables::IVisibilityChangedRepository)
          .checked(:always).on_failure(:raise)
      end
      def continue(repository)
        Restorable::VisibilityChangedRepository.continue(repository)
      end

      # Public: Returns the most recent VisibilityChangedRepository restoration for a repository, if one exists.
      # Otherwise, returns a null object.
      sig do
        params(repository: Repositories::IRepository)
          .returns(Restorables::IVisibilityChangedRepository)
          .checked(:always).on_failure(:raise)
      end
      def current(repository)
        Restorable::VisibilityChangedRepository.current(repository)
      end

      # Public: Initialize saving state for watcher-related restorable types. A no-op if the ID is nil or the
      # restoration cannot be found.
      #
      # restorable_id - The Integer ID of the VisibilityChangedRepository restoration record, or nil if it came from
      #   a null object.
      # remaining - Integer representing the number of iterative steps that must report completion before the watcher
      #   types are considered fully saved.
      #
      # Returns true if all TypeStates were created successfully, false otherwise. Returns false if ID is nil or
      #   the restoration cannot be found.
      sig do
        params(
          restorable_id: T.nilable(Integer),
          remaining: Integer
        ).returns(T::Boolean).checked(:always).on_failure(:raise)
      end
      def start_saving_watchers(restorable_id:, remaining:)
        Restorable::VisibilityChangedRepository.by_id(restorable_id)
          .start_saving_watchers(remaining: remaining)
      end

      # Public: Report progress on saving watcher-related restorable types by reporting completion of one or more
      # discrete steps. If this is the final step we were told to anticipate with the call to .start_saving_watchers,
      # mark watcher types as saved. A no-op if the ID is nil or the restoration cannot be found.
      #
      # restorable_id - The Integer ID of the VisibilityChangedRepository restoration record, or nil if it came from
      #   a null object.
      # decrement_by - Integer amount to decrement by (default: 1)
      #
      # Returns true if all requested types were successfully processed, false otherwise. Returns false if ID is nil
      #   or the restoration cannot be found.
      sig do
        params(
          restorable_id: T.nilable(Integer),
          decrement_by: Integer
        ).returns(T::Boolean).checked(:always).on_failure(:raise)
      end
      def report_saving_watchers_progress(restorable_id:, decrement_by: 1)
        Restorable::VisibilityChangedRepository.by_id(restorable_id)
          .report_saving_watchers_progress(decrement_by)
      end

      # Public: Saves custom watched repository subscriptions as part of a visibility change restoration process.
      # This method stores the provided subscriptions data to be restored later if the repository visibility
      # is reverted back to its original state. A no-op if the ID is nil or the restoration cannot be found.
      #
      # restorable_id - The Integer ID of the VisibilityChangedRepository restoration record, or nil if it came from
      #   a null object.
      # subscriptions - An Array of CustomWatchedRepositorySubscription objects to be saved for restoration
      #
      # Returns nothing.
      sig do
        params(
          restorable_id: T.nilable(Integer),
          subscriptions: T::Array[Restorables::CustomWatchedRepositorySubscription]
        ).void.checked(:always).on_failure(:raise)
      end
      def save_custom_watched_repositories(restorable_id:, subscriptions:)
        Restorable::VisibilityChangedRepository.by_id(restorable_id)
          .save_custom_watched_repositories(subscriptions)
      end

      # Public: Marks the saving of custom watched repositories as complete for a specific visibility change
      # restoration. This method is called to indicate that all custom watched repository subscriptions have been
      # successfully saved and the restoration process is ready for the next phase. A no-op if the ID is nil or the
      # restoration cannot be found.
      #
      # restorable_id - The Integer ID of the VisibilityChangedRepository restoration record, or nil if it came from
      #   a null object.
      #
      # Returns nothing.
      sig do
        params(restorable_id: T.nilable(Integer))
          .void.checked(:always).on_failure(:raise)
      end
      def save_custom_watched_repositories_complete(restorable_id:)
        Restorable::VisibilityChangedRepository.by_id(restorable_id)
          .save_custom_watched_repositories_complete
      end

      # Public: Saves watched repository thread subscriptions as part of a visibility change restoration process.
      # This method stores the provided thread subscriptions data to be restored later if the repository visibility
      # is reverted back to its original state. A no-op if the ID is nil or the restoration cannot be found.
      #
      # restorable_id - The Integer ID of the VisibilityChangedRepository restoration record, or nil if it came from
      #   a null object.
      # threads - An Array of WatchedRepositoryThreadSubscription objects to be saved for restoration
      #
      # Returns nothing.
      sig do
        params(
          restorable_id: T.nilable(Integer),
          threads: T::Array[Restorables::WatchedRepositoryThreadSubscription]
        ).void.checked(:always).on_failure(:raise)
      end
      def save_watched_repository_threads(restorable_id:, threads:)
        Restorable::VisibilityChangedRepository.by_id(restorable_id)
          .save_watched_repository_threads(threads)
      end

      # Public: Marks the saving of watched repository threads as complete for a specific visibility change
      # restoration. This method is called to indicate that all watched repository thread subscriptions have been
      # successfully saved and the restoration process is ready for the next phase. A no-op if the ID is nil or the
      # restoration cannot be found.
      #
      # restorable_id - The Integer ID of the VisibilityChangedRepository restoration record, or nil if it came from
      #   a null object.
      #
      # Returns nothing.
      sig do
        params(restorable_id: T.nilable(Integer))
          .void.checked(:always).on_failure(:raise)
      end
      def save_watched_repository_threads_complete(restorable_id:)
        Restorable::VisibilityChangedRepository.by_id(restorable_id)
          .save_watched_repository_threads_complete
      end

      # Public: Saves watched repository subscriptions as part of a visibility change restoration process.
      # This method stores the provided repositories data to be restored later if the repository visibility
      # is reverted back to its original state. A no-op if the ID is nil or the restoration cannot be found.
      #
      # restorable_id - The Integer ID of the VisibilityChangedRepository restoration record, or nil if it came from
      #   a null object.
      # repositories - An Array of Repository objects to be saved for restoration
      #
      # Returns nothing.
      sig do
        params(
          restorable_id: T.nilable(Integer),
          repositories: T::Array[Restorables::IWatchedRepositorySubscription]
        ).void.checked(:always).on_failure(:raise)
      end
      def save_watched_repositories(restorable_id:, repositories:)
        Restorable::VisibilityChangedRepository.by_id(restorable_id)
          .save_watched_repositories(repositories)
      end

      # Public: Marks the saving of watched repositories as complete for a specific visibility change
      # restoration. This method is called to indicate that all watched repository subscriptions have been
      # successfully saved and the restoration process is ready for the next phase. A no-op if the ID is nil or the
      # restoration cannot be found.
      #
      # restorable_id - The Integer ID of the VisibilityChangedRepository restoration record, or nil if it came from
      #   a null object.
      #
      # Returns nothing.
      sig do
        params(restorable_id: T.nilable(Integer))
          .void.checked(:always).on_failure(:raise)
      end
      def save_watched_repositories_complete(restorable_id:)
        Restorable::VisibilityChangedRepository.by_id(restorable_id)
          .save_watched_repositories_complete
      end

      # Public: Begin the restoration process for all active VisibilityChangedRepositories found for a certain
      # repository. Return true if any restoration data was found to process or false if there was none.
      #
      # repository - The Repository to recover social data for, if available
      # actor - The User performing the restoration operation
      sig do
        params(repository: Repositories::IRepository, actor: User)
          .returns(T::Boolean)
          .checked(:always).on_failure(:raise)
      end
      def restore_from(repository, actor:)
        restorables = Restorable::VisibilityChangedRepository.restorable_for_repository(repository)
        restorables.each { |restorable| restorable.restore(actor: actor) }
        restorables.any?
      end

      # Public: Cancel any active visibility change restorations that are currently in progress. Return true if any
      # operations were stopped or false if there were none.
      #
      # repository - The Repository to cancel active restorations for, if any
      # actor - The User performing the cancellation operation
      sig do
        params(repository: Repositories::IRepository, actor: User)
          .returns(T::Boolean)
          .checked(:always).on_failure(:raise)
      end
      def cancel_restorations(repository, actor:)
        restorables = Restorable::VisibilityChangedRepository.restoring_for_repository(repository)
        restorables.each { |restorable| restorable.cancel(actor: actor) }
        restorables.any?
      end

      # Public: Get total counts of stars and different types of watchers that are available to be restored
      # for a repository.
      #
      # repository - The Repository to get restorable counts for
      #
      # Returns a VisibilityChangedRepositoryCounts object with counts for each type of restorable data
      sig do
        params(repository: Repositories::IRepository)
          .returns(Restorables::VisibilityChangedRepositoryCounts)
          .checked(:always).on_failure(:raise)
      end
      def restorable_counts(repository)
        restorables = Restorable::VisibilityChangedRepository.restorable_for_repository(repository)
        Restorable::VisibilityChangedRepository.total_counts_for(restorables)
      end

      # Public: Get total counts of stars and different types of watchers that are in the process of being
      # restored for a repository.
      #
      # repository - The Repository to get restoring counts for
      #
      # Returns a VisibilityChangedRepositoryCounts object with counts for each type of restorable data currently being restored
      sig do
        params(repository: Repositories::IRepository)
          .returns(Restorables::VisibilityChangedRepositoryCounts)
          .checked(:always).on_failure(:raise)
      end
      def restoring_counts(repository)
        restorables = Restorable::VisibilityChangedRepository.restoring_for_repository(repository)
        Restorable::VisibilityChangedRepository.total_counts_for(restorables)
      end
    end
  end
end
