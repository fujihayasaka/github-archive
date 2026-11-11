# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    class CodeScanningAlertAssignmentEventProcessor < SingleMessageProcessor
      DEFAULT_GROUP_ID = "github-#{Rails.env}-code_scanning_alert_assignment_event_processor"
      DEFAULT_SUBSCRIBE_TO = /code_scanning\.v0\.AlertUpdateAssignees\Z/


      options[:session_timeout] = 60.seconds
      options[:socket_timeout] = 65.seconds

      # When the processor starts consuming from a partition for the first time and has no committed offsets,
      # `start_from_beginning` determines if should start from the beginning of the log (i.e. the oldest available messages)
      # or the end of the log (i.e. the newest available messages).
      #
      # This is the equivalent of the java client `auto.offset.reset` consumer config.
      # See: https://kafka.apache.org/documentation/#consumerconfigs_auto.offset.reset
      options[:start_from_beginning] = false
      options[:max_bytes_per_partition] = 100.kilobytes

      resolve_tenant_context do |message|
        Repositories::Public.get_active_or_deleted!(message.value[:repository_id]).owner&.business
      end

      # Public: Configure the Hydro processor
      def setup(**kwargs)
        options[:group_id] ||= DEFAULT_GROUP_ID
        options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
      end

      # Message will be a AlertUpdateAssignees.proto
      # see https://github.com/github/hydro-schemas/blob/b9a5476cfb9ed4b34a0a82d7492dcfece5fdd0b3/proto/hydro/schemas/code_scanning/v0/alert_update_assignees.proto#L9
      sig { override.params(message: GitHub::StreamProcessors::Message).returns(T.anything) }
      def process_message(message)
        repo = Repository.find_by(id: message.value[:repository_id])
        return message.skip("Code Scanning banned") if kill_switch?(repo)

        event_from_message(message.value)&.deliver_later
      rescue StandardError => e # rubocop:todo Lint/RescueException
        # We want to continue processing messages even if we fail
        # here. Therefore we log the error and continue. A more
        # detailed set of exceptions here might be desirable, and we
        # should refine this once we get a sense of typical ways in
        # which we fail.
        GitHub.logger.error(
          "Failure processing message",
          "code.namespace" => "CodeScanningAlertAssignmentEventProcessor",
          "code.function" => "process_message",
          :exception => e,
        )
        Failbot.report(e)
      end

      private

      # Return a Hook::Event::CodeScanningAlertEvent from the given AlertUpdateAssignees message
      def event_from_message(values)
        action = :updated_assignment

        actor_id = values[:actor_id]
        actor_id = nil if actor_id.zero?

        response = GitHub::Turboscan.alert(
          repository_id: values[:repository_id],
          number: values[:alert_number],
        )

        # Return early if Turboscan is unavailable or the alert is not found
        if response.blank? || response.error.present?
          GitHub.logger.error(
            "Code scanning unavailable",
            "code.namespace" => "CodeScanningAlertAssignmentEventProcessor",
            "code.function" => "event_from_message",
          )
          return
        end

        alert = response.data.result.to_h

        event = Hook::Event::CodeScanningAlertEvent.new(
          action: action,
          repository_id: values[:repository_id],
          alert_number: values[:alert_number],
          actor_id: actor_id,
          result: alert,
        )
        event.attributes[:queued_at] = Time.now.to_f
        event
      end

      sig { params(repo: T.nilable(Repository)).returns(T::Boolean) }
      def kill_switch?(repo)
        return false if GitHub.enterprise?
        repo&.code_scanning_banned?
      end
    end
  end
end
