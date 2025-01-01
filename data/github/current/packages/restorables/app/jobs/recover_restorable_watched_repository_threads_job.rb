# typed: strict
# frozen_string_literal: true

class RecoverRestorableWatchedRepositoryThreadsJob < ApplicationJob
  include RestorableRecoveryJob

  queue_as :recover_restorable_watched_repository_threads

  retry_on_dirty_exit

  READ_BATCH_SIZE = 1000
  WRITE_BATCH_SIZE = 100

  sig { params(restorable_id: Integer).void }
  def perform(restorable_id:)
    restorable = load_restorable(restorable_id, [:restorable_watched_repository_threads])
    return unless restorable

    repository = Restorable::VisibilityChangedRepository.find_by(restorable: restorable)&.repository
    return unless repository

    batch = with_read do
      results = restorable.watched_repository_threads.order(id: :asc).limit(READ_BATCH_SIZE)
      GitHub::PrefillAssociations.prefill_associations(results, [:user])
      results
    end

    batch.in_groups_of(WRITE_BATCH_SIZE, false) do |group|
      process_watched_repository_threads_batch(group, repository)
    end

    if batch.size == READ_BATCH_SIZE
      self.class.perform_later(restorable_id: restorable_id)
    else
      with_write { restorable.restored(:restorable_watched_repository_threads) }
    end
  end

  private

  sig { params(group: T::Array[Restorable::WatchedRepositoryThread], repository: Repositories::IRepository).void }
  def process_watched_repository_threads_batch(group, repository)
    # Check validity of users once per unique user
    users = group.filter_map(&:user).uniq
    skip_users = users_to_skip(users)

    # Efficiently load thread models for this group.
    threads = threads_by_wrt(group)

    group.each do |restorable_watched_thread|
      watching_user = restorable_watched_thread.user
      next if watching_user.nil?
      next if skip_users.include?(watching_user)
      next if forbid_subscription?(watching_user, repository)

      thread_model = threads[restorable_watched_thread]
      next unless thread_model

      next if user_already_subscribed_to_thread?(watching_user, repository, thread_model)

      Newsies::ThreadSubscription.throttle_writes do
        if restorable_watched_thread.ignored?
          ::Notifications::Subscriptions.unsubscribe_from_thread(
            watching_user,
            thread_model,
          )
        else
          ::Notifications::Subscriptions.subscribe_to_thread(
            watching_user,
            repository,
            thread_model,
            restorable_watched_thread.reason,
          )
        end
      end
    end

    # Delete the processed batch
    Restorable::WatchedRepositoryThread.throttle do
      with_write { group.each(&:destroy!) }
    end
  end

  # Load ActiveRecord thread models (Issue, PullRequest, Release, whatever) corresponding to a batch of
  # WatchedRepositoryThreads in an efficient way by issuing a single SELECT per thread type. Any malformed
  # thread keys, thread keys that reference bad types, or thread models that no longer exist will be omitted.
  #
  # Returns a Hash mapping each Restorable::WatchedRepositoryThread to its corresponding thread model or nil.
  sig do
    params(watched_repository_threads: T::Enumerable[Restorable::WatchedRepositoryThread])
      .returns(T::Hash[Restorable::WatchedRepositoryThread, T.untyped])
  end
  def threads_by_wrt(watched_repository_threads)
    # Deserialize Newsies::Thread objects from the stored thread_key values. Group WatchedRepositoryThread models
    # by the thread they correspond to. Note that multiple WatchedRepositoryThreads may correspond to the same thread,
    # so this is a T::Hash[Newsies::Thread, T::Array[Restorable::WatchedRepositoryThread]].
    by_threads = watched_repository_threads.group_by do |restorable_watched_thread|
      Newsies::Thread.from_key(restorable_watched_thread.thread_key)
    rescue Newsies::Object::InvalidKey
      nil
    end
    by_threads.delete(nil) # Omit any threads that couldn't be deserialized

    thread_models = {}
    by_threads.keys.group_by(&:type).each do |thread_type, threads|
      # Attempt to load the thread model class from the type string. Note that this will skip commit threads, which
      # are stored with the type "Grit::Commit". That's fine, it would be hard to load the commit again anyway.
      model_class = thread_type.constantize

      # Skip non-ActiveRecord thread models. Currently, all Newsies::Thread::POSSIBLE_THREAD_TYPES other than
      # Commit pass this check.
      next unless model_class.respond_to?(:where)

      # Load all thread models for the threads of this type in a single query. (The limit is to keep Query Guard
      # happy and guard against the ID list going haywire somehow.)
      threads_by_id = threads.index_by(&:id)
      model_class.where(id: threads_by_id.keys).limit(WRITE_BATCH_SIZE).each do |thread_model|
        thread = threads_by_id[Newsies::Object.to_id(thread_model).to_s]
        next unless thread

        # Associate each loaded thread model (Issue, PullRequest, etc.) with the WatchedRepositoryThread whose key
        # referenced it.
        by_threads.fetch(thread, []).each do |restorable_watched_thread|
          thread_models[restorable_watched_thread] = thread_model
        end
      end
    rescue NameError
      # The thread key's type didn't correspond to a real model.
      nil
    end

    thread_models
  end

  # Determine if the user has already re-subscribed to the repository or thread.
  sig { params(user: User, repository: Repositories::IRepository, thread: T.untyped).returns(T::Boolean) }
  def user_already_subscribed_to_thread?(user, repository, thread)
    # Check notification_subscriptions and notification_thread_type_subscriptions
    return true if user_already_subscribed?(user, repository)

    notifyd_sub = ::Notifications::Subscriptions.subscription_status(user, repository, thread)
    notifyd_sub.valid?
  end
end
