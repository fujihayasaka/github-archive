# frozen_string_literal: true

class FindOrCreateUpdateConfig
  attr_reader :repo, :update_config_details, :user

  def initialize(repo:, update_config_details:, user: nil)
    @repo = repo
    @user = user
    @update_config_details = update_config_details
  end

  def run
    return existing_update_config if existing_update_config

    update_config = create_update_config
    create_update_config_registries(update_config)

    create_update_config_cooldown(update_config)

    transition_update_config_state(update_config)
    update_config
    # Two previously :pending update configs are being transitioned in parallel,
    # so we ensure that the one that has already transitioned is returned and
    # the conflicting record is cleaned up.
  rescue Statesman::GuardFailedError
    raise unless existing_update_config

    update_config.destroy! # Ensures callbacks and dependent associations are properly handled
    existing_update_config
  end

  private

  def existing_update_config
    find_by_params = {
      repo_id: repo.id,
      package_manager: update_config_details["package-manager"],
      target_branch: update_config_details["target-branch"].presence&.strip,
      directory: nil,
      directories: nil,
      multi_ecosystem_config_id: update_config_details["multi_ecosystem_config_id"],
    }

    if cleaned_directories.present?
      find_by_params[:directories] = cleaned_directories
    else
      find_by_params[:directory] = cleaned_directory
    end

    UpdateConfig.active.find_by(**find_by_params)
  end

  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
  def create_update_config # rubocop:disable Metrics/PerceivedComplexity
    params = {
      repo: repo,
      package_manager: update_config_details["package-manager"],
      enable_beta_ecosystems: update_config_details["enable-beta-ecosystems"] || false,
      update_schedule: update_config_details["update-schedule"],
      target_branch: update_config_details["target-branch"].presence&.strip,
      lockfile_only: update_config_details["lockfile-only"] || false,
      requirements_update_strategy: update_strategy,
      default_labels: ["dependencies"],
      allowed_updates: allowed_updates,
      commit_message_prefix: update_config_details["commit-message-prefix"],
      commit_message_prefix_development:
        update_config_details["commit-message-prefix-development"],
      commit_message_include_scope:
        update_config_details["commit-message-include-scope"],
      update_schedule_time_of_day: update_schedule_time_of_day,
      update_schedule_day_of_week: update_schedule_day_of_week,
      update_schedule_cron_expression: update_schedule_cron_expression,
      update_schedule_timezone: update_schedule_timezone,
      pull_request_branch_name_separator: pull_request_branch_name_separator,
      open_pull_requests_limit: open_pull_requests_limit,
      rebase_strategy: rebase_strategy,
      vendor: update_config_details["vendor"] || false,
      all_registries: update_config_details["registries"] == UpdateConfig::REGISTRY_WILDCARD,
      multi_ecosystem_config_id: update_config_details["multi_ecosystem_config_id"],
      exclude_paths: update_config_details["exclude-paths"] || [],
    }

    update_config = add_directory_or_directories(params)
    UpdateConfig.create!(**update_config)
  rescue ActiveRecord::RecordInvalid => e
    raise unless e.message.include?("Directory has already been taken")
    raise unless existing_update_config

    existing_update_config
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

  def add_directory_or_directories(update_config_params)
    if cleaned_directories.present?
      update_config_params[:directories] = cleaned_directories
    else
      update_config_params[:directory] = cleaned_directory
    end

    update_config_params
  end

  def create_update_config_cooldown(update_config)
    cooldown_details = update_config_details["cooldown"]

    if cooldown_details.blank?
      update_config.update_config_cooldown&.destroy!
      return
    end

    cooldown = update_config.update_config_cooldown || update_config.build_update_config_cooldown

    cooldown.update!(
      default_days: cooldown_details.fetch("default-days", 0),
      semver_major_days: cooldown_details.fetch("semver-major-days", 0),
      semver_minor_days: cooldown_details.fetch("semver-minor-days", 0),
      semver_patch_days: cooldown_details.fetch("semver-patch-days", 0),
      include: Array(cooldown_details.fetch("include", [])),
      exclude: Array(cooldown_details.fetch("exclude", [])),
    )
  end

  def create_update_config_registries(update_config)
    return if update_config.all_registries?
    return if update_config_details["registries"].blank?

    names = update_config_details["registries"]
    UpdateConfigRegistry.insert_all(
      names.map { |name| { update_config_id: update_config.id, registry_name: name, created_at: Time.now.utc } },
      returning: nil,
    )
  end

  def transition_update_config_state(update_config)
    Statesman::Machine.retry_conflicts do
      return unless update_config.in_state?(:pending)

      update_config.transition_to!(
        :rate_limited,
        initiator_github_id: user&.id,
      )
    end
  end

  def allowed_updates
    update_config_details["allowed-updates"] ||
      [{ dependency_type: "direct", update_type: "all" }]
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

  def update_strategy
    if update_config_details["requirements-update-strategy"] == "auto" then nil
    else
      update_config_details["requirements-update-strategy"]
    end
  end

  def update_schedule_time_of_day
    update_config_details["update-schedule-time-of-day"] || repo.default_update_schedule_time_of_day
  end

  def update_schedule_day_of_week
    update_config_details["update-schedule-day-of-week"] ||
      UpdateConfig::DEFAULT_UPDATE_SCHEDULE_DAY_OF_WEEK
  end

  def update_schedule_cron_expression
    update_config_details["update-schedule-cron-expression"] ||
      UpdateConfig::DEFAULT_UPDATE_SCHEDULE_CRON_EXPRESSION
  end

  def update_schedule_timezone
    update_config_details["update-schedule-timezone"] ||
      UpdateConfig::DEFAULT_UPDATE_SCHEDULE_TIMEZONE
  end

  def pull_request_branch_name_separator
    update_config_details["pull-request-branch-name-separator"] ||
      UpdateConfig::DEFAULT_PULL_REQUEST_BRANCH_NAME_SEPARATOR
  end

  def open_pull_requests_limit
    update_config_details["open-pull-requests-limit"] ||
      UpdateConfig::DEFAULT_OPEN_PULL_REQUESTS_LIMIT
  end

  def rebase_strategy
    update_config_details["rebase-strategy"] ||
      UpdateConfig::DEFAULT_REBASE_STRATEGY
  end

  def account
    repo.account
  end
end
