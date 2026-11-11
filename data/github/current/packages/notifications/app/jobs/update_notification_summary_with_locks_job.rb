# typed: true
# frozen_string_literal: true

# Updates the NotificationSummary for a given summarizable object (issue, PR, etc.) with
# distributed locking (Redis-based job deduplication with 2-minute TTL). The lock key is
# based on the subject class and ID to prevent concurrent summary updates for the same object.
# Calls summarizable.update_notification_summary_now within a write context.
#
# Enqueued by: Notifications::Summarizable concern
# (packages/notifications/app/models/notifications/summarizable.rb) on issue/PR state
# changes that affect the notification summary.
class UpdateNotificationSummaryWithLocksJob < ApplicationJob
  include GitHub::Tracing
  include GitHub::VexiActor
  trace_method :build_summarizable

  # https://app.datadoghq.com/s/59fe6c40c/4rw-ncm-yaz
  use_replicas ApplicationRecord::ActionsEnvironments,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks

  queue_as :update_summaries

  RETRYABLE_ERRORS = [
    GitHub::Restraint::UnableToLock,
    Redis::CommandError,
    Redis::ConnectionError,
    Redis::CannotConnectError,
    Redis::TimeoutError,
  ].freeze

  class UpdateNotificationSummaryError < StandardError; end

  retry_on_dirty_exit
  retry_on UpdateNotificationSummaryError, wait: :polynomially_longer, attempts: 5
  retry_on *RETRYABLE_ERRORS, wait: :polynomially_longer, attempts: 5

  resolve_tenant_context do |klass, id|
    subject = klass.constantize.find_by(id: id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    Notifications::TenantContext.resolve_tenant(subject&.notifications_list)
  rescue NameError
    nil
  end

  # 2 minutes is picked as atribtrary timeout, feel free to update it if needed
  LOCK_TTL = 2.minutes

  locked_by timeout: LOCK_TTL, key: ->(job) {
    "newsies-update-notifications-summary-enqueue-#{job.summarizable_class}-#{job.summarizable_id}"
  }

  def perform(summarizable_class, summarizable_id, enqueue = false, retryable = false, options = {})
    begin
      status = :error
      status = update(summarizable_class, summarizable_id, options)
    ensure
      GitHub.logger.info(
        "code.namespace" => self.class.name,
        "code.function" => "perform",
        "gh.notifyd.subject.type" => summarizable_class,
        "gh.notifyd.subject.id" => summarizable_id,
        "gh.notifyd.status" => status.to_s
      )
      GitHub.dogstats.increment("update_notification_summary.perform.count", tags: ["subject:#{summarizable_class}", "status:#{status}"])
    end
  end

  def update(summarizable_class, summarizable_id, options)
    options = options.with_indifferent_access

    summarizable = build_summarizable(summarizable_class, summarizable_id)
    return :no_subject unless summarizable

    succeeded = GitHub.tracer.in_span("update_notification_summary_now", kind: :internal, attributes: { "code.namespace" => summarizable_class }) do
      with_write do
        NotificationSummary.throttle do
          summarizable.update_notification_summary_now
        end
      end
    end

    raise UpdateNotificationSummaryError unless succeeded
    :success
  end

  def build_summarizable(summarizable_class, summarizable_id)
    summarizable_class = begin
      summarizable_class.constantize
    rescue NameError
      return
    end
    summarizable_class.find_by_id(summarizable_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  def summarizable_class
    if arguments[0].is_a?(Hash)
      arguments[0][:summarizable_class]
    else
      arguments[0]
    end
  end

  def summarizable_id
    if arguments[0].is_a?(Hash)
      arguments[0][:summarizable_id]
    else
      arguments[1]
    end
  end

  # Options is 5th argument if it's a hash, otherwise return an empty hash
  def options
    if arguments.size > 4 && arguments[4].is_a?(Hash)
      arguments[4]
    else
      {}
    end
  end

  def vexi_id
    GitHub::VexiActor.to_feature_flag_id(summarizable_class, summarizable_id)
  end
end
