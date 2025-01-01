# typed: strict
# frozen_string_literal: true

# Originally owned & implemented by the Billing team. ApplicationRecord Domain must remain as
# `Billing` due to DB naming conventions. Similarly with the class name, keep the `Vss` prefix even within
# the Licensing::Vss module is required for DB naming conventions.
module Licensing
  module Vss
    class VssSubscriptionEvent < ApplicationRecord::Domain::Billing
      enum :status, {
        unprocessed: "unprocessed",
        processed: "processed",
        failed: "failed",
        under_investigation: "under_investigation"
      }

      validates :investigation_notes, length: { maximum: 255 }

      after_create_commit :instrument_create

      scope :unsuccessful, -> { where(status: [:failed, :under_investigation]).order(id: :desc) }

      REQUIRED_FIELDS = %w[
        Identity
        SubscriptionGuid
        AssignmentOperation
      ].freeze
      NEW_ASSIGNMENT_OPERATION = "Assign"
      REMOVE_ASSIGNMENT_OPERATION = "Remove"
      UNASSIGN_ASSIGNMENT_OPERATION = "Unassign"
      VALID_OPERATIONS = T.let([
        "None",
        NEW_ASSIGNMENT_OPERATION,
        REMOVE_ASSIGNMENT_OPERATION,
        UNASSIGN_ASSIGNMENT_OPERATION,
        "PendingAcceptance"
      ].freeze, T::Array[String])

      sig { returns(T.nilable(String)) }
      def enterprise_agreement_number
        parsed_payload["AgreementNumber"]
      end

      sig { returns(T.nilable(String)) }
      def email
        parsed_payload["Identity"]
      end

      sig { returns(String) }
      def identity
        parsed_payload.dig("PropertyBag", "email") ||
          parsed_payload["Email"] || # original path of the email field before it was moved into `PropertyBag`
          ""
      end

      sig { returns(T.nilable(String)) }
      def operation
        parsed_payload["AssignmentOperation"]
      end

      sig { returns(T::Boolean) }
      def new_assignment?
        operation == NEW_ASSIGNMENT_OPERATION
      end

      sig { returns(T::Boolean) }
      def remove_assignment?
        operation == REMOVE_ASSIGNMENT_OPERATION || operation == UNASSIGN_ASSIGNMENT_OPERATION
      end

      sig { returns(T::Boolean) }
      def valid_payload?
        valid_json? &&
          valid_json_object? &&
          all_required_fields_present? &&
          valid_operation?
      end

      sig { returns(T::Boolean) }
      def anonymized?
        (email.present? && email !~ URI::MailTo::EMAIL_REGEXP) ||
          parsed_payload.dig("PropertyBag", "subscribername") == "AnonymizeSubscriberName" ||
          parsed_payload.dig("PropertyBag", "notes") == "AnonymizeNotes"
      end

      private

      sig { void }
      def instrument_create
        GlobalInstrumenter.instrument "visual_studio_subscription_event.create", options: {
          payload: self.payload,
          status: self.status,
          investigation_notes: self.investigation_notes,
        }
      end

      sig { returns(T::Boolean) }
      def valid_json?
        !!parsed_payload
      end

      sig { returns(T::Boolean) }
      def valid_json_object?
        parsed_payload.is_a?(Hash)
      end

      sig { returns(T::Boolean) }
      def all_required_fields_present?
        REQUIRED_FIELDS.all? do |field|
          parsed_payload[field].present?
        end
      end

      sig { returns(T::Boolean) }
      def valid_operation?
        VALID_OPERATIONS.include?(operation)
      end
    end
  end
end
