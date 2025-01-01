# typed: true
# frozen_string_literal: true

module Licensing
  module Vss
    class ParsedSubscriptionEvent
      extend T::Sig

      REQUIRED_FIELDS = %w[
        Identity
        SubscriptionGuid
        AssignmentOperation
      ].freeze
      NEW_ASSIGNMENT_OPERATION = "Assign"
      REMOVE_ASSIGNMENT_OPERATION = "Remove"
      VALID_OPERATIONS = [
        "None",
        NEW_ASSIGNMENT_OPERATION,
        REMOVE_ASSIGNMENT_OPERATION,
        "PendingAcceptance"
      ].freeze

      sig { params(json_string: T.nilable(String)).void }
      def initialize(json_string)
        @json_string = json_string
        parse
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
        operation == REMOVE_ASSIGNMENT_OPERATION
      end

      private

      attr_reader :json_string, :parsed_data

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

      def parse
        @parsed_data = JSON.parse(json_string)
        @valid_json = true
      rescue JSON::ParserError
        @parsed_data = Hash.new
        @valid_json = false
      end
    end
  end
end
