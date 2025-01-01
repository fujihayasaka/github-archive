# typed: false
# frozen_string_literal: true

class NewsiesAutoSubscribeJob < ApplicationJob
  include GitHub::Tracing
  trace_method(
    :mark_repositories_as_notified,
    span_attribute_extractor: ->(_instance, *args, **_kwargs) do
      user, repositories = args[0..1]
      {
        "gh.user.id" => user.id,
        "gh.notifications.mark_repositories_as_notified.repo.count" => repositories.nil? ? 0 : repositories.count,
      }
    end
  )
  trace_method(
    :notify_user_of_repositories,
    span_attribute_extractor: ->(_instance, *args, **_kwargs) do
      user, _email_address, repositories = args[0..1]
      {
        "gh.user.id" => user.id,
        "gh.notifications.notify_user_of_repositories.repo.count" => repositories.nil? ? 0 : repositories.count,
      }
    end
  )

  # Default set of primaries for write operations
  use_primaries ApplicationRecord::Mysql2

  retry_on_dirty_exit

  queue_as :newsies_auto_subscribe

  schedule interval: 5.minutes, condition: -> { !GitHub.enterprise? }

  locked_by timeout: 1.hour, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  # This job iterates over all pending users and repositories without using a single tenant in particular
  exempt_from_tenant_context_requirement

  BATCH_SIZE = 100

  def perform
    users = 0
    mailing = 0
    time = Time.now

    GitHub.newsies.notify_auto_subscribed do |settings, repositories|
      unless settings.auto_subscribe?
        mark_repositories_as_notified(settings.user, repositories)
        next
      end

      users += 1
      mailing_start = Time.now

      repositories
        .includes(:owner)
        .group_by { |repo| settings.email(repo.organization || :global).address }
        .each do |email_address, repos|
          notify_user_of_repositories(settings.user, email_address, repos)
        end

      mailing += Time.now - mailing_start
    end
  rescue Freno::Throttler::Error
    GitHub.dogstats.increment("newsies.auto_subscribe_job.throttled")
  ensure
    total = Time.now - time
    ms = ((total - mailing) * 1000).round
    mailing_ms = (mailing * 1000).round
    GitHub.dogstats.timing("newsies.auto_subscribe_job.query", ms)
    GitHub.dogstats.timing("newsies.auto_subscribe_job.deliver", mailing_ms)
    GitHub.dogstats.count("newsies.auto_subscribe_job.users", users)
  end

  private

  # Private: mark repositories as notified and send the email
  def notify_user_of_repositories(user, email_address, repositories)
    # Work in batches to ensure we don't have large amounts of unthrottled writes
    # This also limits how many repositories are listed per-email
    repositories.each_slice(BATCH_SIZE) do |repos_slice|
      repos_slice = repos_slice.reject { |repo| repo.owner&.organization? && !repo.owner&.user_can_receive_email_notifications?(user) }

      # we try to mark lists as notified before sending email, so that if the
      # throttle fails the database will not be incorrect
      Newsies::ListSubscription.throttle do
        response = GitHub.newsies.mark_lists_as_notified(user, repos_slice)

        # fail here if newsies is unavailable to prevent further delivery
        raise response.error if response.failed?
      end

      GitHub.tracer.in_span("auto_subscribe_and_deliver_now", kind: :internal) do
        NewsiesMailer.auto_subscribe(user, email_address, repos_slice).deliver_now
      end
    end
  end

  # Private: just mark the repositories as notified without delivering the email
  def mark_repositories_as_notified(user, repositories)
    repositories.each_slice(BATCH_SIZE) do |repos_slice|
      Newsies::ListSubscription.throttle do
        response = GitHub.newsies.mark_lists_as_notified(user, repos_slice)

        # fail here if newsies is unavailable to prevent further delivery
        raise response.error if response.failed?
      end
    end
  end
end
