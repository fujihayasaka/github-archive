# typed: true
# frozen_string_literal: true

class UpdateNotificationSummaryJob < ApplicationJob
  include GitHub::Tracing
  trace_method :build_summarizable

  queue_as :kubernetes_notifications

  class UpdateNotificationSummaryError < StandardError; end
  retry_on UpdateNotificationSummaryError, wait: :polynomially_longer, attempts: 20
  retry_on_dirty_exit

  resolve_tenant_context do |klass, id|
    subject = klass.constantize.find_by(id: id)
    Notifications::TenantContext.resolve_tenant(subject&.notifications_list)
  rescue NameError
    nil
  end

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
    summarizable_class.find_by_id(summarizable_id)
  end
end
