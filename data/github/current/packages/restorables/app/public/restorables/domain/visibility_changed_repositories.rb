# typed: strict
# frozen_string_literal: true

module Restorables
  class Domain
    class VisibilityChangedRepositories < GH::Domain::Base
      # Public: Ensures that a VisibilityChangedRepository restoration is in the saving state for a repository. Returns
      # the currently active restoration if one is underway or starts a new one if not.
      sig { params(repository: Repositories::IRepository).returns(Restorables::IVisibilityChangedRepository) }
      def ensure_started(repository)
        Restorable::VisibilityChangedRepository.ensure_started(repository)
      end

      # Public: Returns a VisibilityChangedRepository restoration in a saving state for a repository, if one exists.
      # Otherwise, returns a null object.
      sig { params(repository: Repositories::IRepository).returns(Restorables::IVisibilityChangedRepository) }
      def continue(repository)
        Restorable::VisibilityChangedRepository.continue(repository)
      end

      # Public: Returns the most recent VisibilityChangedRepository restoration for a repository, if one exists.
      # Otherwise, returns a null object.
      sig { params(repository: Repositories::IRepository).returns(Restorables::IVisibilityChangedRepository) }
      def current(repository)
        Restorable::VisibilityChangedRepository.current(repository)
      end

      # Public: Begin the restoration process for all active VisibilityChangedRepositories found for a certain
      # repository. Return true if any restoration data was found to process or false if there was none.
      sig do
        params(repository: Repositories::IRepository)
          .returns(T::Boolean)
          .checked(:always).on_failure(:raise)
      end
      def restore_from(repository)
        restorables = Restorable::VisibilityChangedRepository.restorable_for_repository(repository)
        restorables.each(&:restore)
        restorables.any?
      end

      # Public: Cancel any active visibility change restorations that are currently in progress. Return true if any
      # operations were stopped or false if there were none.
      sig do
        params(repository: Repositories::IRepository)
          .returns(T::Boolean)
          .checked(:always).on_failure(:raise)
      end
      def cancel_restorations(repository)
        restorables = Restorable::VisibilityChangedRepository.restoring_for_repository(repository)
        restorables.each(&:cancel)
        restorables.any?
      end
    end
  end
end
