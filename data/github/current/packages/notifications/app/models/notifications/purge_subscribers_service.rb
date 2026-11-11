# typed: true
# frozen_string_literal: true

module Notifications
  # Service encapsulating the core purge logic for removing notification
  # subscriptions from users who no longer have access to a repository.
  #
  # This service handles:
  #   - Fetching the next batch of subscriber user IDs via merged cursor pagination
  #   - Checking which users have lost access
  #   - Triggering async deletion of subscriptions for those users
  #
  class PurgeSubscribersService
    sig { params(repository: Repositories::IRepository, job_name: String).void }
    def initialize(repository:, job_name:)
      @repository_id = T.let(T.must(repository.id), Integer)
      @subject = T.let(Subject.new(type: "Repository", id: @repository_id), Subject)
      @repository = repository
      @tags = T.let(["job:#{job_name}"], T::Array[String])
    end

    # Public: Fetch the next batch of unique subscriber user IDs across all
    # subscription types, using merged cursor pagination.
    #
    # offset_id  - Integer user_id cursor. Returns users with user_id > offset_id.
    # batch_size - Integer max number of user IDs to return.
    #
    # Returns Array<Integer> of user IDs, sorted ascending, deduplicated,
    # with at most batch_size elements.
    sig { params(offset_id: Integer, batch_size: Integer).returns(T::Array[Integer]) }
    def fetch_next_batch(offset_id, batch_size:)
      batch = T.let([], T::Array[Integer])
      track_duration("notifications.newsies_purge_subscribers_job.dist.gather_user_ids_time") do
        batch = Subscriptions.all_repository_subscriber_ids(
          @repository_id, after: offset_id, limit: batch_size
        )
      end
      batch
    end

    # Public: Find user IDs from the batch that no longer have read access
    # to the repository.
    #
    # user_ids - Array<Integer> of user IDs to check.
    #
    # Returns Array<Integer> of user IDs without access.
    sig { params(user_ids: T::Array[Integer]).returns(T::Array[Integer]) }
    def user_ids_without_access(user_ids)
      without_access = T.let([], T::Array[Integer])
      track_duration("notifications.newsies_purge_subscribers_job.dist.access_checks_time") do
        # NOTE: readable_by? is not part of the IRepository interface — it exists on the concrete
        # Repository class. The downcast is safe because Repositories.domain.by_id always returns
        # a Repository instance at runtime.
        repository = T.unsafe(@repository)
        without_access = User.where(id: user_ids).order(id: :asc)
          .reject { |user| repository.readable_by?(user) }
          .filter_map(&:id)
      end
      without_access
    end

    # Public: Trigger async deletion of subscriptions for users who lost access.
    #
    # user_ids      - Array<Integer> of user IDs to remove.
    # restorable_id - Optional Integer restorable ID for persistence recovery.
    sig { params(user_ids: T::Array[Integer], restorable_id: T.nilable(Integer)).void }
    def async_delete_subscriptions(user_ids, restorable_id: nil)
      Subscriptions.async_delete_list_subscriptions_for_users(
        list: @subject, user_ids: user_ids, restorable_id: restorable_id
      )
    end

    # Public: Count total subscriber user IDs across all subscription types.
    # Returns an upper bound (sum of per-type counts, not deduplicated).
    sig { returns(Integer) }
    def count_all_repository_subscribers
      Subscriptions.count_all_repository_subscribers(@repository_id)
    end

    # Public: Report total job duration metric.
    sig { params(start_time: T.any(Time, ActiveSupport::TimeWithZone)).void }
    def report_total_duration(start_time)
      duration_ms = (Time.now.utc - start_time) * 1_000
      GitHub.dogstats.distribution("notifications.newsies_purge_subscribers_job.dist.duration", duration_ms, tags: @tags)
    end

    private

    sig { params(metric_name: String, block: T.proc.void).void }
    def track_duration(metric_name, &block)
      timer = Timer.start
      block.call
      GitHub.dogstats.distribution(metric_name, timer.elapsed_ms, tags: @tags)
    end
  end
end
