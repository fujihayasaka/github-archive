# rubocop:todo GitHub/EnforcePackageAppStructure
# rubocop:todo GitHub/UseActorFeatureEnabled
# typed: true
# frozen_string_literal: true

class HydroNotifydDeliverWebJob < HydroMessageJob

  include GitHub::Tracing
  trace_method :deliver

  DATABASE_UNAVAILABLE_EXCEPTIONS = [
    Freno::Throttler::Error,
    *Resiliency::Response::UnavailableExceptions
  ]

  BATCH_LIMIT = 10
  PARTICIPANT_REASONS = %w(author comment assign state_change mention team_mention manual)
  SUBSCRIBED_REASONS = %w(list_subscription thread_type_subscription subscribed)

  queue_as :hydro_notifyd_deliver_web_v1

  retry_on_dirty_exit
  retry_on *DATABASE_UNAVAILABLE_EXCEPTIONS, delay: :polynomially_longer, max_retries: 20

  class ReasonsConverter

    # The reason precedence is defined by the order in which appear in the array.
    # Reasons that imply some expectations from the user should have higher precedence,
    # followed by the rest of participating reasons, and finally subscribed.
    # Reasons not appearing here will have the least precedence by default.
    DEFAULT_REASON_ORDER = %w(mention team_mention assign review_requested comment manual author state_change subscribed)

    REASON_ORDER_BY_SUBJECT_TYPE = {
      # When the subject type is Issue, we give higher precendece to assign reason.
      # This way when a new issue is assigned to a recipient that is also mentioned,
      # the reason will end up being assign, no matter the order of notification deliveries.
      # See https://github.com/github/notifyd/issues/2783#issuecomment-1525819915 for full details.
      "Issue" => %w(assign mention team_mention review_requested comment manual author state_change subscribed)
    }

    REASONS_MAPPING = {
      approval_requested: "approval_requested",
      assign: "assign",
      author: "author",
      ci_activity: "ci_activity",
      comment: "comment",
      list_subscription: "subscribed",
      manual: "manual",
      mention: "mention",
      state_change: "state_change",
      subscribed: "subscribed",
      team_mention: "team_mention",
      thread_type_subscription: "subscribed",
      member_feature_requested: "member_feature_requested"
    }

    # convert turns notifyd reasons into newsies reasons
    sig { params(reasons: T::Array[String]).returns(T::Array[String]) }
    def self.convert(reasons)
      reasons.map { |reason| REASONS_MAPPING[reason.to_sym] }.compact
    end

    sig { params(subject_type: String, reasons: T::Array[String]).returns(T::Array[String]) }
    def self.sort(subject_type, reasons)
      order = REASON_ORDER_BY_SUBJECT_TYPE[subject_type] || DEFAULT_REASON_ORDER
      reasons.sort_by { |reason| order.index(reason) || order.count }
    end
  end

  # Potentially delivers a Web Notification for a multiple recipients.
  #
  # This is the last step of the new web notifications delivery pipeline.
  # In this pipeline, a notification event generated in dotcom is processed by notifyd,
  # which generates web notification events for explicit recipients and subscribers.
  #
  # Currently, notifyd doesn't have the web delivery settings, and thus it generates
  # a web notification event for every potential web delivery notification.
  #
  # It's the responsibility of this job to check these web delivery settings
  # and decide whether to deliver or drop the web notification.
  def perform
    subject_type = message[:subject_type]
    subject_id = message[:subject_id]

    object = hydrate_subject(subject_type, subject_id)
    if object.nil?
      GitHub.dogstats.increment("notifyd.deliver_web.deliver.skipped", tags: ["reason:no_object"])
      return
    end

    list = object.notifications_list
    if list.nil?
      GitHub.dogstats.increment("notifyd.deliver_web.deliver.skipped", tags: ["reason:no_list"])
      return
    end

    thread = object.notifications_thread # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    if thread.nil?
      GitHub.dogstats.increment("notifyd.deliver_web.deliver.skipped", tags: ["reason:no_thread"])
      return
    end

    delivery = ActiveRecord::Base.connected_to(role: :writing) do
      GitHub.tracer.in_span("build_newsies_delivery", kind: :internal) do
        comment = object.is_a?(PullRequest) ? object.issue : object
        GitHub.dogstats.distribution_time("notifyd.deliver_web.build", tags: ["subject:#{subject_type}"]) do
          summary = NotificationSummary.fetch_and_update!(list, thread, comment)
          Newsies::Delivery.new(summary, comment)
        end
      end
    end

    if delivery.nil?
      GitHub.dogstats.increment("notifyd.deliver_web.deliver.skipped", tags: ["reason:no_delivery"])
      return
    end

    triggered_at = message.dig(:tracking, :triggered_at)
    triggered_at = Google::Protobuf::Timestamp.new(triggered_at).to_time unless triggered_at.nil?

    throttle(recipients: message[:recipients]) do |recipient|
      begin
        start = GitHub::Dogstats.monotonic_time
        status = :unknown
        status = deliver(subject_type: subject_type, delivery: delivery, user_id: recipient[:user_id], reasons: recipient[:reasons], triggered_at: triggered_at)
      ensure
        GitHub.logger.info("Delivering web notification for single recipient", {
          "code.namespace" => "HydroNotifydDeliverWebJob",
          "code.function" => "perform",
          "gh.notifyd.subject.type" => subject_type,
          "gh.notifyd.subject.id" => subject_id,
          "gh.notifyd.list_id" => delivery.list_id.to_s,
          "gh.notifyd.list_type" => delivery.list_type,
          "gh.notifyd.thread_id" => delivery.thread_id.to_s,
          "gh.notifyd.thread_type" => delivery.thread_type,
          "gh.notifyd.comment_id" => delivery.comment_id.to_s,
          "gh.notifyd.comment_type" => delivery.comment_type,
          "gh.notifyd.notification_id" => delivery.notification_id,
          "gh.user.id" => recipient[:user_id],
          "gh.notifyd.reasons" => recipient[:reasons],
          "gh.notifyd.status" => status.to_s
        })
        GitHub.dogstats.timing_since("notifyd.deliver_web.perform.time", start, tags: ["subject:#{subject_type}", "status:#{status}"])
      end
    end
  end

  def hydrate_subject(subject_type, subject_id)
    object = subject_type.constantize.find_by_id(subject_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    case object
    when CheckSuite
      CheckSuiteEventNotification.new(object)
    when IssueEvent
      object.issue_event_notification
    else
      object
    end
  end

  def throttle(recipients:)
    message[:recipients].each_slice(BATCH_LIMIT) do |batch|
      Newsies::NotificationEntry.throttle do
        batch.each do |recipient|
          yield(recipient)
        end
      end
    end
  end

  def deliver(subject_type:, delivery:, user_id:, reasons:, triggered_at:)
    return :no_user unless user = User.find_by(id: user_id)

    settings = GitHub.newsies.settings(user)&.value
    reason = delivery_reason(settings, reasons, subject_type)
    return :no_reason if reason.nil?

    ActiveRecord::Base.connected_to(role: :writing) do
      GitHub.dogstats.distribution_time("notifyd.deliver_web.deliver", tags: ["subject:#{subject_type}"]) do
        Newsies::WebHandler.new.force_deliver(
          delivery,
          user,
          event_time: triggered_at,
          reason: reason,
          root_job_enqueued_at: triggered_at&.utc.to_f,
          extra_tags: ["reason:#{reason}", "source:notifyd"]
        )
      end
      :success
    end
  end

  # Determine which reason to use to deliver the web notification, if any.
  #
  # Notifyd has already determined the recipients and reasons, but is currently knows nothing about web delivery settings.
  # This extra filtering needs to be done here, but only for reasons that are part of the PARTICIPANT or SUBSCRIBED sets.
  # Other reasons are not filtered because they are not related to web delivery settings.
  #
  # Contrary to how Newsies work, in notifyd we may have multiple reasons to notify a single recipient.
  # We need to determine if any of the reasons is related to an enabled setting.
  # It may happen that more than one reason satisfies the constraint, in this case we just return one.
  #
  # Which reason relates to with setting should be handled by the integrator, not us.
  # This means that ideally we would have the reason groups in this event.
  # This is not necessary in the long term as once notifyd has the web delivery settings,
  # it will be able to do this filtering by itself, and the resulting list of reason would be the final one.
  # In order to avoid this additional temoprary complexity that would result in the need to deprecate the event field,
  # this matching is hardcoded here for now.
  def delivery_reason(settings, raw_reasons, subject_type)
    filterable_reasons, reasons = raw_reasons.partition { |reason| PARTICIPANT_REASONS.include?(reason) || SUBSCRIBED_REASONS.include?(reason) }
    filterable_reasons = filterable_reasons.select do |reason|
      settings.participating_web? && PARTICIPANT_REASONS.include?(reason) ||
      settings.subscribed_web? && SUBSCRIBED_REASONS.include?(reason)
    end
    converted_reasons = ReasonsConverter.convert(reasons + filterable_reasons)
    sorted_reasons = ReasonsConverter.sort(subject_type, converted_reasons)
    sorted_reasons.first
  end
end
