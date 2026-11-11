# typed: true
# frozen_string_literal: true

module Licensing
  module Vss
    class ParsedSubscriptionEvent

      REQUIRED_FIELDS = %w[
        Identity
        SubscriptionGuid
        AssignmentOperation
      ].freeze
      NEW_ASSIGNMENT_OPERATION = "Assign"
      REMOVE_ASSIGNMENT_OPERATION = "Remove"
      UNASSIGN_ASSIGNMENT_OPERATION = "Unassign"
      VALID_OPERATIONS = [
        "None",
        NEW_ASSIGNMENT_OPERATION,
        REMOVE_ASSIGNMENT_OPERATION,
        UNASSIGN_ASSIGNMENT_OPERATION,
        "PendingAcceptance"
      ].freeze

      sig { params(data: T.any(String, Hash, NilClass)).void }
      def initialize(data)
        @source = data
        hydrate
      end

      sig { params(event: Licensing::Vss::VssSubscriptionEvent).returns(Licensing::Vss::ParsedSubscriptionEvent) }
      def self.from_event(event)
        parsed_event = new(event.parsed_payload)

        parsed_event.valid? ? parsed_event : new(event.payload)
      end

      def valid?
        valid_json? &&
          valid_json_object? &&
          all_required_fields_present? &&
          valid_operation?
      end

      def enterprise_agreement_number
        parsed_data["AgreementNumber"]
      end

      sig { returns(String) }
      def email
        parsed_data["Identity"]
      end

      def subscription_id
        parsed_data["SubscriptionGuid"]
      end

      def operation
        parsed_data["AssignmentOperation"]
      end

      def new_assignment?
        operation == NEW_ASSIGNMENT_OPERATION
      end

      def remove_assignment?
        operation == REMOVE_ASSIGNMENT_OPERATION || operation == UNASSIGN_ASSIGNMENT_OPERATION
      end

      private

      attr_reader :source, :parsed_data

      def hydrate
        case source
        when String
          # legacy: parse JSON string once
          @parsed_data = JSON.parse(source)
          @valid_json = true
        when Hash
          # already parsed JSON object
          @parsed_data = source
          @valid_json = true
        else
          # nil or invalid JSON
          @parsed_data = {}
          @valid_json = false
        end
      rescue JSON::ParserError
        # if we get a JSON parse error, we set the parsed_data to an empty hash
        # and valid_json to false
        @parsed_data = {}
        @valid_json = false
      end

      def valid_json?
        !!@valid_json
      end

      def valid_json_object?
        @parsed_data.is_a?(Hash)
      end

      def all_required_fields_present?
        REQUIRED_FIELDS.all? do |field|
          parsed_data[field].present?
        end
      end

      def valid_operation?
        VALID_OPERATIONS.include?(operation)
      end
    end
  end
end
