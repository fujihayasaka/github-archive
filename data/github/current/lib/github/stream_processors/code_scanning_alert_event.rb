# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    # Once Turboscan has completed the ingestion of an Analysis
    # and computed the diff, it signals on the AlertEvent topic
    # all the alert changes.
    class CodeScanningAlertEvent < SingleMessageProcessor
      DEFAULT_GROUP_ID = "code_scanning_alert_event"
      DEFAULT_SUBSCRIBE_TO = /turboscan.v0.AlertEvent\Z/

      # :min_bytes and :max_wait_time define how frequently we fetch a new batch,
      # and :max_bytes_per_partition defines the max size of a batch.
      # :session_timeout defines how long to wait before considering the consumer
      # non-responding.
      #
      # We currently say to fetch at new batch every 0.2 seconds or
      # if there are at least 5KB of data, and not to get more than 100 KB in a
      # batch. We promise to process the 100KB within 60 seconds.
      # Our messages here are pretty small (<1KB) so we claim that we can process
      # >100 messages in ~60 seconds.
      options[:min_bytes] = 5.kilobytes
      options[:max_wait_time] = 0.2.seconds
      options[:max_bytes_per_partition] = 100.kilobytes
      options[:session_timeout] = 60.seconds
      options[:start_from_beginning] = false

      resolve_tenant_context do |message|
        Repositories::Public.get_active_or_deleted!(message.value[:repository_id]).owner&.business
      end

      def setup(group_id: nil, subscribe_to: nil)
        options[:group_id] ||= DEFAULT_GROUP_ID
        options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
        self.metric_prefix = "code_scanning.alert_event"
      end

      # Message will be a AlertEvent.proto
      # see https://github.com/github/hydro-schemas/blob/bd32975dd26848a565ab345a620295ec7218f6ff/proto/hydro/schemas/turboscan/v0/alert_event.proto#L9
      #
      def process_message(message)
        GitHub.logger.error(
          "Unexpected result is nil",
          "code.namespace" => "CodeScanningAlertEvent",
          "code.function" => "process_message",
          "messaging.source.name" => message.topic,
          "messaging.kafka.source.partition" => message.partition,
          "messaging.kafka.message.offset" => message.offset,
        ) if message.value[:result].nil?

        return message.skip("Code Scanning banned") if kill_switch?(message.value[:repository_id])
        event_from_message(message.value)&.deliver_later

      rescue StandardError => e # rubocop:todo Lint/RescueException
        # We want to continue processing messages even if we fail
        # here. Therefore we log the error and continue. A more
        # detailed set of exceptions here might be desirable, and we
        # should refine this once we get a sense of typical ways in
        # which we fail.
        GitHub.logger.error(
          "Failure processing message",
          "code.namespace" => "CodeScanningAlertEvent",
          "code.function" => "process_message",
          :exception => e,
        )
        Failbot.report(e)
      end

      private

      # Return a Hook::Event::CodeScanningAlertEvent from the given AlertEvent message
      def event_from_message(values)
        action =
          case values[:event]
          when :ALERT_CREATED
            :created
          when :ALERT_REOPENED_BY_USER
            :reopened_by_user
          when :ALERT_CLOSED_BY_USER
            :closed_by_user
          when :ALERT_CLOSED_BECAME_FIXED
            :fixed
          when :ALERT_APPEARED_IN_BRANCH
            :appeared_in_branch
          when :ALERT_REAPPEARED
            :reopened
          when :ALERT_DELETED_BY_USER
            # Explicitly ignore deleted events, so that integrators do not start
            # using it until we decide whether we want deletion to occur only
            # at the Analysis level
            nil
          else
            nil
          end
        return nil if action.nil?

        actor_id = values[:actor_id]
        actor_id = nil if actor_id.zero?

        event = Hook::Event::CodeScanningAlertEvent.new(
          action: action,
          repository_id: values[:repository_id],
          alert_number: values[:alert_number],
          commit_oid: values[:commit_oid],
          ref: values[:ref],
          actor_id: actor_id,
          result: values[:result],
        )
        event.attributes[:queued_at] = Time.now.to_f
        event
      end

      def kill_switch?(repository_id)
        return false if GitHub.enterprise?
        # We often get several consecutive messages for the same repo and
        # want to avoid having to access the db every time. So we cache the last
        # repo we've seen.
        unless @cached_repo.present? && @cached_repo.id == repository_id
          @cached_repo = Repository.where(id: repository_id).first
        end
        @cached_repo&.code_scanning_banned?
      end
    end
  end
end
