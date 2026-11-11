# typed: true
# frozen_string_literal: true

# Configuration for Dependabot runner labels and group at org/repo level.
module Configurable
  module DependabotRunnerSettings
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { Instrumentation::Model }

    DEPENDABOT_RUNNER_LABELS_KEY = "dependabot.runner_labels".freeze
    DEPENDABOT_RUNNER_GROUP_KEY = "dependabot.runner_group".freeze

    # Runner type constants for UI components
    RUNNER_TYPE_STANDARD = "standard".freeze
    RUNNER_TYPE_LABELED = "labeled".freeze

    # Field name constants for error messages
    RUNNER_GROUP_NAME = "Runner group name"
    RUNNER_LABEL_NAME = "Runner label"

    # Default values
    DEFAULT_RUNNER_LABELS = ["dependabot"].freeze

    # Validation constants
    MAX_LENGTH = 45
    MAX_LABELS_COUNT = 2
    VALID_FORMAT = /\A[a-zA-Z0-9._-]+\z/

    # Class method for validating runner setting values
    # @param value [String] The value to validate
    # @param field_name [String] Name of the field for error messages
    # @return [String, nil] Error message if invalid, nil if valid
    sig { params(value: String, field_name: String).returns(T.nilable(String)) }
    def self.validate_value_error(value, field_name)
      return "#{field_name} must be 45 characters or less." if value.length > MAX_LENGTH
      return "#{field_name} can only contain letters, numbers, hyphens, underscores, and dots." unless value.match?(VALID_FORMAT)
      nil
    end

    # Class method for validating runner setting values (raises on error)
    # @param value [String] The value to validate
    # @param field_name [String] Name of the field for error messages
    sig { params(value: String, field_name: String).void }
    def self.validate_value(value, field_name)
      error = validate_value_error(value, field_name)
      raise ArgumentError, error if error
    end

    # Set both runner labels and group atomically to prevent inheritance issues.
    # Labels should be comma-separated string, e.g. "label1,label2"
    #
    # @param labels [String, nil] Comma-separated runner labels
    # @param group [String, nil] Runner group name
    # @param actor [T.untyped] User making the change (must have admin permissions on the target)
    # @param force [Boolean] Whether to force the change even if values are the same
    # @return [Boolean] Whether any configuration was changed
    sig { params(labels: T.nilable(String), group: T.nilable(String), actor: T.untyped, force: T::Boolean).returns(T::Boolean) }
    def set_dependabot_runner_settings(labels:, group:, actor:, force: false)
      # Process labels - split by comma and validate
      label_array = if labels.present?
        labels.split(",").map(&:strip).reject(&:blank?)
      else
        []
      end

      # Validate each label
      label_array.each { |label| Configurable::DependabotRunnerSettings.validate_value(label, "Label") }

      # Validate labels count
      raise ArgumentError, "Too many labels (maximum #{MAX_LABELS_COUNT} allowed)" if label_array.size > MAX_LABELS_COUNT

      # Validate group if present
      Configurable::DependabotRunnerSettings.validate_value(group, "Group") if group.present?

      # Convert to storage format
      labels_string = label_array.join(",")

      # If labels are set, group must be explicitly set (even as empty string)
      # to prevent inheritance from parent level and ensure both come from same configuration level
      group_value = if labels_string.present?
        group || ""  # Force empty string if group is nil but labels exist
      else
        group  # Keep original group value when no labels
      end

      # Set both values atomically
      labels_changed = if labels_string.blank?
        config.delete(DEPENDABOT_RUNNER_LABELS_KEY, actor)
      elsif force
        config.set!(DEPENDABOT_RUNNER_LABELS_KEY, labels_string, actor)
      else
        config.set(DEPENDABOT_RUNNER_LABELS_KEY, labels_string, actor)
      end

      group_changed = if group_value.nil?
        config.delete(DEPENDABOT_RUNNER_GROUP_KEY, actor)
      elsif force
        config.set!(DEPENDABOT_RUNNER_GROUP_KEY, group_value, actor)
      else
        config.set(DEPENDABOT_RUNNER_GROUP_KEY, group_value, actor)
      end

      changed = labels_changed || group_changed
      instrument_dependabot_runner_settings_updated(labels: label_array, group: group_value, actor:) if changed
      changed
    end

    # Clear both runner labels and group atomically
    #
    # @param actor [T.untyped] User making the change (must have admin permissions on the target)
    # @return [Boolean] Whether any configuration was changed
    sig { params(actor: T.untyped).returns(T::Boolean) }
    def clear_dependabot_runner_settings(actor:)
      labels_changed = config.delete(DEPENDABOT_RUNNER_LABELS_KEY, actor)
      group_changed = config.delete(DEPENDABOT_RUNNER_GROUP_KEY, actor)
      changed = labels_changed || group_changed
      instrument_dependabot_runner_settings_updated(labels: [], group: nil, actor:) if changed
      changed
    end

    sig { returns(T.nilable(String)) }
    def dependabot_runner_labels
      raw = config.get(DEPENDABOT_RUNNER_LABELS_KEY)
      return nil unless raw.is_a?(String)
      return nil if raw.blank?
      raw
    end

    sig { returns(T.nilable(String)) }
    def dependabot_runner_group
      # Empty string means "explicitly no group" (prevents inheritance)
      # nil means "not set" (allows inheritance)
      config.get(DEPENDABOT_RUNNER_GROUP_KEY)
    end

    # Public: Return runner configuration for Dependabot to consume.
    # Uses Configurable module's automatic inheritance: Repository → Organization → Default
    #
    # Returns:
    #   A Hash with the following keys:
    #     :runner_labels - Array<String>: The labels to use for the runner.
    #     :runner_group  - String or nil: The runner group name.
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def dependabot_runner_settings
      labels_string = dependabot_runner_labels
      labels_array = if labels_string.present?
        labels_string.split(",").map(&:strip)
      else
        DEFAULT_RUNNER_LABELS
      end

      {
        runner_labels: labels_array,
        runner_group: dependabot_runner_group
      }
    end

    sig { params(labels: T::Array[String], group: T.nilable(String), actor: T.untyped).void }
    def instrument_dependabot_runner_settings_updated(labels:, group:, actor:)
      GitHub.instrument(
        "dependabot_runner_settings.updated",
        self.event_context.merge(labels:, group:, actor:)
      )
    end
  end
end
