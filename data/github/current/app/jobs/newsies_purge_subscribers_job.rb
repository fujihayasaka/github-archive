# typed: true
# frozen_string_literal: true

class NewsiesPurgeSubscribersJob < ApplicationJob
  include ActiveJob::InitiallyEnqueuedAt
  include Repositories::Domain::Provider

  class ResponseFailed < StandardError; end


  BATCH_SIZE = 1000

  queue_as :notifications

  retry_on ResponseFailed
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(repository_id, user_offset_id = 0, start_time = initially_enqueued_at)
    return unless repository = repositories_domain.by_id(repository_id, allow_deleted: true)

    batch = T.let([], T::Array[T.untyped])
    response = Newsies::Response.new do
      list = Newsies::List.new("Repository", repository_id)
      batch = batched_user_ids(list, user_offset_id)
      user_ids = user_ids_without_access(repository, batch)
      if user_ids.size > 0
        subject = Notifications::Subject.new(type: "Repository", id: repository_id)
        Notifications::Subscriptions.async_delete_list_subscriptions_for_users(list: subject, user_ids: user_ids)
      end
    end

    if response.failed?
      raise ResponseFailed
    end

    if batch.size < BATCH_SIZE
      report_total_duration(start_time)
    else
      NewsiesPurgeSubscribersJob.perform_later(repository_id, batch.last)
    end
  end

  private

  def user_ids_without_access(repository, user_ids)
    without_access = T.let([], T::Array[T.nilable(Integer)])
    track_duration("notifications.newsies_purge_subscribers_job.dist.access_checks_time") do
      without_access = User.where(id: user_ids).reject { |user| repository.readable_by?(user) }.map(&:id)
    end
    without_access
  end

  def batched_user_ids(list, offset_id)
    user_ids = []
    track_duration("notifications.newsies_purge_subscribers_job.dist.gather_user_ids_time") do
      user_ids.concat(Newsies::ListSubscription.for_list(list).distinct.pluck(:user_id))
      user_ids.concat(Newsies::ThreadTypeSubscription.for_list(list).distinct.pluck(:user_id))
      user_ids.concat(Newsies::ThreadSubscription.for_list(list).distinct.pluck(:user_id))
    end

    user_ids
      .uniq
      .sort
      .select { |id| id > offset_id }
      .slice(0, BATCH_SIZE)
  end

  def report_total_duration(start_time)
    duration_ms = T.cast((Time.now.utc - start_time), Float) * 1_000
    GitHub.dogstats.distribution("notifications.newsies_purge_subscribers_job.dist.duration", duration_ms)
  end

  def track_duration(metric_name, &block)
    timer = Timer.start
    block.call
    GitHub.dogstats.distribution(metric_name, timer.elapsed_ms)
  end
end
