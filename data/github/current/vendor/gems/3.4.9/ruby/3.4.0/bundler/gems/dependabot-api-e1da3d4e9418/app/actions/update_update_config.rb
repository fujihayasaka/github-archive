# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength
class UpdateUpdateConfig
  def initialize(update_config:, update_config_details:)
    @update_config = update_config
    @update_config_details = update_config_details
  end

  def run # rubocop:disable Metrics/MethodLength
    UpdateConfig.transaction do
      update_schedule
      update_directory
      update_directories
      update_target_branch
      update_requirements_update_strategy
      update_filters
      update_default_pr_annotations
      update_commit_message_options
      update_time_of_day_schedule
      update_timezone_schedule
      update_day_of_week_schedule
      update_cron_expression_schedule
      update_pull_request_branch_name_separator
      update_open_pull_requests_limit
      update_rebase_strategy
      update_vendor
      update_enable_beta_ecosystems
      update_insecure_external_code_execution
      update_registries
      update_cooldown
      update_exclude_paths
    end
  end

  private

  attr_reader :update_config, :update_config_details

  def update_schedule
    return unless update_config_details.key?("update-schedule")

    update_config.update!(
      update_schedule: update_config_details["update-schedule"],
    )
  end

  def update_directory
    return unless update_config_details.key?("directory") && update_config_details["directory"].present?

    update_config.update!(directory: cleaned_directory)
  end

  def update_directories
    return unless update_config_details.key?("directories") && update_config_details["directories"].present?

    update_config.update!(directories: cleaned_directories)
  end

  def update_target_branch
    return unless update_config_details.key?("target-branch")

    update_config.update!(
      target_branch: update_config_details["target-branch"].presence&.strip,
    )
  end

  def update_requirements_update_strategy
    return unless update_config_details.key?("requirements-update-strategy")

    update_strategy =
      if update_config_details["requirements-update-strategy"] == "auto"
        nil
      else
        update_config_details["requirements-update-strategy"]
      end

    update_config.update!(requirements_update_strategy: update_strategy)
  end

  def update_filters
    update_lockfile_only
    update_allowed_updates
  end

  def update_lockfile_only
    return unless update_config_details.key?("lockfile-only")

    update_config.update!(lockfile_only: update_config_details["lockfile-only"])
  end

  def update_allowed_updates
    if update_config_details.key?("allowed-updates")
      update_config.update!(
        allowed_updates: update_config_details["allowed-updates"],
      )
      return
    end

    updated_settings = update_config.allowed_updates

    update_config.update!(allowed_updates: updated_settings)
  end

  def update_default_pr_annotations
    update_custom_labels
    update_default_assignees
    update_default_milestone
  end

  def update_custom_labels
    return unless update_config_details.key?("custom-labels")

    update_config.update!(
      custom_labels: update_config_details["custom-labels"]&.uniq,
    )
  end

  def update_default_assignees
    return unless update_config_details.key?("default-assignees")

    update_config.update!(
      default_assignees: update_config_details["default-assignees"]&.uniq,
    )
  end

  def update_default_milestone
    return unless update_config_details.key?("default-milestone")

    update_config.update!(
      default_milestone: update_config_details["default-milestone"],
    )
  end

  def update_commit_message_options
    if update_config_details.key?("commit-message-prefix")
      update_config.update!(
        commit_message_prefix: update_config_details["commit-message-prefix"],
      )
    end

    if update_config_details.key?("commit-message-prefix-development")
      update_config.update!(
        commit_message_prefix_development:
          update_config_details["commit-message-prefix-development"],
      )
    end

    return unless update_config_details.key?("commit-message-include-scope")

    update_config.update!(
      commit_message_include_scope:
        update_config_details["commit-message-include-scope"],
    )
  end

  def update_time_of_day_schedule
    update_schedule_time_of_day = update_config_details["update-schedule-time-of-day"]

    if update_schedule_time_of_day.nil?
      update_config.update!(
        update_schedule_time_of_day: update_config.repo.default_update_schedule_time_of_day,
      )
    else
      update_config.update!(
        update_schedule_time_of_day: update_schedule_time_of_day,
      )
    end
  end

  def update_day_of_week_schedule
    return unless update_config_details.key?("update-schedule-day-of-week")

    update_schedule_day_of_week =
      update_config_details["update-schedule-day-of-week"]

    if update_schedule_day_of_week.nil?
      update_config.update!(
        update_schedule_day_of_week:
          UpdateConfig::DEFAULT_UPDATE_SCHEDULE_DAY_OF_WEEK,
      )
    else
      update_config.update!(
        update_schedule_day_of_week: update_schedule_day_of_week,
      )
    end
  end

  def update_cron_expression_schedule
    return unless update_config_details.key?("update-schedule-cron-expression")

    update_schedule_cron_expression =
      update_config_details["update-schedule-cron-expression"]

    if update_schedule_cron_expression.nil?
      update_config.update!(
        update_schedule_cron_expression:
          UpdateConfig::DEFAULT_UPDATE_SCHEDULE_CRON_EXPRESSION,
      )
    else
      update_config.update!(
        update_schedule_cron_expression: update_schedule_cron_expression,
      )
    end
  end

  def update_exclude_paths
    return unless update_config_details.key?("exclude-paths")

    update_config.update!(exclude_paths: update_config_details["exclude-paths"])
  end

  def update_timezone_schedule
    return unless update_config_details.key?("update-schedule-timezone")

    update_schedule_timezone =
      update_config_details["update-schedule-timezone"]

    if update_schedule_timezone.nil?
      update_config.update!(
        update_schedule_timezone:
          UpdateConfig::DEFAULT_UPDATE_SCHEDULE_TIMEZONE,
      )
    else
      update_config.update!(
        update_schedule_timezone: update_schedule_timezone,
      )
    end
  end

  def update_pull_request_branch_name_separator
    return unless update_config_details.key?("pull-request-branch-name-separator")

    pull_request_branch_name_separator =
      update_config_details["pull-request-branch-name-separator"]

    if pull_request_branch_name_separator.nil?
      update_config.update!(
        pull_request_branch_name_separator:
          UpdateConfig::DEFAULT_PULL_REQUEST_BRANCH_NAME_SEPARATOR,
      )
    else
      update_config.update!(
        pull_request_branch_name_separator: pull_request_branch_name_separator,
      )
    end
  end

  def update_open_pull_requests_limit
    return unless update_config_details.key?("open-pull-requests-limit")

    open_pull_requests_limit = update_config_details["open-pull-requests-limit"]

    if open_pull_requests_limit.nil?
      update_config.update!(
        open_pull_requests_limit:
          UpdateConfig::DEFAULT_OPEN_PULL_REQUESTS_LIMIT,
      )
    else
      update_config.update!(
        open_pull_requests_limit: open_pull_requests_limit,
      )
    end
  end

  def update_rebase_strategy
    return unless update_config_details.key?("rebase-strategy")

    rebase_strategy = update_config_details["rebase-strategy"]

    if rebase_strategy.nil?
      update_config.update!(
        rebase_strategy: UpdateConfig::DEFAULT_REBASE_STRATEGY,
      )
    else
      update_config.update!(
        rebase_strategy: rebase_strategy,
      )
    end
  end

  def update_vendor
    return unless update_config_details.key?("vendor")

    vendor = update_config_details["vendor"]
    update_config.update!(vendor: vendor)
  end

  def update_enable_beta_ecosystems
    return unless update_config_details.key?("enable-beta-ecosystems")
    return if update_config.enable_beta_ecosystems == update_config_details["enable-beta-ecosystems"].present?

    update_config.update!(enable_beta_ecosystems: update_config_details["enable-beta-ecosystems"].present?)

    MetricsClient.increment("update_config.enable_beta_ecosystems",
                            tags: ["enabled:#{update_config.enable_beta_ecosystems}"])
  end

  def update_insecure_external_code_execution
    update_config.update!(insecure_external_code_execution: update_config_details["insecure-external-code-execution"])
  end

  def update_registries
    if update_config_details["registries"] == UpdateConfig::REGISTRY_WILDCARD
      update_config.update!(all_registries: true)
      update_config.update_config_registries.destroy_all
    else
      update_config.update!(all_registries: false)
      update_registry_names
    end
  end

  def update_registry_names
    uc_registries = update_config_details["registries"] || []
    existing = update_config.update_config_registries.pluck(:registry_name)
    to_create = uc_registries.select { |reg| existing.exclude?(reg) }
    unless to_create.empty?
      UpdateConfigRegistry.insert_all(
        to_create.map { |name| { update_config_id: update_config.id, registry_name: name, created_at: Time.now.utc } },
        returning: nil,
      )
    end

    to_delete = existing.select { |reg| uc_registries.exclude?(reg) }
    update_config.update_config_registries.where(registry_name: to_delete).destroy_all unless to_delete.empty?
  end

  def update_cooldown
    cooldown_details = update_config_details["cooldown"]

    if cooldown_details.nil?
      update_config.update_config_cooldown&.destroy! if update_config.update_config_cooldown.present?
      return
    end

    cooldown_record = update_config.update_config_cooldown || update_config.build_update_config_cooldown
    cooldown_record.update!(
      default_days: cooldown_details.fetch("default-days", 0),
      semver_major_days: cooldown_details.fetch("semver-major-days", 0),
      semver_minor_days: cooldown_details.fetch("semver-minor-days", 0),
      semver_patch_days: cooldown_details.fetch("semver-patch-days", 0),
      include: Array(cooldown_details.fetch("include", [])),
      exclude: Array(cooldown_details.fetch("exclude", []))
    )
  end

  def cleaned_directory
    Directories.new(update_config_details.fetch("directory")).first
  end

  # TODO: Currently directories are optional, so retuning nil if not present.
  # In future when we make directories mandatory, we should return an empty array
  def cleaned_directories
    return nil if update_config_details.fetch("directories", nil).blank?

    Directories.new(update_config_details.fetch("directories")).to_a
  end
end
# rubocop:enable Metrics/ClassLength
