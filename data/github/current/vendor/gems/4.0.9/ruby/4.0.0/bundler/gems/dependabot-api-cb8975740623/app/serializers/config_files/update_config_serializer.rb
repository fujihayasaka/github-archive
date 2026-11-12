# frozen_string_literal: true

module ConfigFiles
  class UpdateConfigSerializer < ActiveModel::Serializer
    attributes :package_ecosystem, :directory, :schedule
    attribute :cooldown, if: -> { object.update_config_cooldown.present? }

    def package_ecosystem
      ParseConfigFile.token_for(package_manager: object.package_manager)
    end

    def schedule
      { "interval" => object.update_schedule }
    end

    def cooldown
      return nil unless object.update_config_cooldown

      object.update_config_cooldown.cooldown_settings
    end

    attribute :target_branch,
              if: -> { include_defaults? || object.target_branch }
    def target_branch
      object.target_branch || object.repo.default_branch
    end

    attribute :assignees,
              if: -> { include_defaults? || object.default_assignees }
    def assignees
      object.default_assignees || []
    end

    attribute :labels,
              if: -> { include_defaults? || object.custom_labels }
    def labels
      object.custom_labels || object.default_labels
    end

    attribute :versioning_strategy,
              if: lambda {
                include_defaults? && manager_supports_requirement_strategies? ||
                  object.requirements_update_strategy ||
                  object.lockfile_only?
              }
    def versioning_strategy
      requirements_update_strategy = object.requirements_update_strategy
      return convert_update_strategy(requirements_update_strategy) if requirements_update_strategy
      return "lockfile-only" if object.lockfile_only?

      "auto"
    end

    attribute :allow,
              if: lambda {
                include_defaults? ||
                  object.allowed_updates.map(&:symbolize_keys) != [
                    { dependency_type: "direct", update_type: "all" },
                  ]
              }
    def allow
      object.allowed_updates.map do |au|
        {
          "dependency-name" => au.fetch("dependency_name", nil),
          "dependency-type" => au.fetch("dependency_type", nil),
          "update-types" => au.fetch("update_types", nil),
        }.compact
      end
    end

    attribute :ignore,
              if: lambda {
                include_defaults? ||
                  object.ignore_conditions.any?(&:from_config_file?)
              }
    def ignore
      object.ignore_conditions.map do |ic|
        {
          "dependency-name" => ic.dependency_name,
          "versions" => [ic.version_requirement],
        }.compact
      end
    end

    attribute :commit_message,
              if: -> { !object.commit_message_prefix.nil? }
    def commit_message
      {
        "prefix" => object.commit_message_prefix,
        "prefix-development" => object.commit_message_prefix_development,
        "include" => object.commit_message_include_scope ? "scope" : nil,
      }.compact
    end

    attribute :exclude_paths,
              if: -> { object.exclude_paths.present? }
    def exclude_paths
      return nil unless object.exclude_paths

      object.exclude_paths
    end

    private

    def convert_update_strategy(strategy)
      ParseConfigFile::REQUIREMENT_UPDATE_STRATEGY_LOOKUP.invert.fetch(strategy)
    end

    def include_defaults?
      instance_options[:include_defaults]
    end

    def manager_supports_requirement_strategies?
      allowed_package_managers =
        UpdateConfig::UPDATE_STRATEGIES.keys

      allowed_package_managers.include?(object.package_manager)
    end
  end
end
