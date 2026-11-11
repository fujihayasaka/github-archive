# typed: strict
# frozen_string_literal: true

# Public: This is a null copy of Restorable::VisibilityChangedRepository returned when a restorable isn't found so
# that calling code doesn't have to use any conditionals and can just treat a restorable as a restorable.
#
# Generally, callers should use the state predicates #saving? or #restorable? to determine if the instance they have
# is appropriate for use.
class Restorable
  class NullVisibilityChangedRepository
    include Restorable::IPrivateVisibilityChangedRepository

    sig { params(repository: ::Repositories::IRepository).returns(IPrivateVisibilityChangedRepository) }
    def self.ensure_started(repository)
      new
    end

    sig { params(repository: ::Repositories::IRepository).returns(IPrivateVisibilityChangedRepository) }
    def self.continue(repository)
      new
    end

    sig { override.returns(T.nilable(Integer)) }
    def id
      nil
    end

    sig { override.returns(T::Boolean) }
    def saving?
      false
    end

    sig { override.returns(T::Boolean) }
    def restorable?
      false
    end

    sig { override.returns(T::Boolean) }
    def restoring?
      false
    end

    sig { override.returns(T::Boolean) }
    def restored?
      false
    end

    sig { override.returns(Time) }
    def updated_at
      Time.zone.now
    end

    sig { override.params(stars: T::Enumerable[StarEntity]).void }
    def save_stars(stars) ; end

    sig { override.void }
    def save_stars_complete ; end

    sig { override.params(remaining: Integer).returns(T::Boolean) }
    def start_saving_watchers(remaining:)
      false
    end

    sig { override.params(decrement_by: Integer).returns(T::Boolean) }
    def report_saving_watchers_progress(decrement_by = 1)
      false
    end

    sig { override.params(repositories: T::Array[Restorables::IWatchedRepositorySubscription]).void }
    def save_watched_repositories(repositories) ; end

    sig { override.void }
    def save_watched_repositories_complete ; end

    sig { override.params(subscriptions: T::Array[Restorables::CustomWatchedRepositorySubscription]).void }
    def save_custom_watched_repositories(subscriptions) ; end

    sig { override.void }
    def save_custom_watched_repositories_complete ; end

    sig { override.params(threads: T::Array[Restorables::WatchedRepositoryThreadSubscription]).void }
    def save_watched_repository_threads(threads) ; end

    sig { override.void }
    def save_watched_repository_threads_complete ; end

    sig { override.params(actor: T.nilable(User)).void }
    def restore(actor: nil) ; end

    sig { override.params(actor: T.nilable(User)).void }
    def cancel(actor: nil) ; end

    sig { override.returns(T.nilable(Restorable)) }
    def restorable
      nil
    end
  end
end
