# typed: true
# frozen_string_literal: true

module DependabotSettings
  class RunnerSettingsComponent < ApplicationComponent
    include GitHub::Memoizer
    include SecurityAnalysisSettingsHelper

    # Runner type constants - reference centralized constants
    RUNNER_TYPE_STANDARD = Configurable::DependabotRunnerSettings::RUNNER_TYPE_STANDARD
    RUNNER_TYPE_LABELED = Configurable::DependabotRunnerSettings::RUNNER_TYPE_LABELED
    DEFAULT_RUNNER_LABELS = Configurable::DependabotRunnerSettings::DEFAULT_RUNNER_LABELS

    # Field name constants for error messages - reference centralized constants
    RUNNER_GROUP_FIELD_NAME = Configurable::DependabotRunnerSettings::RUNNER_GROUP_NAME
    RUNNER_LABEL_FIELD_NAME = Configurable::DependabotRunnerSettings::RUNNER_LABEL_NAME

    RUNNER_TYPES = [
      {
        label: "Standard GitHub runner",
        value: RUNNER_TYPE_STANDARD,
        description: "Dependabot will use standard GitHub runners to run scans",
        action: "selectStandardGithubRunner"
      },
      {
        label: "Labeled runner",
        value: RUNNER_TYPE_LABELED,
        description: "Dependabot will use labeled GitHub or self-hosted runners that you may define.",
        action: "selectLabeledRunner"
      }
    ].freeze

    attr_reader :owner

    def initialize(owner:)
      @owner = owner
    end

    def render?
      true
    end

    def current_runner_type
      @owner.dependabot_self_hosted_enabled_for_new_repos? ? RUNNER_TYPE_LABELED : RUNNER_TYPE_STANDARD
    end

    def current_runner_type_display
      current_runner_type == RUNNER_TYPE_LABELED ? "Labeled runner" : "Standard GitHub runner"
    end

    def current_runner_labels
      # If self-hosted is disabled, don't show any labels
      return "" unless @owner.dependabot_self_hosted_enabled_for_new_repos?

      labels = @owner.dependabot_runner_labels

      # If no labels are set and self-hosted is enabled, return default
      if labels.blank?
        return "dependabot"
      end

      # Convert comma-separated string to display format with spaces after commas
      labels.split(",").map(&:strip).join(", ")
    end

    def current_runner_label
      # If self-hosted is disabled, don't show any labels
      return "" unless @owner.dependabot_self_hosted_enabled_for_new_repos?

      # Return single label as string for form input (ADR: single label only)
      labels_string = @owner.dependabot_runner_labels

      # If no labels are set and self-hosted is enabled, return default
      if labels_string.blank?
        return DEFAULT_RUNNER_LABELS.first
      end

      # Return first label from comma-separated string
      labels_string.split(",").first&.strip || ""
    end

    def default_runner_label
      DEFAULT_RUNNER_LABELS.first
    end

    def current_runner_group
      return nil unless self_hosted_enabled?

      @owner.dependabot_runner_group
    end

    # Main section content
    def runner_section_title
      "Runner type"
    end

    def runner_section_description
      "Select the runner type used by Dependabot for scans and version and security updates."
    end

    def self_hosted_enabled?
      @owner.dependabot_self_hosted_enabled_for_new_repos?
    rescue StandardError
      false
    end

    # Validation error message helpers
    def runner_format_error(field_name)
      "#{field_name} can only contain letters, numbers, hyphens, underscores, and dots."
    end

    def create_runner_type_menu_items(menu:)
      RUNNER_TYPES.each do |runner_type|
        menu.with_item(
          label: runner_type[:label],
          active: current_runner_type == runner_type[:value],
          data: {
            action: "click:dependabot-runner-settings##{runner_type[:action]}",
            value: runner_type[:value]
          }
        ) do |item|
          item.with_description.with_content(runner_type[:description])
        end
      end
    end
  end
end
