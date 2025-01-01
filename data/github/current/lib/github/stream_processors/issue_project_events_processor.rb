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

      DEFAULT_GROUP_ID = "github-#{Rails.env}-issue_project_events_processor"
      DEFAULT_SUBSCRIBE_TO = [
        PROJECT_ITEM_CREATE_TOPIC,
        PROJECT_ITEM_UPDATE_TOPIC,
        PROJECT_ITEM_DESTROY_TOPIC,
        PROJECT_COLUMN_VALUE_CREATE_TOPIC,
        PROJECT_COLUMN_VALUE_UPDATE_TOPIC,
        PROJECT_COLUMN_VALUE_DESTROY_TOPIC,
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
        return unless User.find_by(id: message.value.dig(:actor, :id))&.feature_enabled?(:write_issue_project_events_mysql)

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
        else
          # This indicates that the processor is subscribed to a schema that it doesn't know how to handle.
          log_error("Unexpected schema", message)
        end
      end

      def handle_project_item_create(message)
        create_issue_project_event("added_to_project_v2", message)
      end

      def handle_project_item_destroy(message)
        create_issue_project_event("removed_from_project_v2", message)
      end

      def handle_project_item_update(message)
        return unless message.value.dig(:previous_values).include?('"content_type"=>["DraftIssue", "Issue"]')

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
      end

      def handle_project_column_value_create(message)
        return unless is_status_column(message)
        status_values = map_status(message.value.dig(:project_column, :custom_field_values))
        status = status_values[message.value[:value]]

        create_issue_status_changed_event("project_v2_item_status_changed", message, status, "")
      end

      def handle_project_column_value_update(message)
        return unless is_status_column(message)
        status_values = map_status(message.value.dig(:project_column, :custom_field_values))
        status = status_values[message.value[:value]]
        previous_status = status_values[message.value[:previous_value]]

        create_issue_status_changed_event("project_v2_item_status_changed", message, status, previous_status)
      end

      def handle_project_column_value_destroy(message)
        return unless is_status_column(message)
        status_values = map_status(message.value.dig(:project_column, :custom_field_values))
        previous_status = status_values[message.value[:value]]

        create_issue_status_changed_event("project_v2_item_status_changed", message, "", previous_status)
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

      def is_status_column(message)
        message.value.dig(:project_column, :name) == "Status"
      end

      def validate_issue_project_event(message)
        unless valid_actor?(message) &&
            valid_memex_project?(message) &&
            valid_memex_project_item?(message) &&
            valid_memex_project_item_issue?(message)
          log_error("Invalid issue project event", message)
          return false
        end

        true
      end

      def validate_issue_status_changed_event(message)
        unless valid_actor?(message) &&
            valid_project?(message) &&
            valid_project_item?(message) &&
            valid_project_item_issue?(message)
          log_error("Invalid issue status changed event", message)
          return false
        end

        true
      end

      def create_issue_project_event(event_name, message, actor_id = nil, created_at = Time.at(message.timestamp))
        return unless validate_issue_project_event(message)

        ActiveRecord::Base.connected_to(role: :writing) do
          IssueEvent.create!(
            issue_id: message.value.dig(:memex_project_item, :issue, :id),
            event: event_name,
            actor_id: actor_id || message.value.dig(:actor, :id),
            source_id: message.id,
            project_id: message.value.dig(:memex_project, :id),
            created_at: created_at,
          )
        end
      end

      def create_issue_status_changed_event(event_name, message, status, previous_status)
        return unless validate_issue_status_changed_event(message)

        ActiveRecord::Base.connected_to(role: :writing) do
          IssueEvent.create!(
            issue_id: message.value.dig(:project_item, :issue, :id),
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
        status_array.map do |status|
          status.split(",").map { |pair| pair.split(":").last }
        end.to_h
      end
    end
  end
end
