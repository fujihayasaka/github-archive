# typed: strict
# frozen_string_literal: true

class Restorable
  # Private: Augment the public IVisibilityChangedRepository interface with package-private methods that are shared
  # between the null object and its real implementation, but perform write operations on the model. To expose this
  # functionality outside of the package, add dedicated methods to the public domain interface that load the correct
  # restorable and call these methods.
  module IPrivateVisibilityChangedRepository
    extend T::Helpers
    include Restorables::IVisibilityChangedRepository

    abstract!

    sig { abstract.params(stars: T::Enumerable[StarEntity]).void }
    def save_stars(stars); end

    sig { abstract.void }
    def save_stars_complete; end

    sig { abstract.params(remaining: Integer).returns(T::Boolean) }
    def start_saving_watchers(remaining:); end

    sig { abstract.params(decrement_by: Integer).returns(T::Boolean) }
    def report_saving_watchers_progress(decrement_by = 1); end

    sig { abstract.params(repositories: T::Array[Restorables::IWatchedRepositorySubscription]).void }
    def save_watched_repositories(repositories); end

    sig { abstract.void }
    def save_watched_repositories_complete; end

    sig { abstract.params(subscriptions: T::Array[Restorables::CustomWatchedRepositorySubscription]).void }
    def save_custom_watched_repositories(subscriptions); end

    sig { abstract.void }
    def save_custom_watched_repositories_complete; end

    sig { abstract.params(threads: T::Array[Restorables::WatchedRepositoryThreadSubscription]).void }
    def save_watched_repository_threads(threads); end

    sig { abstract.void }
    def save_watched_repository_threads_complete; end

    sig { abstract.params(actor: T.nilable(User)).void }
    def restore(actor: nil); end

    sig { abstract.params(actor: T.nilable(User)).void }
    def cancel(actor: nil); end

    sig { abstract.returns(T.nilable(Restorable)) }
    def restorable; end
  end
end
