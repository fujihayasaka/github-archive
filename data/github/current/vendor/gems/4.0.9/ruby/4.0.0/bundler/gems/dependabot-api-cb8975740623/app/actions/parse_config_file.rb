# frozen_string_literal: true

require "yaml"
require "json"
require "json-schema"
require "dependabot/utils"
require "dependabot/cronjob_validator"

# Parses a config file. Returns a hash of update config details to be created or
# updated.
#
# rubocop:disable Metrics/ClassLength
class ParseConfigFile
  class Unparseable < StandardError; end

  class Invalid < StandardError
    ERROR_MESSAGE_LIMIT = 50

    attr_reader :errors

    def initialize(errors)
      @errors = errors
      super(concatenated_error_messages)
    end

    private

    def concatenated_error_messages
      messages = errors.take(ERROR_MESSAGE_LIMIT).map { |e| e.fetch(:message) }

      messages << "and #{errors.length - ERROR_MESSAGE_LIMIT} more errors." if errors.length > ERROR_MESSAGE_LIMIT

      messages.join("\n")
    end
  end

  # NOTE: If this ever ceases to be 1-to-1 we will need to update places that
  # invert it (e.g., ConfigFiles::UpdateConfigSerializer)
  PACKAGE_MANAGER_LOOKUP = {
    "bazel" => PackageManagers::BAZEL,
    "bun" => PackageManagers::BUN,
    "bundler" => PackageManagers::BUNDLER,
    "cargo" => PackageManagers::CARGO,
    "composer" => PackageManagers::COMPOSER,
    "conda" => PackageManagers::CONDA,
    "deno" => PackageManagers::DENO,
    "devcontainers" => PackageManagers::DEVCONTAINERS,
    "docker" => PackageManagers::DOCKER,
    "docker-compose" => PackageManagers::DOCKER_COMPOSE,
    "dotnet-sdk" => PackageManagers::DOTNET_SDK,
    "elm" => PackageManagers::ELM,
    "github-actions" => PackageManagers::GITHUB_ACTIONS,
    "gitsubmodule" => PackageManagers::SUBMODULES,
    "gomod" => PackageManagers::GO_MODULES,
    "gradle" => PackageManagers::GRADLE,
    "helm" => PackageManagers::HELM,
    "julia" => PackageManagers::JULIA,
    "maven" => PackageManagers::MAVEN,
    "mix" => PackageManagers::HEX,
    "nix" => PackageManagers::NIX,
    "nuget" => PackageManagers::NUGET,
    "npm" => PackageManagers::NPM_AND_YARN,
    "opentofu" => PackageManagers::OPENTOFU,
    "pip" => PackageManagers::PIP,
    "pre-commit" => PackageManagers::PRE_COMMIT,
    "pub" => PackageManagers::PUB,
    "rust-toolchain" => PackageManagers::RUST_TOOLCHAIN,
    "sbt" => PackageManagers::SBT,
    "swift" => PackageManagers::SWIFT,
    "terraform" => PackageManagers::TERRAFORM,
    "uv" => PackageManagers::UV,
    "vcpkg" => PackageManagers::VCPKG,
  }.freeze

  # Translate customer-specified registry type to internal representation
  REGISTRY_TYPE_LOOKUP = {
    "cargo-registry" => "cargo_registry",
    "composer-repository" => "composer_repository",
    "docker-registry" => "docker_registry",
    "git" => "git_source",
    "helm-registry" => "helm_registry",
    "hex-organization" => "hex_organization",
    "hex-repository" => "hex_repository",
    "maven-repository" => "maven_repository",
    "npm-registry" => "npm_registry",
    "nuget-feed" => "nuget_feed",
    "pub-repository" => "pub_repository",
    "python-index" => "python_index",
    "rubygems-server" => "rubygems_server",
    "terraform-registry" => "terraform_registry",
    "goproxy-server" => "goproxy_server",
  }.freeze

  # NOTE: If this ever ceases to be 1-to-1 we will need to update places that
  # invert it (e.g., ConfigFiles::UpdateConfigSerializer)
  REQUIREMENT_UPDATE_STRATEGY_LOOKUP = {
    "widen" => "widen_ranges",
    "increase" => "bump_versions",
    "increase-if-necessary" => "bump_versions_if_necessary",
    "lockfile-only" => "lockfile_only",
  }.freeze

  SEMVER_SUPPORTED_PACKAGE_MANAGERS = [
    PackageManagers::BUNDLER,
    PackageManagers::CARGO,
    PackageManagers::COMPOSER,
    PackageManagers::PUB,
    PackageManagers::DOTNET_SDK,
    PackageManagers::ELM,
    PackageManagers::GO_MODULES,
    PackageManagers::GRADLE,
    PackageManagers::MAVEN,
    PackageManagers::HEX,
    PackageManagers::NUGET,
    PackageManagers::NPM_AND_YARN,
    PackageManagers::PIP,
    PackageManagers::SWIFT,
    PackageManagers::BUN,
    PackageManagers::UV,
    PackageManagers::RUST_TOOLCHAIN,
    PackageManagers::SBT,
    PackageManagers::CONDA,
    PackageManagers::DENO,
    PackageManagers::JULIA,
  ].freeze

  COOLDOWN_SUPPORTED_PACKAGE_MANAGERS = [
    PackageManagers::BUNDLER,
    PackageManagers::PIP,
    PackageManagers::UV,
    PackageManagers::NPM_AND_YARN,
    PackageManagers::BUN,
    PackageManagers::DOCKER,
    PackageManagers::DOCKER_COMPOSE,
    PackageManagers::MAVEN,
    PackageManagers::CARGO,
    PackageManagers::GO_MODULES,
    PackageManagers::COMPOSER,
    PackageManagers::GRADLE,
    PackageManagers::PUB,
    PackageManagers::SUBMODULES,
    PackageManagers::ELM,
    PackageManagers::GITHUB_ACTIONS,
    PackageManagers::DEVCONTAINERS,
    PackageManagers::HEX,
    PackageManagers::DOTNET_SDK,
    PackageManagers::VCPKG,
    PackageManagers::RUST_TOOLCHAIN,
    PackageManagers::HELM,
    PackageManagers::TERRAFORM,
    PackageManagers::SWIFT,
    PackageManagers::CONDA,
    PackageManagers::NUGET,
    PackageManagers::JULIA,
    PackageManagers::OPENTOFU,
    PackageManagers::BAZEL,
    PackageManagers::PRE_COMMIT,
    PackageManagers::NIX,
    PackageManagers::DENO,
  ].freeze

  COOLDOWN_FIELDS = %w(
    default-days
    semver-major-days
    semver-minor-days
    semver-patch-days
  ).freeze

  MINIMUM_COOLDOWN_DAYS = 1
  MAXIMUM_COOLDOWN_DAYS = 90

  SEMVER_COOLDOWN_FIELDS = COOLDOWN_FIELDS - ["default-days"]

  def self.token_for(package_manager:)
    @token_lookup ||= PACKAGE_MANAGER_LOOKUP.invert
    @token_lookup.fetch(package_manager)
  end

  def initialize(config_file:, repo:)
    @config_file = config_file
    @repo = repo
  end

  def run
    validated_config_file
  end

  def automerge
    validated_config_file.dig("automerge", "enabled") == true
  end

  def days_before_automerge
    validated_config_file.dig("automerge", "days-before-merge")
  end

  def updates
    @updates ||= validated_config_file["updates"].map do |uc|
      next if uc["multi-ecosystem-group"]

      update_config = uc.merge(beta_ecosystem_setting)
      transform_update_config_details(update_config)
    end
  end

  def multi_ecosystem_updates
    @multi_ecosystem_updates ||= validated_config_file["updates"].map do |uc|
      next unless uc["multi-ecosystem-group"]

      raise_if_multi_ecosystems_disabled!

      group_name = uc["multi-ecosystem-group"]
      group = validated_config_file.dig("multi-ecosystem-groups", group_name) || {}

      transform_update_config_details(uc).merge(
        "multi_ecosystem_config_name" => group_name,
        "multi_ecosystem_config_update_types" => group["update-types"],
        "multi_ecosystem_config_dependency_type" => group["dependency-type"],
        "multi_ecosystem_config_exclude_patterns" => group["exclude-patterns"],
        "update-schedule" => group.dig("schedule", "interval"),
        "update-schedule-time-of-day" => group.dig("schedule", "time"),
        "update-schedule-day-of-week" => group.dig("schedule", "day"),
        "update-schedule-timezone" => group.dig("schedule", "timezone"),
        "update-schedule-cron-expression" => group.dig("schedule", "cronjob"),
      )
    end.compact
  end

  def multi_ecosystem_names
    multi_ecosystem_groups = validated_config_file.fetch("multi-ecosystem-groups", {})
    return [] if multi_ecosystem_groups.empty?

    raise_if_multi_ecosystems_disabled!

    multi_ecosystem_groups.keys
  end

  def multi_ecosystem_exclusions
    @multi_ecosystem_exclusions ||=
      multi_ecosystem_updates.
      each_with_object(nested_hash_with_array_defaults) do |uc, exclusions|
        package_manager = uc["package-manager"]
        patterns = uc["multi_ecosystem_config_patterns"].map do |p|
          { "dependency_name" => p, "version_requirement" => ">= 0" }
        end

        directories_for_update_config(uc).each do |directory|
          exclusions[package_manager][directory] += patterns
        end
      end
  end

  def registries
    @registries ||= validated_config_file["registries"]&.
                    transform_values { |reg| transform_registry_details(reg) }
  end

  def enable_beta_ecosystems?
    @enable_beta_ecosystems ||= parsed_config_file["enable-beta-ecosystems"] || false
  end

  private

  attr_reader :config_file

  def validated_config_file
    return @validated_config_file if defined?(@validated_config_file)

    validate_parsed_config_file(parsed_config_file)
    @validated_config_file = parsed_config_file
  end

  def parsed_config_file
    # NOTE: Supporting aliases would be nice, but can create recursive
    # structures that have memory leaks
    @parsed_config_file ||= YAML.safe_load(config_file.content, aliases: false)
  rescue Psych::SyntaxError, Psych::DisallowedClass => e
    raise Unparseable, e.message
  rescue Psych::BadAlias
    raise Unparseable, "YAML aliases are not supported"
  end

  # rubocop:disable Metrics/MethodLength
  def validate_parsed_config_file(config_hash)
    # JSON::Validator blows up unless we provide a hash
    unless config_hash.is_a?(Hash)
      errs = [
        {
          fragment: "#/",
          message: "Top level entity must be an Object, "\
                   "not a #{config_hash.class}",
        },
      ]
      raise Invalid, errs
    end

    validate_top_level_config(config_hash)
    validate_package_ecosystems(config_hash)
    validate_no_glob_in_directory(config_hash)
    validate_unique_update_configs_with_globs_and_heuristics(config_hash)
    validate_update_configs(config_hash)
    validate_registries(config_hash)
    validate_multi_ecosystem_groups(config_hash)
    validate_update_config_registries(config_hash)
    validate_all_registries_are_used(config_hash)
    validate_ignore_conditions(config_hash)
    validate_directories(config_hash)
    validate_cooldown(config_hash)
    validate_cronjob(config_hash)
    validate_multi_ecosystem_update_fields(config_hash)
    validate_exclude_paths(config_hash)
  end
  # rubocop:enable Metrics/MethodLength

  def validate_multi_ecosystem_update_fields(config_hash)
    errors = []

    (config_hash["updates"] || []).each_with_index do |update, idx|
      next unless update["multi-ecosystem-group"]

      errors.concat(validate_forbidden_fields_on_multi_ecosystem_update(update, idx))
    end

    raise Invalid, errors if errors.any?
  end

  def validate_forbidden_fields_on_multi_ecosystem_update(update, idx)
    forbidden_fields = %w(
      milestone
      commit-message
      target-branch
      open-pull-requests-limit
      pull-request-branch-name
    )

    forbidden_fields.filter_map do |field|
      next unless update[field]

      create_multi_ecosystem_field_error(field, idx)
    end
  end

  def create_multi_ecosystem_field_error(field, idx)
    {
      fragment: "#/updates/#{idx}/#{field}",
      message: "\"#{field}\" should only be set on the associated multi-ecosystem group, " \
               "not directly on updates that are part of a multi-ecosystem update group.",
    }
  end

  def validate_multi_ecosystem_groups(config_hash)
    errors = []
    groups = config_hash["multi-ecosystem-groups"]
    return if groups.nil?

    errors.concat(validate_group_structures(groups))
    errors.concat(validate_group_references(config_hash, groups))

    raise Invalid, errors if errors.any?
  end

  def validate_group_structures(groups)
    errors = []
    groups.each do |group_name, group_config|
      unless group_config.is_a?(Hash)
        errors << {
          fragment: "#/multi-ecosystem-groups/#{group_name}",
          message: "The group '#{group_name}' must be an object.",
        }
        next
      end

      next if group_config.key?("schedule")

      errors << {
        fragment: "#/multi-ecosystem-groups/#{group_name}",
        message: "The group '#{group_name}' must include a 'schedule' property.",
      }
    end
    errors
  end

  def validate_group_references(config_hash, groups)
    errors = []
    (config_hash["updates"] || []).each_with_index do |update, idx|
      next unless update["multi-ecosystem-group"]

      group_name = update["multi-ecosystem-group"]
      next if groups.key?(group_name)

      errors << {
        fragment: "#/updates/#{idx}/multi-ecosystem-group",
        message: "The multi-ecosystem-group '#{group_name}' is not defined in multi-ecosystem-groups.",
      }
    end
    errors
  end

  def validate_top_level_config(config_hash)
    config_errors = JSON::Validator.fully_validate(
      schema, config_hash,
      version: :draft6,
      parse_data: false,
      errors_as_objects: true,
      fragment: "#/definitions/top_level",
    )

    raise Invalid, sanitize_errors(config_errors) if config_errors.any?
  end

  def validate_package_ecosystems(config_hash)
    errors = []
    config_hash["updates"].each do |config|
      package_manager = config["package-ecosystem"]
      next if released_or_enabled_beta_ecosystem?(package_manager)

      errors.push(
        fragment: "#/enable-beta-ecosystems",
        message: "The enable-beta-ecosystems setting must be true to use the package-ecosystem #{package_manager}."
      )
    end

    raise Invalid, errors if errors.any?
  end

  def validate_no_glob_in_directory(config_hash)
    config_errors = []
    config_hash["updates"].each_with_index do |config, index|
      next unless config.key?("directory")

      next unless Directories.new([config["directory"]]).contains_glob?

      config_errors.push(
        fragment: "#/updates/#{index}/directory",
        message: "The property '#/updates/#{index}/directory' must not include a glob pattern",
      )
    end

    raise Invalid, config_errors if config_errors.any?
  end

  def validate_unique_update_configs_with_globs_and_heuristics(config_hash)
    partitioned_configs = partition_configs(config_hash)
    config_errors = check_overlapping_directories(partitioned_configs)
    raise Invalid, config_errors if config_errors.any?
  end

  def partition_configs(config_hash)
    updates_array = config_hash["updates"].reject { |item| item.key?("multi-ecosystem-group") }

    updates_array.each_with_object({}) do |update_config, partitioned_configs|
      package_manager = update_config["package-ecosystem"]
      directory = update_config["directory"]
      target_branch = update_config["target-branch"]
      directories = update_config["directories"]

      key = OpenStruct.new(
        package_manager: package_manager,
        target_branch: target_branch,
      )
      partitioned_configs[key] ||= []
      partitioned_configs[key] << Directories.new(directories || directory)
    end
  end

  def check_overlapping_directories(partitioned_configs)
    config_errors = []
    partitioned_configs.each do |(key, all_directories_in_ecosystem_branch_pair)|
      begin
        next unless all_directories_in_ecosystem_branch_pair.combination(2).any? { |d1, d2| d1.overlap?(d2) }
      rescue Directories::IndeterminateOverlapError
        msg = "Dependabot cannot determine if '#{key.package_manager}' has overlapping directories"
      else
        msg = "Ecosystem '#{key.package_manager}' has overlapping directories"
      end

      msg += " for target branch '#{key.target_branch}'" unless key.target_branch.nil?
      config_errors << {
        message: "Update configs must have a unique combination of "\
          "'package-ecosystem', 'directory', and 'target-branch'. #{msg}.",
      }
    end
    config_errors
  end

  def validate_update_configs(config_hash)
    config_errors = []

    config_hash["updates"].each_with_index do |update_config, index|
      errors = validate_single_update_config(update_config, index)
      config_errors.push(errors: errors, index: index) if errors.any?
    end

    return if config_errors.empty?

    errors = flatten_config_errors(config_errors, "updates")
    errors = sanitize_errors(errors)

    raise Invalid, errors
  end

  def validate_single_update_config(update_config, index)
    package_manager = update_config["package-ecosystem"]
    errors = JSON::Validator.fully_validate(
      schema, update_config,
      version: :draft6,
      parse_data: false,
      errors_as_objects: true,
      fragment: "#/definitions/#{package_manager}",
    )

    check_multi_ecosystem_group_requirements(update_config, index)
    check_schedule_requirement(update_config, index)

    errors
  end

  def check_multi_ecosystem_group_requirements(update_config, index)
    return unless update_config["multi-ecosystem-group"] && !update_config["patterns"]

    raise Invalid, [
      {
        fragment: "#/updates/patterns",
        message: "The property '#/updates/#{index}/patterns' is required "\
          "when 'multi-ecosystem-group' is set.",
      },
    ]
  end

  def check_schedule_requirement(update_config, index)
    return unless !update_config["multi-ecosystem-group"] && !update_config["schedule"]

    raise Invalid, [
      {
        fragment: "#/updates/multi-ecosystem-group",
        message: "The property '#/updates/#{index}' did not contain a "\
          "required property of 'schedule'",
      },
    ]
  end

  def multi_ecosystems_enabled?
    @repo.config_feature_enabled?(:multi_ecosystems) # rubocop:disable Dependabot/NoLocalFeatureFlags
  end

  def raise_if_multi_ecosystems_disabled!
    return if multi_ecosystems_enabled?

    raise Invalid, [
      {
        fragment: "#/multi-ecosystem-groups",
        message: "The property '#/multi-ecosystem-groups' is not supported "\
          "when multi-ecosystems is not enabled.",
      },
    ]
  end

  def validate_package_ecosystem_errors(update_config)
    package_manager = update_config["package-ecosystem"]
    JSON::Validator.fully_validate(
      schema, update_config,
      version: :draft6,
      parse_data: false,
      errors_as_objects: true,
      fragment: "#/definitions/#{package_manager}",
    )
  end

  def validate_registries(config_hash)
    config_errors = []
    config_hash["registries"]&.each do |name, registry|
      registry_type = registry["type"]
      errors = JSON::Validator.fully_validate(
        schema, registry,
        version: :draft6,
        parse_data: false,
        errors_as_objects: true,
        fragment: "#/definitions/#{registry_type}",
      )
      config_errors.push(errors: errors, index: name) if errors.any?
    end

    errors = flatten_config_errors(config_errors, "registries")
    errors += registry_name_errors(config_hash)
    errors = sanitize_errors(errors)

    raise Invalid, errors if errors.any?
  end

  def registry_name_errors(config_hash)
    registry_names = config_hash.fetch("registries", {}).keys

    registry_names.map do |name|
      next unless name.length > Registry::NAME_MAX_LENGTH

      {
        fragment: "#/registries/#{name}",
        message: "The registry name '#{name}' is too long. The maximum is #{Registry::NAME_MAX_LENGTH} characters.",
      }
    end.compact
  end

  def validate_update_config_registries(config_hash)
    registry_names = config_hash.fetch("registries", {}).keys

    errors = []
    config_hash["updates"].each_with_index do |config, index|
      next unless config.key?("registries")
      next if config["registries"] == "*"

      nonexistent_registries = config["registries"] - registry_names

      nonexistent_registries.each do |name|
        fragment = "#/updates/#{index}/registries"
        errors.push(
          fragment: fragment,
          message: "The property '#{fragment}' includes the \"#{name}\" registry " \
            "which is not defined in the top-level 'registries' definition"
        )
      end
    end
    return if errors.empty?

    raise Invalid, errors
  end

  def validate_all_registries_are_used(config_hash)
    registry_names = config_hash.fetch("registries", {}).keys
    return if registry_names.empty?

    used_registries = []
    wildcard_used = false

    config_hash["updates"].each do |config|
      break (wildcard_used = true) if config["registries"] == "*"

      used_registries |= config.fetch("registries", [])
    end

    return if wildcard_used

    unused_registries = registry_names - used_registries
    return if unused_registries.empty?

    fragment = "#/registries"
    errors = []
    unused_registries.each do |name|
      errors.push(fragment: fragment,
                  message: "The property '#{fragment}' includes the \"#{name}\" registry " \
                    "which is not used in any of the configurations")
    end

    raise Invalid, errors
  end

  def validate_ignore_conditions(config_hash)
    config_errors = []
    config_hash["updates"].each_with_index do |config, index|
      config_errors += ignore_errors(config, index) if config.key?("package-ecosystem")
    end
    raise Invalid, config_errors if config_errors.any?
  end

  def validate_directories(config_hash)
    errors = []
    config_hash["updates"].each_with_index do |updates_config, index|
      if updates_config.key?("directory") && updates_config["directory"].include?("..")
        errors.push(
          fragment: "#/updates/#{index}/directory",
          message: "The property '#/updates/#{index}/directory' must not "\
                    "include '..'",
        )
      end

      next unless updates_config.key?("directories") && updates_config.key?("directory")

      errors.push(
        fragment: "#/updates/#{index}/directories",
        message: "The property '#/updates/#{index}/directories' must not "\
                  "be used with 'directory'",
      )
    end

    raise Invalid, errors if errors.any?
  end

  def validate_cooldown(config_hash)
    errors = []
    config_hash["updates"].each_with_index do |config, index|
      next unless config.key?("cooldown")

      package_manager = config["package-ecosystem"]
      cooldown = config["cooldown"]
      errors.concat(validate_cooldown_enablement(package_manager, cooldown, index))
    end

    raise Invalid, errors if errors.any?
  end

  def validate_exclude_paths(config_hash)
    errors = []
    config_hash["updates"].each_with_index do |config, index|
      next unless config.key?("exclude-paths")

      exclude_paths = config["exclude-paths"]
      errors.concat(validate_exclude_paths_structure(exclude_paths, index))
    end

    raise Invalid, errors if errors.any?
  end

  def validate_exclude_paths_structure(exclude_paths, index)
    errors = []
    unless exclude_paths.is_a?(Array)
      errors.push(
        fragment: "#/updates/#{index}/exclude-paths",
        message: "The property '#/updates/#{index}/exclude-paths' did not match the following type: array",
      )
      return errors
    end

    exclude_paths.each_with_index do |path, path_index|
      unless path.is_a?(String)
        errors.push(
          fragment: "#/updates/#{index}/exclude-paths/#{path_index}",
          message: "The property '#/updates/#{index}/exclude-paths/#{path_index}' must be a string.",
        )
        next
      end
      errors.concat(validate_exclude_path_pattern(path, index, path_index))
    end

    errors
  end

  def validate_exclude_path_pattern(path, index, path_index) # rubocop:disable Metrics/MethodLength,Metrics/PerceivedComplexity
    errors = []

    if path.include?("..")
      errors.push(
        fragment: "#/updates/#{index}/exclude-paths/#{path_index}",
        message: "The property '#/updates/#{index}/exclude-paths/#{path_index}' must not include '..'.",
      )
    end

    if path.starts_with?("/") && path != "/"
      errors.push(
        fragment: "#/updates/#{index}/exclude-paths/#{path_index}",
        message: "The property '#/updates/#{index}/exclude-paths/#{path_index}' should be relative to the repository root.", # rubocop:disable Layout/LineLength
      )
    end

    if path.include?("//")
      errors.push(
        fragment: "#/updates/#{index}/exclude-paths/#{path_index}",
        message: "The property '#/updates/#{index}/exclude-paths/#{path_index}' must not include '//' as a path separator.", # rubocop:disable Layout/LineLength
      )
    end

    if path.include?("\\")
      errors.push(
        fragment: "#/updates/#{index}/exclude-paths/#{path_index}",
        message: "The property '#/updates/#{index}/exclude-paths/#{path_index}' must not include '\\' as a path separator. Use forward slashes for path separation.", # rubocop:disable Layout/LineLength
      )
    end

    if path.strip.empty?
      errors.push(
        fragment: "#/updates/#{index}/exclude-paths/#{path_index}",
        message: "The property '#/updates/#{index}/exclude-paths/#{path_index}' must not be empty.",
      )
    end

    if path.count("[") != path.count("]")
      errors.push(
        fragment: "#/updates/#{index}/exclude-paths/#{path_index}",
        message: "The property '#/updates/#{index}/exclude-paths/#{path_index}' must have matching brackets.",
      )
    end

    if path.count("{") != path.count("}")
      errors.push(
        fragment: "#/updates/#{index}/exclude-paths/#{path_index}",
        message: "The property '#/updates/#{index}/exclude-paths/#{path_index}' must have matching curly braces.",
      )
    end

    if path.match?(/\*{3,}/)
      errors.push(
        fragment: "#/updates/#{index}/exclude-paths/#{path_index}",
        message: "The property '#/updates/#{index}/exclude-paths/#{path_index}' must not include more than two consecutive asterisks.", # rubocop:disable Layout/LineLength
      )
    end
    errors
  end

  # rubocop:disable Metrics/PerceivedComplexity
  def validate_cronjob(config_hash)
    errors = []

    config_hash["updates"].each_with_index do |config, index|
      next unless config.key?("schedule")
      next if config.key?("multi-ecosystem-group")

      schedule = config["schedule"]
      interval = schedule.fetch("interval", nil)

      next unless interval && interval == "cron"

      cronjob = schedule.fetch("cronjob", nil)

      if cronjob.nil?
        errors.push(
          fragment: "#/updates/#{index}/schedule",
          message: "The property '#/updates/#{index}/interval' must "\
                    "include 'cronjob' property if interval type is 'cron'",
        )
      elsif cronjob
        errors.concat(validate_cronjob_enablement(cronjob, index))
      end
    end

    raise Invalid, errors if errors.any?
  end
  # rubocop:enable Metrics/PerceivedComplexity

  def package_manager_alias(package_manager)
    PACKAGE_MANAGER_LOOKUP[package_manager] || package_manager
  end

  def validate_cooldown_enablement(package_manager, cooldown, index)
    unless COOLDOWN_SUPPORTED_PACKAGE_MANAGERS.include?(package_manager_alias(package_manager))
      return [{
        fragment: "#/updates/#{index}/cooldown",
        message: "The property '#/updates/#{index}/cooldown' is not supported "\
                 "for the package ecosystem '#{package_manager}'.",
      }]
    end

    errors = []
    errors.concat(validate_cooldown_structure(package_manager, cooldown, index))
    errors
  end

  def validate_cronjob_enablement(cronjob, index)
    errors = []
    begin
      Dependabot::CronjobValidator.validate_cronjob_expression(cronjob)
    rescue Dependabot::CronjobValidator::InvalidCronjobExpressionError => e
      errors << {
        fragment: "#/updates/#{index}/schedule/interval/cronjob",
        message: "The property '#/updates/#{index}/schedule/interval/cronjob' is invalid: #{e.message}",
      }
    end
    errors
  end

  def validate_cooldown_structure(package_manager, cooldown, index)
    unless cooldown.is_a?(Hash)
      return [{
        fragment: "#/updates/#{index}/cooldown",
        message: "The property '#/updates/#{index}/cooldown' must be an object.",
      }]
    end

    errors = []
    errors.concat(validate_cooldown_integer_fields(package_manager, cooldown, index))
    errors.concat(validate_cooldown_array_fields(cooldown, index))
    errors
  end

  # rubocop:disable Metrics/MethodLength
  def validate_cooldown_integer_fields(package_manager, cooldown, index)
    COOLDOWN_FIELDS.each_with_object([]) do |field, errs|
      next unless cooldown.key?(field)

      unless cooldown[field].is_a?(Integer)
        errs << {
          fragment: "#/updates/#{index}/cooldown/#{field}",
          message: "The property '#/updates/#{index}/cooldown/#{field}' must be an integer.",
        }
      end

      unless cooldown[field].between?(MINIMUM_COOLDOWN_DAYS, MAXIMUM_COOLDOWN_DAYS)
        errs << {
          fragment: "#/updates/#{index}/cooldown/#{field}",
          message: "The property '#/updates/#{index}/cooldown/#{field}' must be between "\
                    "#{MINIMUM_COOLDOWN_DAYS} and #{MAXIMUM_COOLDOWN_DAYS}.",
        }
      end

      next unless SEMVER_COOLDOWN_FIELDS.include?(field)

      next if SEMVER_SUPPORTED_PACKAGE_MANAGERS.include?(package_manager_alias(package_manager))

      errs << {
        fragment: "#/updates/#{index}/cooldown/#{field}",
        message: "The property '#/updates/#{index}/cooldown/#{field}' is not supported "\
                 "for the package ecosystem '#{package_manager}'.",
      }
    end
  end
  # rubocop:enable Metrics/MethodLength

  # Checks that if package manager support semver cooldowns,
  def validate_cooldown_for_semver(package_manager, field, index); end

  def validate_cooldown_array_fields(cooldown, index)
    %w(include exclude).each_with_object([]) do |field, errs|
      next unless cooldown.key?(field)
      next if cooldown[field].is_a?(Array)

      errs << {
        fragment: "#/updates/#{index}/cooldown/#{field}",
        message: "The property '#/updates/#{index}/cooldown/#{field}' must be an array.",
      }
    end
  end

  def ignore_errors(config, index) # rubocop:disable Metrics/MethodLength
    config_errors = []

    package_manager = config.fetch("package-ecosystem")
    transformed_package_manager = transform_package_manager(config)

    unique_ignores = Set.new
    Array(config["ignore"]).each_with_index do |ic, i| # rubocop:disable Metrics/BlockLength
      if duplicate_ignore?(unique_ignores, ic, "update-types")
        fragment = "#/updates/#{index}/ignore/#{i}/update-types"
        config_errors.push(
          fragment: fragment,
          message: "The property '#{fragment}' includes a duplicate. Ignores must "\
                   "have a unique combination of 'dependency-name' and 'update-types'",
        )
      end

      if duplicate_ignore?(unique_ignores, ic, "versions")
        fragment = "#/updates/#{index}/ignore/#{i}/versions"
        config_errors.push(
          fragment: fragment,
          message: "The property '#{fragment}' includes a duplicate. Ignores must "\
                   "have a unique combination of 'dependency-name' and 'versions'",
        )
      end

      # NOTE: Only validate dependency-name when there are no versions or
      # update-types as this will generate a duplicate ic matching all versions
      if !ic["versions"] && !ic["update-types"] && duplicate_ignore?(unique_ignores, ic, "dependency-name")
        fragment = "#/updates/#{index}/ignore/#{i}/dependency-name"
        config_errors.push(
          fragment: fragment,
          message: "The property '#{fragment}' is a duplicate.",
        )
      end

      next if versions_valid?(ic["versions"], transformed_package_manager)

      fragment = "#/updates/#{index}/ignore/#{i}/versions"
      config_errors.push(
        fragment: fragment,
        message: "The property '#{fragment}' includes invalid version "\
                 "requirements for a #{package_manager} ignore condition",
      )
    end

    config_errors
  end

  def versions_valid?(versions, package_manager)
    Array(versions).each do |version_reqs|
      requirement_class(package_manager).requirements_array(version_reqs)
    end

    true
  rescue Gem::Requirement::BadRequirementError
    false
  end

  def duplicate_ignore?(unique_ignores, ignore, ignore_key)
    Array(ignore[ignore_key]).each do |value|
      key = [ignore["dependency-name"], value].uniq
      return true if unique_ignores.include?(key)

      unique_ignores.add(key)
    end

    false
  end

  def extract_schedule(uc_details)
    if uc_details["multi-ecosystem-group"]
      group_name = uc_details["multi-ecosystem-group"]
      group = validated_config_file.dig("multi-ecosystem-groups", group_name)
      group_schedule = group && group["schedule"]
      return group_schedule if group_schedule
    end
    uc_details["schedule"]
  end

  def nested_hash_with_array_defaults
    Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = [] } }
  end

  def directories_for_update_config(uc_details)
    if uc_details["directories"]
      uc_details["directories"]
    elsif uc_details["directory"]
      [uc_details["directory"]]
    else
      []
    end
  end

  # rubocop:disable Metrics/MethodLength
  # rubocop:disable Metrics/AbcSize
  def transform_update_config_details(uc_details)
    update_schedule = extract_schedule(uc_details)
    normalize_update_schedule(update_schedule)

    details = {
      "package-manager" => transform_package_manager(uc_details),
      "enable-beta-ecosystems" => uc_details.fetch("enable-beta-ecosystems", false),
      "directory" => clean_directory(uc_details.fetch("directory", nil)),
      "update-schedule" => update_schedule["interval"],
      "update-schedule-time-of-day" => update_schedule["time"],
      "update-schedule-day-of-week" => update_schedule["day"],
      "update-schedule-timezone" => update_schedule["timezone"],
      "update-schedule-cron-expression" => cron_expression(update_schedule),
      "target-branch" => transform_config_param(uc_details, "target-branch").presence&.strip,
      "default-reviewers" => nil,
      "default-assignees" => transform_assignees(uc_details),
      "default-milestone" => transform_config_param(uc_details, "milestone"),
      "custom-labels" => uc_details.fetch("labels", nil),
      "lockfile-only" => transform_lockfile_only(uc_details),
      "requirements-update-strategy" =>
        transform_requirements_update_strategy(uc_details),
      "allowed-updates" => transform_allowed_updates(uc_details),
      "ignore-conditions" => transform_ignore_conditions(uc_details),
      "commit-message-prefix" => transform_nested_config_param(uc_details, "commit-message", "prefix"),
      "commit-message-prefix-development" =>
        transform_nested_config_param(uc_details, "commit-message", "prefix-development"),
      "commit-message-include-scope" =>
        transform_commit_message_include_scope(uc_details),
      "open-pull-requests-limit" =>
        transform_config_param(uc_details, "open-pull-requests-limit"),
      "rebase-strategy" => uc_details.fetch("rebase-strategy", nil),
      "pull-request-branch-name-separator" =>
        transform_nested_config_param(uc_details, "pull-request-branch-name", "separator"),
      "vendor" => uc_details.fetch("vendor", false),
      "registries" => uc_details.fetch("registries", nil),
      "insecure-external-code-execution" => uc_details.fetch("insecure-external-code-execution", nil),
      "groups" => uc_details.fetch("groups", nil),
      "cooldown" => transform_cooldown(uc_details),
      "multi_ecosystem_config_id" => nil,
      "multi_ecosystem_config_patterns" => uc_details.fetch("patterns", nil),
      "multi_ecosystem_config_name" => uc_details.fetch("multi-ecosystem-group", nil),
      "exclude-paths" => uc_details.fetch("exclude-paths", nil)&.presence,
    }
    details["directories"] = clean_directories(uc_details.fetch("directories")) if uc_details.key?("directories")
    details
  end
  # rubocop:enable Metrics/AbcSize
  # rubocop:enable Metrics/MethodLength

  def normalize_update_schedule(update_schedule)
    update_schedule["time"] ||= @repo.default_update_schedule_time_of_day
    update_schedule["timezone"] ||= UpdateConfig::DEFAULT_UPDATE_SCHEDULE_TIMEZONE

    update_schedule["day"] ||= @repo.default_update_schedule_day_of_week if update_schedule["interval"] == "weekly"

    update_schedule
  end

  def cron_expression(update_schedule)
    timezone = update_schedule["timezone"]

    return "#{update_schedule['cronjob']} #{timezone}" if update_schedule["interval"] == "cron"

    # Get the time of day and create a cron in the specified timezone
    time_of_day = Time.use_zone(timezone) { Time.zone.parse(update_schedule["time"]) }

    case update_schedule["interval"]
    when "daily"
      # run every weekday, at the specified minute and hour, in the specified timezone
      "#{time_of_day.min} #{time_of_day.hour} * * 1-5 #{timezone}"
    when "weekly"
      # run on the specified day of the week, at the specified minute and hour, in the specified timezone
      day_of_week = day_of_week_to_cron(update_schedule["day"])
      "#{time_of_day.min} #{time_of_day.hour} * * #{day_of_week} #{timezone}"
    when "monthly"
      # run on the 1st of every month, at the specified minute and hour, in the specified timezone
      "#{time_of_day.min} #{time_of_day.hour} 1 * * #{timezone}"
    when "quarterly"
      # run on the 1st of Jan, Apr, Jul, Oct at the specified minute and hour, in the specified timezone
      "#{time_of_day.min} #{time_of_day.hour} 1 1,4,7,10 * #{timezone}"
    when "semiannually"
      # run on the 1st of Jan and Jul at the specified minute and hour, in the specified timezone
      "#{time_of_day.min} #{time_of_day.hour} 1 1,7 * #{timezone}"
    when "yearly"
      # run on the 1st of Jan at the specified minute and hour, in the specified timezone
      "#{time_of_day.min} #{time_of_day.hour} 1 1 * #{timezone}"
    end
  end

  def day_of_week_to_cron(day_name)
    return nil unless day_name

    Date::DAYNAMES.map(&:downcase).index(day_name.downcase)
  end

  def transform_config_param(uc_details, param_name, default_value = nil)
    group_name = uc_details["multi-ecosystem-group"]
    if group_name
      group_value = validated_config_file.dig("multi-ecosystem-groups", group_name, param_name)
      return group_value unless group_value.nil?
    end
    uc_details.fetch(param_name, default_value)
  end

  def transform_nested_config_param(uc_details, *keys)
    group_name = uc_details["multi-ecosystem-group"]
    if group_name
      group_value = validated_config_file.dig("multi-ecosystem-groups", group_name, *keys)
      return group_value unless group_value.nil?
    end
    uc_details.dig(*keys)
  end

  def transform_assignees(uc_details)
    assignees = uc_details.fetch("assignees", [])

    if (group_name = uc_details["multi-ecosystem-group"])
      group = validated_config_file.dig("multi-ecosystem-groups", group_name) || {}
      assignees.concat(group["assignees"]) if group["assignees"]
    end

    assignees.presence
  end

  def beta_ecosystem_setting
    { "enable-beta-ecosystems" => enable_beta_ecosystems? }.compact
  end

  def transform_package_manager(uc_details)
    PACKAGE_MANAGER_LOOKUP.fetch(uc_details.fetch("package-ecosystem"))
  end

  def transform_lockfile_only(uc_details)
    version_req = uc_details.fetch("versioning-strategy", nil)
    version_req == "lockfile-only"
  end

  def transform_requirements_update_strategy(uc_details)
    package_manager = transform_package_manager(uc_details)
    version_req = uc_details.fetch("versioning-strategy", nil)
    allowed_strategies = UpdateConfig::UPDATE_STRATEGIES.
                         fetch(package_manager, [])
    update_strategy = REQUIREMENT_UPDATE_STRATEGY_LOOKUP.fetch(version_req, nil)
    update_strategy if allowed_strategies.include?(update_strategy)
  end

  def transform_allowed_updates(uc_details)
    value = uc_details.fetch("allow", [])

    if value.empty?
      [
        { "dependency_type" => "direct", "update_type" => "all" },
      ]
    else
      value.map do |au|
        {
          "dependency_name" => au["dependency-name"],
          "dependency_type" => au["dependency-type"],
          "update_types" => au["update-types"],
        }.compact
      end
    end
  end

  def transform_ignore_conditions(uc_details)
    ignore_conditions = flattened_ignore_conditions(uc_details)
    return unless ignore_conditions

    ignore_conditions.map do |ic|
      next unless ic["dependency-name"]

      hash = {
        "dependency_name" => ic["dependency-name"],
        "update_types" => ic["update-types"],
        "version_requirement" => ic["versions"],
      }

      hash["version_requirement"] = ">= 0" if hash["version_requirement"].blank? && hash["update_types"].blank?

      hash
    end.compact
  end

  def flattened_ignore_conditions(uc_details)
    ignore_conditions = uc_details["ignore"]
    return unless ignore_conditions

    ignore_conditions.each_with_object([]) do |ic, memo|
      versions = Array(ic["versions"])

      versions.each do |version|
        memo.push("dependency-name" => ic["dependency-name"], "versions" => version)
      end

      if ic["update-types"].present?
        memo.push("dependency-name" => ic["dependency-name"], "update-types" => ic["update-types"])
      end

      if versions.none? && ic["update-types"].blank?
        memo.push("dependency-name" => ic["dependency-name"], "versions" => nil)
      end

      memo
    end
  end

  def transform_commit_message_include_scope(uc_details)
    commit_message_include = transform_nested_config_param(uc_details, "commit-message", "include")
    return unless commit_message_include

    commit_message_include == "scope"
  end

  def clean_directory(directory)
    return unless directory

    Directories.new(directory).first
  end

  def clean_directories(directories)
    return unless directories

    Directories.new(directories).to_a
  end

  def transform_registry_details(reg_details)
    reg_details.clone.tap { |r| r["type"] = transform_registry_type(reg_details) }
  end

  def transform_registry_type(reg_details)
    REGISTRY_TYPE_LOOKUP.fetch(reg_details.fetch("type"))
  end

  def transform_cooldown(uc_details)
    return nil unless uc_details["cooldown"].is_a?(Hash)

    cooldown = uc_details["cooldown"]

    {
      "default-days" => cooldown.fetch("default-days", 0).to_i,
      "semver-major-days" => cooldown.fetch("semver-major-days", 0).to_i,
      "semver-minor-days" => cooldown.fetch("semver-minor-days", 0).to_i,
      "semver-patch-days" => cooldown.fetch("semver-patch-days", 0).to_i,
      "include" => cooldown["include"] || [],
      "exclude" => cooldown["exclude"] || [],
    }
  end

  def flatten_config_errors(config_errors, root)
    config_errors.flat_map do |config_error|
      index = config_error[:index]
      config_error[:errors].map do |schema_error|
        schema_error[:message] =
          schema_error[:message].
          sub(/^The property '#/, "The property '#/#{root}/#{index}")
        schema_error[:fragment] =
          schema_error[:fragment].
          sub(/^#/, "#/#{root}/#{index}")
        schema_error
      end
    end
  end

  def sanitize_errors(errors)
    errors.map do |error|
      err = error.dup
      err[:message] = sanitize_schema_error(error[:message])
      err[:message] = mask_timezone_error(err[:message]) if %r{schedule/timezone\Z}.match?(err[:fragment])
      err
    end
  end

  def sanitize_schema_error(error_message)
    # Removing useless hashed reference to schema:
    # e.g. "... in schema 18a1ffbb-4681-5b00-bd15-2c76aee4b28f"
    error_message.sub(/ in schema [-a-zA-Z0-9]+#?$/, "")
  end

  # Printing out the entire TZ database in this message risks overflowing
  # the character limit on some github/github endpoints, so we mask it
  # with a custom error
  def mask_timezone_error(error_message)
    error_message.sub(%r{did not match one of the following values: Africa/Abidjan, .+ Zulu\Z},
                      "is not a valid timezone.")
  end

  def requirement_class(package_manager)
    Dependabot::Utils.requirement_class_for_package_manager(package_manager)
  end

  def schema
    @schema ||= JSON.parse(Rails.root.join("config/config_file_json_schema.json").read)
  end

  def beta_ecosystem?(package_manager)
    Ecosystems.beta?(package_manager)
  end

  def released_or_enabled_beta_ecosystem?(package_manager)
    !beta_ecosystem?(package_manager) || (beta_ecosystem?(package_manager) && enable_beta_ecosystems?)
  end
end
# rubocop:enable Metrics/ClassLength
