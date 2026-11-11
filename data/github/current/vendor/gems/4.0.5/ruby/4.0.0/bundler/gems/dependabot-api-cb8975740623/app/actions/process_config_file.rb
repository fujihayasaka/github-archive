# frozen_string_literal: true

require "github_helpers"

# Retrieves the Dependabot congiguration file via the GitHub API for the given repository id
#
# Preconditions:
#   - The repository associated with the repo_github_id must exist in our database
#
# rubocop:disable Metrics/ClassLength
class ProcessConfigFile
  class ResetConfiguration
    attr_reader :repo

    def initialize(repo:)
      @repo = repo
    end

    def run
      disable_config_file_update_configs
      delete_registries
      clear_config_file_path
    end

    private

    # TODO: Avoid deactivating Security Update configs?
    #
    # The UpdateConfig used for Security Updates is not managed by the file but
    # will be deactivated by this call. We will re-create it when the next security
    # update job is received so the impact is low, but it creates unnessary churn.
    def disable_config_file_update_configs
      repo.update_configs.active.each do |config|
        Statesman::Machine.retry_conflicts { config.transition_to(:deleted) }
      end
    end

    def delete_registries
      repo.registries.destroy_all
    end

    def clear_config_file_path
      repo.update!(config_file_path: nil)
    end
  end

  def initialize(account:, repo_name:, repo_github_id:, quiet: false, event_source: "unknown")
    @account = account
    @repo_name = repo_name
    @repo_github_id = repo_github_id
    @quiet = quiet
    @event_source = event_source
  end

  # TODO: Record the sha when processing a file and early return if the sha has not changed
  #       since the last run
  def run
    return unless account.active?

    repo = Repo.find_by!(github_id: repo_github_id)
    handle_transfer(repo, account) if repo.account != account

    return unless config_file_enabled?(repo)

    config_file = fetch_config_for(repo)

    MetricsClient.increment("process_config_file.run", tags: {
                              config_file_present: config_file.present?,
                              event_source: event_source,
                            })

    update_repository_from_config_file(repo, config_file)
  rescue *SynchronizeRepoState::HANDLED_ERRORS
    SynchronizeRepoState.new(
      repo: repo,
      event_source: "action.process_config_file",
    ).run

    log_info(repo: repo, msg: "synchronizing repo state.")
  end

  private

  attr_reader :account, :repo_name, :repo_github_id, :event_source

  def config_file_enabled?(repo)
    return true if repo.using_config_file?

    settings = Dependabot::Application.dependabot_repository_settings_client.get_repository_settings(repo)
    settings.dependabot_config_file_enabled
  end

  # rubocop:disable Metrics/MethodLength
  def update_repository_from_config_file(repo, config_file)
    if config_file
      repo.event_stream.record_event(Activity::RepoEvents::CONFIGURATION_UPDATED,
                                     tags: { source: "process-config-file" })
      parsed_config_file = ParseConfigFile.new(
        config_file: config_file,
        repo: repo
      )
      update_registries_from_file(repo, parsed_config_file.registries)
      updates = parsed_config_file.updates.compact

      multi_ecosystem_configs = find_or_create_multi_ecosystem_configs(repo, parsed_config_file.multi_ecosystem_names)
      if multi_ecosystem_configs.any?
        ignore_multi_ecosystem_updates_in_regular_updates(parsed_config_file, updates)
        updates += multi_ecosystem_updates(parsed_config_file, multi_ecosystem_configs)
      end
      update_config_from_file(repo, updates)
      set_config_file_path(repo, config_file)

      log_info(repo: repo, msg: "updated config from file.")
    elsif repo.using_config_file?
      repo.event_stream.record_event(Activity::RepoEvents::CONFIGURATION_DELETED,
                                     tags: { source: "process-config-file" })
      ResetConfiguration.new(repo: repo).run
      log_info(repo: repo, msg: "cleared config file.")
    else
      log_info(repo: repo, msg: "nothing changed.")
    end

    delete_config_file_errors(repo)

    nil
  rescue ParseConfigFile::Unparseable, ParseConfigFile::Invalid => e
    handle_config_file_error(repo, config_file, e)
    log_info(repo: repo, msg: "config file error: #{e.message}")
  end

  # rubocop:enable Metrics/MethodLength
  def multi_ecosystem_updates?(parsed_config_file)
    parsed_config_file.multi_ecosystem_updates.present?
  end

  def multi_ecosystem_updates(parsed_config_file, multi_ecosystem_configs)
    return [] unless multi_ecosystem_updates?(parsed_config_file)

    parsed_multi_ecosystem_updates = parsed_config_file.multi_ecosystem_updates
    parsed_multi_ecosystem_updates.map do |multi_ecosystem_update|
      name = multi_ecosystem_update["multi_ecosystem_config_name"]
      multi_ecosystem_config = multi_ecosystem_configs.find { |config| config.name == name }
      multi_ecosystem_update.merge("multi_ecosystem_config_id" => multi_ecosystem_config.id)
    end.flatten
  end

  def ignore_multi_ecosystem_updates_in_regular_updates(parsed_config_file, updates)
    multi_update_exclusions = parsed_config_file.multi_ecosystem_exclusions

    updates.each do |update|
      ignore_conditions = update["ignore-conditions"] || []

      directories = [update["directory"]] || update["directories"]
      directories.each do |directory|
        next unless multi_update_exclusions[update["package-manager"]]&.key?(directory)

        ignore_conditions += multi_update_exclusions[update["package-manager"]][directory]
      end
      update["ignore-conditions"] = ignore_conditions.uniq
    end
  end

  def find_or_create_multi_ecosystem_configs(repo, multi_ecosystem_names)
    return [] if multi_ecosystem_names.blank?

    multi_ecosystem_names.map do |name|
      existing_multi_ecosystem_config = repo.multi_ecosystem_configs.find_by(name:)
      existing_multi_ecosystem_config || MultiEcosystemConfig.create!(name:)
    end
  end

  def handle_transfer(repo, account)
    repo.update!(account: account)

    MetricsClient.increment("action.process_config_file.handle_repo_transfer")
  end

  def update_config_from_file(repo, update_configs)
    create_or_update_update_configs(repo, update_configs)
    delete_removed_update_configs(repo, update_configs)
  end

  def update_registries_from_file(repo, registries)
    create_or_update_registries(repo, registries) unless registries.nil?
    delete_removed_registries(repo, registries)
  end

  def set_config_file_path(repo, config_file)
    enqueue_resync_of_repo_default_labels(repo) if repo.config_file_path.nil?

    repo.update!(config_file_path: config_file.path)
  end

  def create_or_update_update_configs(repo, update_configs)
    enqueue_scheduled_update_id = SecureRandom.uuid
    update_configs.each do |uc_details|
      update_config = existing_update_config(uc_details, repo)
      update_config ||= uniquely_similar_update_config(uc_details, repo, update_configs)
      update_config ||= resurrectable_matching_update_config(uc_details, repo)

      resync_repo = !update_config
      update_config ||= create_update_config(uc_details, repo)

      update_update_config(update_config, uc_details)
      update_ignore_conditions(update_config, uc_details)
      update_dependency_groups(update_config, uc_details)
      update_cooldown(update_config, uc_details)
      update_multi_ecosystem_dependency_groups(update_config, uc_details)

      enqueue_resync_of_repo_default_labels(repo) if resync_repo

      trigger_update_job(update_config, enqueue_scheduled_update_id)
    rescue ActiveRecord::RecordInvalid => e
      raise unless e.message.include?("Directory has already been taken")

      handle_update_config_uniqueness_error(uc_details, repo, update_config, enqueue_scheduled_update_id)

      # We previously would get in this situation when a duplicate config was
      # created as `pending` and they would then transition to `active` or
      # `rate_limited`. We now prevent this scenario in the state transition,
      # so when this _does_ happen we want to know about it.
      raise
    end
  end

  def delete_removed_update_configs(repo, parsed_config_file)
    current_update_configs =
      parsed_config_file.map do |uc_details|
        uc = existing_update_config(uc_details, repo)

        # We should have created the update config if it wasn't already present
        # by the time this method is called, so should be able to find it!
        unless uc
          log_info(repo: repo, msg: "unexpected error: no current update config")
          raise "Couldn't find a current update config"
        end

        uc
      end

    outdated_update_configs =
      UpdateConfig.active.
      where(repo_id: repo.id).
      where.not(id: current_update_configs.map(&:id))
    return unless outdated_update_configs.any?

    outdated_update_configs.each do |uc|
      Statesman::Machine.retry_conflicts { uc.transition_to(:deleted) }
    end

    # The removal of an update config means the default labels for other configs
    # might change (we might not want to include the language tag anymore)
    enqueue_resync_of_repo_default_labels(repo)
  end

  def handle_config_file_error(repo, config_file, error)
    delete_config_file_errors(repo)
    create_config_file_error(repo, error)
    set_config_file_path(repo, config_file)
  end

  def delete_config_file_errors(repo)
    ConfigFileError.where(repo_id: repo.id).delete_all
  end

  def create_config_file_error(repo, error)
    ConfigFileError.create!(
      repo: repo,
      error_details: error_hash(error).fetch("error-detail"),
      error_type: error_hash(error).fetch("error-type"),
    )
  end

  def fetch_config_for(repo)
    FetchConfigFile.new(
      account: account,
      repo_name: repo.name,
      repo_github_id: repo.github_id,
    ).run
  end

  def existing_update_config(update_config_details, repo)
    update_config_attributes = {
      repo_id: repo.id,
      package_manager: update_config_details["package-manager"],
      directory: update_config_details["directory"],
      target_branch: update_config_details["target-branch"]&.strip,
      multi_ecosystem_config_id: update_config_details["multi_ecosystem_config_id"],
    }

    return UpdateConfig.active.find_by(update_config_attributes) if update_config_details["directories"].blank?

    update_configs = UpdateConfig.active.where(update_config_attributes.merge(directory: nil))
    configured_directories = Directories.new(update_config_details["directories"])
    update_configs.find { |uc| Directories.new(uc.directories) == configured_directories }
  end

  def uniquely_similar_update_config(uc_details, repo, parsed_config_file)
    similar_uc_details = parsed_config_file.any? do |other_uc|
      next false if other_uc == uc_details
      next false if other_uc["package-manager"] != uc_details["package-manager"]

      other_uc["directory"] == uc_details["directory"]
    end

    return if similar_uc_details

    update_configs_for_directory = UpdateConfig.active.where(
      repo_id: repo.id,
      package_manager: uc_details["package-manager"],
      directory: uc_details["directory"],
      multi_ecosystem_config_id: uc_details["multi_ecosystem_config_id"],
    )
    return unless update_configs_for_directory.count == 1

    update_configs_for_directory.first
  end

  # If we've deleted an update config, but it's still in the config file, we
  # want to resurrect it. This is to prevent us from losing history re: ignore
  # conditions.
  #
  # TODO: Find resurrectable multi-directory configs
  #
  # This should only be used if no active update config exists
  def resurrectable_matching_update_config(uc_details, repo)
    update_config = UpdateConfig.
                    deleted.
                    order(id: :desc).
                    find_by(
                      repo: repo,
                      package_manager: uc_details["package-manager"],
                      directory: uc_details["directory"],
                      target_branch: uc_details["target-branch"]&.strip,
                      multi_ecosystem_config_id: uc_details["multi_ecosystem_config_id"],
                    )
    if update_config
      log_info(repo: repo, msg: "resurrecting update config #{update_config.id}")
      update_config.transition_to(:rate_limited)
    end
    update_config
  end

  def create_update_config(uc_details, repo)
    FindOrCreateUpdateConfig.new(
      repo: repo,
      update_config_details: uc_details,
    ).run
  end

  def update_update_config(update_config, uc_details)
    UpdateUpdateConfig.new(
      update_config: update_config,
      update_config_details: uc_details,
    ).run
  end

  def update_ignore_conditions(update_config, uc_details)
    update_config.ignore_conditions.from_config_file.each(&:destroy!)
    requested_ignore_conditions = uc_details.fetch("ignore-conditions")
    return if requested_ignore_conditions.nil?

    create_ignore_conditions_for_version_requirements(update_config, requested_ignore_conditions)
    create_ignore_conditions_for_update_types(update_config, requested_ignore_conditions)

    close_ignored_prs(update_config)
  end

  def update_dependency_groups(update_config, uc_details)
    return if uc_details["multi_ecosystem_config_id"].present?

    existing_dependency_groups = update_config.dependency_groups
    requested_dependency_groups = uc_details.fetch("groups")

    if requested_dependency_groups.blank?
      clear_all_dependency_groups(update_config)
      return
    end

    # delete existing dependency groups that are no longer requested
    existing_dependency_groups.each do |existing_dependency_group|
      next if requested_dependency_groups.key?(existing_dependency_group.name)

      existing_dependency_group.update!(deleted_at: Time.now.utc)
    end

    requested_dependency_groups.each_with_index do |requested_group_hash, sort_order|
      requested_group_name, requested_group_properties = *requested_group_hash
      if existing_dependency_groups.find_by(name: requested_group_name).nil?
        create_new_dependency_group(update_config, requested_group_name, requested_group_properties, sort_order)
      else
        update_existing_dependency_group(update_config, requested_group_name, requested_group_properties, sort_order)
      end
    end
  end

  def update_multi_ecosystem_dependency_groups(update_config, uc_details)
    return if uc_details["multi_ecosystem_config_id"].blank?

    update_config.update!(multi_ecosystem_config_id: uc_details["multi_ecosystem_config_id"])

    name = uc_details["multi_ecosystem_config_name"]
    rules = build_multi_ecosystem_group_rules(uc_details)
    group_hash = { applies_to: nil, rules:, sort_order: 0 }.compact

    update_config.dependency_groups.find_or_create_by(name:).update!(group_hash)
  end

  def build_multi_ecosystem_group_rules(uc_details)
    rules = { patterns: uc_details["multi_ecosystem_config_patterns"] }
    if uc_details["multi_ecosystem_config_update_types"]
      rules["update-types"] =
        uc_details["multi_ecosystem_config_update_types"]
    end
    if uc_details["multi_ecosystem_config_dependency_type"]
      rules["dependency-type"] =
        uc_details["multi_ecosystem_config_dependency_type"]
    end
    if uc_details["multi_ecosystem_config_exclude_patterns"]
      rules["exclude-patterns"] =
        uc_details["multi_ecosystem_config_exclude_patterns"]
    end
    rules
  end

  def create_new_dependency_group(update_config, requested_group_name, requested_group_properties, sort_order)
    group_hash = {
      name: requested_group_name,
      applies_to: requested_group_properties.fetch("applies-to", nil),
      rules: requested_group_properties.except("applies-to"),
      sort_order: sort_order,
    }.compact

    update_config.dependency_groups.create!(group_hash)
  end

  def update_existing_dependency_group(update_config, requested_group_name, requested_group_properties, sort_order)
    group_hash = {
      # The name doesn't change when updating an existing dependency group
      applies_to: requested_group_properties.fetch("applies-to", nil),
      rules: requested_group_properties.except("applies-to"),
      sort_order: sort_order,
    }.compact

    update_config.dependency_groups.find_by(name: requested_group_name).update!(group_hash)
  end

  def clear_all_dependency_groups(update_config)
    dependency_group_ids = update_config.dependency_groups.pluck(:id)
    update_config.dependency_groups.update_all(deleted_at: Time.now.utc)
    dependency_group_ids.each { |id| CleanupDependencyGroupPullRequestsJob.perform_later(id) }
  end

  def create_ignore_conditions_for_version_requirements(update_config, ignore_conditions)
    version_requirement_conditions = ignore_conditions.select { |ic| ic["version_requirement"].present? }

    version_requirement_conditions.each do |ic|
      create_ignore_condition(update_config,
                              name: ic.fetch("dependency_name"),
                              version: ic.fetch("version_requirement"))
    end
  end

  def create_ignore_conditions_for_update_types(update_config, ignore_conditions)
    update_types_ignore_conditions = ignore_conditions.select { |ic| ic["update_types"].present? }

    update_types_ignore_conditions.each do |ic|
      create_ignore_condition(update_config,
                              name: ic.fetch("dependency_name"),
                              version: nil,
                              update_types: ic.fetch("update_types"))
    end
  end

  def create_ignore_condition(update_config, name:, version:, update_types: nil)
    if (existing = update_config.ignore_conditions.find_by(dependency_name: name, version_requirement: version))
      new_update_types = update_types || []
      existing_update_types = existing.update_types || []
      merged_update_types = Set.new(existing_update_types + new_update_types)
      existing.update!(update_types: merged_update_types, from_config_file: true)
      return
    end

    update_config.ignore_conditions.create!(
      dependency_name: name,
      version_requirement: version,
      update_types: update_types,
      from_config_file: true,
    )
  end

  def handle_update_config_uniqueness_error(uc_details, repo, update_config, enqueue_scheduled_update_id)
    delete_duplicate_update_config(uc_details, repo)

    remaining_update_config = existing_update_config(uc_details, repo)
    return unless remaining_update_config

    update_update_config(remaining_update_config, uc_details)
    update_ignore_conditions(remaining_update_config, uc_details)

    # If the remaining update config is new, it's likely the race happened
    # during creation, and both threads will have experienced it. If it was
    # created by this thread, perform the normal post-creation steps.
    return unless update_config && remaining_update_config.id == update_config.id
    return unless remaining_update_config.created_at > 10.seconds.ago

    enqueue_resync_of_repo_default_labels(repo)
    trigger_update_job(remaining_update_config, enqueue_scheduled_update_id)
  end

  def delete_duplicate_update_config(uc_details, repo)
    update_configs =
      UpdateConfig.active.
      where(
        repo_id: repo.id,
        package_manager: uc_details["package-manager"],
        directory: uc_details["directory"],
        target_branch: uc_details["target-branch"].presence&.strip,
        multi_ecosystem_config_id: uc_details["multi_ecosystem_config_id"],
      ).order(:id).to_a

    return unless update_configs.count > 1

    update_configs.drop(1).each do |uc|
      Statesman::Machine.retry_conflicts { uc.transition_to(:deleted) }
    end
  end

  def create_or_update_registries(repo, registries)
    existing = repo.registries.pluck(:name)
    to_create, to_update = registries.partition { |name, _| existing.exclude?(name) }

    to_create.each do |name, config|
      Registry.create!(
        source: repo,
        name: name,
        registry_type: config["type"],
        credentials: config.except("type").to_json
      )
    end

    to_update.each do |name, config|
      repo.registries.find_by(name: name)&.update!(
        registry_type: config["type"],
        credentials: config.except("type").to_json
      )
    end
  rescue ActiveRecord::RecordInvalid => e
    messages = e.record.errors.full_messages.map { |message| { message: message } }
    raise ParseConfigFile::Invalid, messages
  end

  def delete_removed_registries(repo, registries)
    if registries
      repo.registries.where.not(name: registries.keys).destroy_all
    else
      repo.registries.destroy_all
    end
  end

  def update_cooldown(update_config, uc_details)
    cooldown_details = uc_details.fetch("cooldown", nil)

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

  def close_ignored_prs(update_config)
    update_config.pull_requests.open.each do |pr|
      security_updates_only = pr.update_job.security_updates_only?
      ignored_pull_request = pr.updated_dependencies.none? do |dep|
        update_config.ignored_update?(dep, security_updates_only: security_updates_only)
      end
      next if ignored_pull_request
      next if pr.head_commit_sha != pr.dependabot_commit_sha

      ClosePullRequestJob.perform_later(
        pull_request: pr,
        reason: "dependency_ignored",
      )
    end
  end

  def enqueue_resync_of_repo_default_labels(repo)
    return if @resync_enqueued

    UpdateDefaultLabelsJob.perform_later(repo: repo)
    @resync_enqueued = true
  end

  def trigger_update_job(update_config, enqueue_scheduled_update_id)
    return if @quiet
    return unless update_config.version_updates_enabled?

    job = UpdateJob.create!(
      update_config_id: update_config.id,
      trigger_type: :config_file_changed,
      enqueue_scheduled_update_id: enqueue_scheduled_update_id,
    )
    PrioritizedJobs::StartUpdateJob.perform_later(job)
    # TODO: Remove once we can refresh PRs from the 'main' scheduled job, See:
    #   https://github.com/github/dependabot-updates/pull/4213
    RefreshOpenGroupPullRequestsJob.perform_later(update_config: update_config)
  end

  def error_hash(error)
    case error
    when ParseConfigFile::Unparseable
      {
        "error-type" => "unparseable_config_file",
        "error-detail" => { "message" => error.message },
      }
    when ParseConfigFile::Invalid
      {
        "error-type" => "invalid_config_file",
        "error-detail" => { "message" => error.message },
      }
    else raise "Unexpected error type: #{error.class}"
    end
  end

  def log_info(repo:, msg:)
    Dependabot::Logger.info(
      msg: msg,
      "code.namespace": "ProcessConfigFile",
      "gh.owner.id": account.github_id,
      "gh.repo.id": repo.github_id,
    )
  end
end
# rubocop:enable Metrics/ClassLength
