# typed: strict
# frozen_string_literal: true

module Stafftools
  module Repositories
    include GitHub::Memoizer
    class StarsAndWatchersRecoveryComponent < ApplicationComponent
      sig { params(repository: ::Repository).void }
      def initialize(repository)
        @repository = repository
      end

      sig { returns(T::Boolean) }
      memoize def recovery_data_available?
        return false unless visibility_change_restoration.restorable?

        !restoration_counts.empty?
      end

      sig { returns(T::Boolean) }
      memoize def storage_in_progress?
        visibility_change_restoration.saving?
      end

      sig { returns(T::Boolean) }
      memoize def recovery_in_progress?
        visibility_change_restoration.restoring?
      end

      sig { returns(T.nilable(Time)) }
      memoize def recovery_in_progress_elapsed_time
        vcr = visibility_change_restoration

        if vcr.restoring?
          vcr.updated_at
        else
          nil
        end
      end

      sig { returns(T.nilable(String)) }
      memoize def recovery_status_message
        if recovery_data_available? && @repository.private?
          "Recovery data is available but the repository is private, social data would not be recovered for users that don't have permission for this repository."
        elsif storage_in_progress?
          "Recovery data is currently being generated for this repository."
        elsif recovery_in_progress?
          "An active recovery operation has been in progress for "
        elsif !recovery_data_available?
          "No recent recovery data is currently available for this repository."
        else
          nil
        end
      end

      sig { returns(T.nilable(String)) }
      memoize def recovery_count_message
        prefix_text = if recovery_data_available?
          "Available to recover: "
        elsif recovery_in_progress?
          "Remaining to recover: "
        end
        return nil unless prefix_text

        nonzero_count_texts = [
          [restoration_counts.repository_stars_count, "star"],
          [restoration_counts.watched_repositories_count, "watcher"],
          [restoration_counts.custom_watched_repositories_count, "custom watcher"],
          [restoration_counts.watched_repository_threads_count, "watched thread"]
        ].filter_map { |count, noun| "#{count} #{noun.pluralize(count)}" if count.positive? }
        "#{prefix_text}#{nonzero_count_texts.to_sentence}."
      end

      private

      sig { returns(Restorables::IVisibilityChangedRepository) }
      memoize def visibility_change_restoration
        Restorables.domain.visibility_changed_repositories.current(@repository)
      end

      sig { returns(Restorables::VisibilityChangedRepositoryCounts) }
      memoize def restoration_counts
        vcr = visibility_change_restoration
        if vcr.restoring?
          Restorables.domain.visibility_changed_repositories.restoring_counts(@repository)
        else
          Restorables.domain.visibility_changed_repositories.restorable_counts(@repository)
        end
      end
    end
  end
end
