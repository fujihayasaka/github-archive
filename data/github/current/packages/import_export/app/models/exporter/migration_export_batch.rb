# typed: strict
# frozen_string_literal: true

module Exporter
  class MigrationExportBatch < ApplicationRecord::Domain::Migrations
    include Workflow

    EXPORT_BATCH_ENABLED_FF = :import_export_use_batched_export

    # Disable Single Table Inheritance since we use 'type' for batch type enum
    self.inheritance_column = nil

    # Structured error with class name and message
    class CapturedError < T::Struct
      const :error_class, T.class_of(Exception)
      const :error_message, String
      const :customer_message, String, default: ""
    end

    ModelProcessingErrors = T.type_alias { T::Hash[Integer, CapturedError] }

    belongs_to :migration
    belongs_to :migration_file, optional: true

    before_destroy :destroy_migration_file

    after_initialize :set_defaults

    # Override getter to deserialize critical_error from JSON
    sig { returns(T.nilable(CapturedError)) }
    def critical_error
      json_error = read_attribute(:critical_error)
      return nil if json_error.blank?

      error_class_name = json_error["error_class"].to_s
      error_class = begin
        Object.const_get(error_class_name)
      rescue NameError
        StandardError
      end

      CapturedError.new(
        error_class: T.cast(error_class, T.class_of(Exception)),
        error_message: json_error["error_message"].to_s,
        customer_message: json_error["customer_message"].to_s
      )
    end

    # Override setter to serialize critical_error to JSON
    sig { params(error: T.nilable(CapturedError)).void }
    def critical_error=(error)
      if error.nil?
        write_attribute(:critical_error, nil)
      else
        write_attribute(:critical_error, {
          "error_class" => error.error_class.name,
          "error_message" => error.error_message,
          "customer_message" => error.customer_message
        })
      end
    end

    # Override getter to deserialize from JSON
    sig { returns(ModelProcessingErrors) }
    def processing_errors
      json_errors = read_attribute(:processing_errors)
      return {} if json_errors.blank?

      json_errors.transform_keys(&:to_i).transform_values do |error_data|
        error_class_name = error_data["error_class"].to_s
        error_class = begin
          Object.const_get(error_class_name)
        rescue NameError
          StandardError
        end

        CapturedError.new(
          error_class: T.cast(error_class, T.class_of(Exception)),
          error_message: error_data["error_message"].to_s,
          customer_message: error_data["customer_message"].to_s
        )
      end
    end

    # Override setter to serialize to JSON
    sig { params(errors: T.nilable(ModelProcessingErrors)).void }
    def processing_errors=(errors)
      if errors.blank?
        write_attribute(:processing_errors, {})
      else
        write_attribute(:processing_errors, errors.transform_keys(&:to_s).transform_values do |captured_error|
          {
            "error_class" => captured_error.error_class.name,
            "error_message" => captured_error.error_message,
            "customer_message" => captured_error.customer_message
          }
        end)
      end
    end

    enum :type, {
      serialization: 0,
      archiving: 1
    }

    workflow :state do
      state :queued, 0 do
        event :claim, transitions_to: :pending
        event :fail, transitions_to: :failed
      end

      state :pending, 1 do
        event :start, transitions_to: :processing
        event :fail, transitions_to: :failed
        event :abort, transitions_to: :aborted
      end

      state :processing, 2 do
        event :complete, transitions_to: :completed
        event :complete_with_failures, transitions_to: :completed_with_failures
        event :fail, transitions_to: :failed
        event :requeue, transitions_to: :queued
      end

      state :completed, 3

      state :failed, 4 do
        event :requeue, transitions_to: :queued
      end

      state :aborted, 5

      state :completed_with_failures, 6
    end

    validates :migration_id, presence: true
    validates :model_type, presence: true, length: { maximum: 64 }
    validates :success_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :failed_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validate :model_ids_present

    private

    sig { void }
    def model_ids_present
      if model_ids.blank?
        errors.add(:model_ids, "can't be blank")
      end
    end

    sig { void }
    def set_defaults
      # Only set default if not explicitly set
      self.model_ids ||= [] if new_record? || read_attribute(:model_ids).nil?
      self.processing_errors = {} if new_record? || read_attribute(:processing_errors).nil?
    end

    sig { void }
    def destroy_migration_file
      migration_file&.destroy
    end
  end
end
