# typed: strict
# frozen_string_literal: true

# Manage Copilot coding agent runner configuration for an organization.
# Encapsulates the runner Configurable keys: runner_type, runner_labels, and runner_group_name.
# Currently included by Organization.
module Configurable
  module CopilotSweAgentRunner
    extend T::Helpers

    requires_ancestor { Configurable }

    RUNNER_TYPE_KEY = "copilot_agent_runner_type"
    RUNNER_LABELS_KEY = "copilot_agent_runner_labels"
    RUNNER_GROUP_NAME_KEY = "copilot_agent_runner_group_name"
    ALLOW_REPO_CUSTOM_RUNNER_KEY = "copilot_agent_allow_repo_custom_runner"

    RUNNER_TYPE_STANDARD = "standard"
    RUNNER_TYPE_LABELED = "labeled"
    VALID_RUNNER_TYPES = T.let([RUNNER_TYPE_STANDARD, RUNNER_TYPE_LABELED].freeze, T::Array[String])

    sig { returns(String) }
    def copilot_swe_agent_runner_type
      value = config.raw(RUNNER_TYPE_KEY)
      VALID_RUNNER_TYPES.include?(value) ? value : RUNNER_TYPE_STANDARD
    end

    sig { returns(String) }
    def copilot_swe_agent_runner_labels
      config.raw(RUNNER_LABELS_KEY) || ""
    end

    sig { returns(String) }
    def copilot_swe_agent_runner_group_name
      config.raw(RUNNER_GROUP_NAME_KEY) || ""
    end

    sig { returns(T::Boolean) }
    def copilot_swe_agent_allow_repo_custom_runner
      config.raw(ALLOW_REPO_CUSTOM_RUNNER_KEY) != "false"
    end

    sig { returns(T::Hash[Symbol, T.any(String, T::Boolean)]) }
    def copilot_swe_agent_runner_config
      {
        runner_type: copilot_swe_agent_runner_type,
        runner_labels: copilot_swe_agent_runner_labels,
        runner_group_name: copilot_swe_agent_runner_group_name,
        allow_repo_custom_runner: copilot_swe_agent_allow_repo_custom_runner,
      }
    end

    sig { params(runner_type: T.nilable(String), runner_labels: String, runner_group_name: String, actor: User, allow_repo_custom_runner: T.nilable(T::Boolean)).void }
    def update_copilot_swe_agent_runner(runner_type:, runner_labels:, runner_group_name:, actor:, allow_repo_custom_runner: nil)
      if runner_type == RUNNER_TYPE_LABELED && runner_labels.blank? && runner_group_name.blank?
        Kernel.raise ArgumentError, "Labeled runner requires at least a runner label or runner group name"
      end

      if runner_type.present? && VALID_RUNNER_TYPES.include?(runner_type)
        config.set!(RUNNER_TYPE_KEY, runner_type, actor)
      end
      config.set!(RUNNER_LABELS_KEY, runner_labels, actor)
      config.set!(RUNNER_GROUP_NAME_KEY, runner_group_name, actor)
      unless allow_repo_custom_runner.nil?
        config.set!(ALLOW_REPO_CUSTOM_RUNNER_KEY, allow_repo_custom_runner.to_s, actor)
      end
    end
  end
end
