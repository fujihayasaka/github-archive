# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    class IssueProjectEventsProcessor < BaseProcessor
      PROJECT_ITEM_CREATE_TOPIC = /github\.memex\.v0\.ProjectItemCreate\Z/
      PROJECT_ITEM_UPDATE_TOPIC = /github\.memex\.v0\.ProjectItemUpdate\Z/
      PROJECT_ITEM_DESTROY_TOPIC = /github\.memex\.v0\.ProjectItemDestroy\Z/
      PROJECT_COLUMN_VALUE_CREATE_TOPIC = /github\.memex\.v0\.MemexProjectColumnValueCreate\Z/
      PROJECT_COLUMN_VALUE_UPDATE_TOPIC = /github\.memex\.v0\.MemexProjectColumnValueUpdate\Z/
      PROJECT_COLUMN_VALUE_DESTROY_TOPIC = /github\.memex\.v0\.MemexProjectColumnValueDestroy\Z/

      # MemexProjectItemMove is a combined event representing both a MemexProjectColumnValueUpdate AND ProjectItemUpdate
      PROJECT_ITEM_MOVE_TOPIC = /github\.memex\.v0\.MemexProjectItemMove\Z/

      DEFAULT_GROUP_ID = "github-#{Rails.env}-issue_project_events_processor"
      DEFAULT_SUBSCRIBE_TO = [
        PROJECT_ITEM_CREATE_TOPIC,
        PROJECT_ITEM_UPDATE_TOPIC,
        PROJECT_ITEM_DESTROY_TOPIC,
        PROJECT_COLUMN_VALUE_CREATE_TOPIC,
        PROJECT_COLUMN_VALUE_UPDATE_TOPIC,
        PROJECT_COLUMN_VALUE_DESTROY_TOPIC,
        PROJECT_ITEM_MOVE_TOPIC,
      ]

      options[:session_timeout] = 60.seconds
      options[:socket_timeout] = 65.seconds
      options[:start_from_beginning] = false

      # Public: Configure the Hydro processor
      def setup(**kwargs)
        options[:group_id] ||= DEFAULT_GROUP_ID
        options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
      end

      def process_message(message)
        case message.schema
        when PROJECT_ITEM_CREATE_TOPIC
          handle_project_item_create(message)
        when PROJECT_ITEM_DESTROY_TOPIC
          handle_project_item_destroy(message)
        when PROJECT_ITEM_UPDATE_TOPIC
          handle_project_item_update(message)
        when PROJECT_COLUMN_VALUE_CREATE_TOPIC
          handle_project_column_value_create(message)
        when PROJECT_COLUMN_VALUE_UPDATE_TOPIC
          handle_project_column_value_update(message)
        when PROJECT_COLUMN_VALUE_DESTROY_TOPIC
          handle_project_column_value_destroy(message)
        when PROJECT_ITEM_MOVE_TOPIC
          handle_project_item_move(message)
        else
          # This indicates that the processor is subscribed to a schema that it doesn't know how to handle.
          log_error("Unexpected schema", message)
        end
      end

      def handle_project_item_create(message)
        create_issue_project_event("added_to_project_v2", message)

        trigger_issue_subscription(message)
      end

      def handle_project_item_destroy(message)
        create_issue_project_event("removed_from_project_v2", message)

        trigger_issue_subscription(message)
      end

      def handle_project_item_update(message)
        return unless message.value.dig(:previous_values).match?(/"content_type" ?=> ?\["DraftIssue", "Issue"\]/)
        return unless message.value.dig(:creator, :id)

        create_issue_project_event(
          "added_to_project_v2",
          message,
          message.value.dig(:creator, :id),
          Time.at(message.value.dig(:memex_project_item, :created_at, :seconds))
        )

        create_issue_project_event(
          "converted_from_draft",
          message,
          message.value.dig(:actor, :id),
        )

        trigger_issue_subscription(message)
      end

      def handle_project_column_value_create(message)
        return unless is_status_column(message.value)
        status_values = map_status(message.value.dig(:project_column, :custom_field_values))
        status = status_values[message.value[:value]]

        return unless status

        create_issue_status_changed_event("project_v2_item_status_changed", message, status, "")

        trigger_issue_subscription(message)
      end

      def handle_project_column_value_update(message)
        return unless is_status_column(message)
        status_values = map_status(message.value.dig(:project_column, :custom_field_values))
        status = status_values[message.value[:value]]
        previous_status = status_values[message.value[:previous_value]]

        return unless previous_status && status
        return if previous_status == status

        create_issue_status_changed_event("project_v2_item_status_changed", message, status, previous_status)

        trigger_issue_subscription(message)
      end

      def handle_project_column_value_destroy(message)
        return unless is_status_column(message.value)
        status_values = map_status(message.value.dig(:project_column, :custom_field_values))
        previous_status = status_values[message.value[:value]]

        return unless previous_status

        create_issue_status_changed_event("project_v2_item_status_changed", message, "", previous_status)

        trigger_issue_subscription(message)
      end

      def handle_project_item_move(message)
        message.value.dig(:project_column_value_records).each do |record|
          next unless is_status_column(record)
          status_values = map_status(record.dig(:project_column, :custom_field_values))
          status = status_values[record[:value]]
          previous_status = status_values[record[:previous_value]]

          next unless previous_status || status
          next if previous_status == status

          create_issue_status_changed_event("project_v2_item_status_changed", message, status || "", previous_status || "")

          trigger_issue_subscription(message)
        end
      end

      private

      def log_error(title, message)
        log_hash = {
          "id" => message.id,
          "schema" => message.schema,
          "code.namespace" => "GitHub::StreamProcessors::IssueProjectEventsProcessor",
          "gh.hydro.msg.timestamp" => message.timestamp,
        }

        GitHub.logger.error(title, **log_hash)
        Failbot.report(StandardError.new(title), **log_hash)
      end

      def log_info(title, message)
        log_hash = {
          "id" => message.id,
          "schema" => message.schema,
          "code.namespace" => "GitHub::StreamProcessors::IssueProjectEventsProcessor",
          "gh.hydro.msg.timestamp" => message.timestamp,
        }

        GitHub.logger.info(title, **log_hash)
      end

      def valid_actor?(message)
        message.value.dig(:actor, :id).present? && message.value.dig(:actor, :id) != 0
      end

      def valid_memex_project?(message)
        message.value.dig(:memex_project, :id).present? && message.value.dig(:memex_project, :id) != 0
      end

      def valid_project?(message)
        message.value.dig(:project, :id).present? && message.value.dig(:project, :id) != 0
      end

      def valid_memex_project_item?(message)
        message.value.dig(:memex_project_item, :id).present? && message.value.dig(:memex_project_item, :id) != 0
      end

      def valid_project_item?(message)
        message.value.dig(:project_item, :id).present? && message.value.dig(:project_item, :id) != 0
      end

      def valid_memex_project_item_issue?(message)
        message.value.dig(:memex_project_item, :issue, :id).present? && message.value.dig(:issue, :id) != 0
      end

      def valid_project_item_issue?(message)
        message.value.dig(:project_item, :issue, :id).present? && message.value.dig(:issue, :id) != 0
      end

      def valid_memex_project_item_pull_request?(message)
        message.value.dig(:memex_project_item, :pull_request, :id).present? && message.value.dig(:pull_request, :id) != 0
      end

      def valid_project_item_pull_request?(message)
        message.value.dig(:project_item, :pull_request, :id).present? && message.value.dig(:pull_request, :id) != 0
      end

      def is_status_column(value)
        value.dig(:project_column, :name) == "Status"
      end

      def validate_issue_project_event(message)
        unless valid_actor?(message) &&
            valid_memex_project?(message) &&
            valid_memex_project_item?(message) &&
            (valid_memex_project_item_issue?(message) || valid_memex_project_item_pull_request?(message))
          log_info("Invalid issue project event", message)
          return false
        end

        true
      end

      def validate_issue_status_changed_event(message)
        unless valid_actor?(message) &&
            valid_project?(message) &&
            valid_project_item?(message) &&
            (valid_project_item_issue?(message) || valid_project_item_pull_request?(message))
          log_info("Invalid issue status changed event", message)
          return false
        end

        true
      end

      def get_issue_id(message)
        project_item_hash = message.value.dig(:project_item) || message.value.dig(:memex_project_item)
        # Return the issue id if this event is for an issue
        issue_id = project_item_hash.dig(:issue, :id)
        return issue_id if issue_id.present?

        # Try to get the pull_request_id in case this event is for a pull request
        pull_request_id = project_item_hash.dig(:pull_request, :id)
        return unless pull_request_id.present?
        pull_request = PullRequest.find_by(id: pull_request_id)
        return unless pull_request.present?
        return unless should_create_pull_request_events(pull_request)
        pull_request.issue&.id
      end

      def should_create_pull_request_events(pull_request)
        owner = pull_request&.repository&.owner

        return false unless owner.present?
        owner.feature_enabled?(:create_pull_request_project_events)
      end

      def create_issue_project_event(event_name, message, actor_id = nil, created_at = Time.at(message.timestamp))
        return unless validate_issue_project_event(message)
        issue_id = get_issue_id(message)
        return unless issue_id.present?

        ActiveRecord::Base.connected_to(role: :writing) do
          IssueEvent.create!(
            issue_id:,
            event: event_name,
            actor_id: actor_id || message.value.dig(:actor, :id),
            source_id: message.id,
            project_id: message.value.dig(:memex_project, :id),
            created_at: created_at,
          )
        end
      end

      def create_issue_status_changed_event(event_name, message, status = "", previous_status = "")
        return unless validate_issue_status_changed_event(message)
        issue_id = get_issue_id(message)
        return unless issue_id.present?

        ActiveRecord::Base.connected_to(role: :writing) do
          IssueEvent.create!(
            issue_id:,
            event: event_name,
            actor_id: message.value.dig(:actor, :id),
            source_id: message.id,
            project_id: message.value.dig(:project, :id),
            project_status: status,
            project_previous_status: previous_status,
            created_at: Time.at(message.timestamp),
          )
        end
      end

      # `status_array` looks like ["id:0bbd73e3,name:Draft", "id:37e3ae09,name:Open", "id:3ea64ab0,name:Closed"]
      #  Return value looks like { "0bbd73e3" => "Draft", "37e3ae09" => "Open", "3ea64ab0" => "Closed" }
      def map_status(status_array)
        result = {}
        status_array.map do |status|
          unless status.starts_with?("id:")
            next
          end

          # We expect status to be in the following format: "id:0bbd73e3,name:Draft"
          # and we want to make sure that we always have the `id` and `name` defined.
          # `name_idx` should be greater than or equal to 4 to ensure "id:" is followed by "name:".
          name_idx = status.index("name:")
          if name_idx.nil? || name_idx < 4
            next
          end

          # `id` always starts from the 3rd index and ends just before `name_idx - 1`.
          id = status[3...name_idx - 1]
          # `value` always starts from `name_idx + 5` (which resembles the number of characters in `name:`).
          value = status[name_idx + 5..-1]
          result[id] = value
        end
        result
      end

      def trigger_issue_subscription(message)
        issue_id = message.value.dig(:project_item, :issue, :id_value) || message.value.dig(:memex_project_item, :issue, :id_value)
        return unless issue = Issue.find_by(id: issue_id)
        global_relay_id = issue.global_relay_id

        ::Platform::Schema.subscriptions.trigger(:issue_updated, { id: global_relay_id }, object: { issue_timeline_updated: true, issue_metadata_updated: true })
      end
    end
  end
end
