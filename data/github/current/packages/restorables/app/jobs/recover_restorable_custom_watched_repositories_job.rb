# typed: strict
# frozen_string_literal: true

class RecoverRestorableCustomWatchedRepositoriesJob < ApplicationJob
  include RestorableRecoveryJob

  queue_as :recover_restorable_custom_watched_repositories

  retry_on_dirty_exit

  READ_BATCH_SIZE = 1000
  WRITE_BATCH_SIZE = 100

  sig { params(restorable_id: Integer).void }
  def perform(restorable_id:)
    restorable = load_restorable(restorable_id, [:restorable_custom_watched_repositories])
    return unless restorable

    repository = Restorable::VisibilityChangedRepository.find_by(restorable: restorable)&.repository
    return unless repository

    batch = Batch.load_next(restorable: restorable).prefill_associations
    batch.each_subscription_batch do |subscription_batch|
      process_subscription_batch(subscription_batch, repository)
    end

    if batch.remaining?
      self.class.perform_later(restorable_id: restorable_id)
    else
      with_write { restorable.restored(:restorable_custom_watched_repositories) }
    end
  end

  private

  sig do
    params(
      sub_batch: T::Array[UserCustomSubscription],
      repository: Repositories::IRepository,
    ).void
  end
  def process_subscription_batch(sub_batch, repository)
    # Check validitity of users once per unique user
    users = sub_batch.filter_map(&:user).uniq
    skip_users = users_to_skip(users)

    processed = T.let([], T::Array[Restorable::CustomWatchedRepository])
    sub_batch.each do |user_subscription|
      processed.concat(user_subscription.custom_watched_repositories)

      watching_user = user_subscription.user
      next if watching_user.nil?
      next if skip_users.include?(watching_user)
      next if forbid_subscription?(watching_user, repository)
      next if user_already_subscribed?(watching_user, repository)
      next if GitHub.newsies.subscription_limit_exceeded?(watching_user, repository).value

      Newsies::ThreadTypeSubscription.throttle_writes do
        GitHub.newsies.subscribe_to_thread_types(watching_user, repository, user_subscription.thread_type_classes)
      end
    end

    # Delete the processed batch
    Restorable::CustomWatchedRepository.throttle do
      with_write { processed.each(&:destroy!) }
    end
  end

  # Utility class to handle loading batches of custom watched repositories in such a way that all records associated
  # with a single user are processed together. This is necessary to ensure that we re-subscribe each user to all
  # of the thread types they were subscribed to before all at once.
  class Batch
    # Loads the next batch of custom watched repositories, ensuring that we do not exceed READ_BATCH_SIZE or risk
    # breaking up records associated with a user across multiple batches.
    #
    # Raises an exception if more than READ_BATCH_SIZE custom watched repositories are found for a single user. We
    # have one record per thread type and far fewer than 1000 unique thread types so this should not happen in
    # practice.
    sig { params(restorable: Restorable).returns(Batch) }
    def self.load_next(restorable:)
      # Order by user_id to ensure that all records associated with a single user are returned together. We don't
      # care about a sub-order because we delete processed records and never deal with partial groups.
      custom_watched_repositories = restorable.custom_watched_repositories
        .order(user_id: :asc)
        .limit(READ_BATCH_SIZE)
        .to_a
      return new([], false) if custom_watched_repositories.empty?

      # If we got back fewer records than our limit, we know that this is all of them.
      return new(custom_watched_repositories, false) if custom_watched_repositories.size < READ_BATCH_SIZE

      # The final "run" of records associated with a user may be truncated across the batch boundary. Drop these
      # records so that we don't risk splitting them across batches.
      last_id = custom_watched_repositories.last&.user_id
      batch = custom_watched_repositories.reverse.drop_while { |repo| repo.user_id == last_id }
      if batch.empty?
        # This is only possible when *all* of the records in this (full) batch were associated with the same user.
        # This could only happen if there were more than READ_BATCH_SIZE possible thread types.
        #
        # If it *did*, raising an exception here is better than returning an empty batch, because returning an
        # empty batch would cause an infinite loop of rescheduled jobs.
        raise RuntimeError, "More than #{READ_BATCH_SIZE} custom watched repositories for single user"
      end
      new(batch, true)
    end

    sig { returns(Batch) }
    def prefill_associations
      GitHub::PrefillAssociations.prefill_associations(@custom_watched_repositories, [:user])
      self
    end

    # Yield batches of loaded records grouped by subscribing user. At most WRITE_BATCH_SIZE records will be yielded
    # at a time. (We only perform one write per subscribing user, so this limits the write load.)
    sig do
      params(
        block: T.proc.params(custom_watched_repositories: T::Array[UserCustomSubscription]).void,
      ).void
    end
    def each_subscription_batch(&block)
      return if @custom_watched_repositories.empty?

      sub_batch = T.let([], T::Array[UserCustomSubscription])
      @custom_watched_repositories.chunk_while { |before, after| before.user_id == after.user_id }.each do |chunk|
        sub_batch << UserCustomSubscription.new(chunk)
        if sub_batch.size >= WRITE_BATCH_SIZE
          yield sub_batch
          sub_batch = []
        end
      end

      yield sub_batch unless sub_batch.empty?
    end

    # Should another job be scheduled to process more records?
    sig { returns(T::Boolean) }
    def remaining?
      @remaining
    end

    private

    sig do
      params(custom_watched_repositories: T::Array[Restorable::CustomWatchedRepository], remaining: T::Boolean).void
    end
    def initialize(custom_watched_repositories, remaining)
      @custom_watched_repositories = custom_watched_repositories
      @remaining = remaining
    end
  end

  # Utility class to group and summarize CustomWatchedRepository records associated with a single user. Returned
  # from `Batch#each_subscription_batch`.
  class UserCustomSubscription
    sig { params(custom_watched_repositories: T::Array[Restorable::CustomWatchedRepository]).void }
    def initialize(custom_watched_repositories)
      @user = T.let(custom_watched_repositories.first&.user, T.nilable(User))
      @thread_types = T.let(custom_watched_repositories.map(&:thread_type), T::Array[String])
      @original_created_at = T.let(custom_watched_repositories.maximum(:original_created_at), T.nilable(Time))

      @custom_watched_repositories = custom_watched_repositories
    end

    sig { returns(T::Array[T::Class[T.anything]]) }
    def thread_type_classes
      @thread_types.filter_map do |thread_type|
        thread_type.constantize
      rescue NameError
        nil
      end
    end

    sig { returns(T.nilable(User)) }
    attr_reader :user

    sig { returns(T.nilable(Time)) }
    attr_reader :original_created_at

    sig { returns(T::Array[Restorable::CustomWatchedRepository]) }
    attr_reader :custom_watched_repositories
  end
end
