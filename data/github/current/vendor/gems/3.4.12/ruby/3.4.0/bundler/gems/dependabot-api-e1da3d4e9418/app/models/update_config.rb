# frozen_string_literal: true

require "allowed_updates_validator"
require "dependabot/config/file"
require "dependabot/config/ignore_condition"
require "dependabot/config/update_config"
require "dependabot/dependency"
require "nullable_serializer"
require "wildcard_matcher"
require "dependabot/cronjob_validator"

# rubocop:disable Metrics/ClassLength
class UpdateConfig < ApplicationRecord
  T.unsafe(self).include Statesman::Adapters::ActiveRecordQueries[
    transition_class: UpdateConfigTransition,
    transition_name: :update_config_transition,
    initial_state: :pending
  ]

  self.ignored_columns += ["default_reviewers"]

  UPDATE_SCHEDULES = %w(never daily weekly monthly quarterly semiannually yearly cron).freeze
  UPDATE_STRATEGIES = {
    PackageManagers::NPM_AND_YARN => %w(widen_ranges bump_versions bump_versions_if_necessary lockfile_only),
    PackageManagers::COMPOSER => %w(widen_ranges bump_versions bump_versions_if_necessary lockfile_only),
    PackageManagers::BUNDLER => %w(bump_versions bump_versions_if_necessary lockfile_only),
    PackageManagers::PIP => %w(bump_versions bump_versions_if_necessary lockfile_only),
    PackageManagers::PUB => %w(widen_ranges bump_versions bump_versions_if_necessary),
    PackageManagers::CARGO => %w(lockfile_only),
    PackageManagers::HEX => %w(lockfile_only),
    PackageManagers::BUN => %w(widen_ranges bump_versions bump_versions_if_necessary lockfile_only),
  }.freeze
  PACKAGE_MANAGERS_WITH_LOCKFILES = {
    PackageManagers::BAZEL => %w(MODULE.bazel.lock),
    PackageManagers::BUNDLER => %w(Gemfile.lock gems.locked),
    PackageManagers::CARGO => %w(Cargo.lock),
    PackageManagers::COMPOSER => %w(composer.lock),
    PackageManagers::DEVCONTAINERS => %w(devcontainer-lock.json .devcontainer-lock.json),
    PackageManagers::HEX => %w(mix.lock),
    PackageManagers::NPM_AND_YARN => %w(package-lock.json yarn.lock pnpm-lock.yaml bun.lock bun.lockb),
    PackageManagers::PIP => %w(Pipfile.lock pyproject.lock poetry.lock),
    PackageManagers::PUB => %w(pubspec.lock),
    PackageManagers::SWIFT => %w(Package.resolved),
    PackageManagers::BUN => %w(bun.lock bun.lockb),
  }.freeze
  PACKAGE_MANAGERS_WITH_CODE_EXECUTION = [
    PackageManagers::BUNDLER,
    PackageManagers::HEX,
    PackageManagers::PIP,
    PackageManagers::SWIFT,
  ].freeze
  AWS_INSTANCE_SMALL = "t3.small"
  AWS_INSTANCE_MEDIUM = "t3.medium"
  AWS_INSTANCE_LARGE = "t3.large"
  AWS_INSTANCE_SIZES = [AWS_INSTANCE_SMALL, AWS_INSTANCE_MEDIUM, AWS_INSTANCE_LARGE].freeze
  DAYS = %w(
    monday tuesday wednesday thursday friday saturday sunday
  ).freeze
  REBASE_STRATEGIES = %w(auto disabled).freeze
  BRANCH_NAME_SEPARATORS = %w(- _ /).freeze
  DEFAULT_OPEN_PULL_REQUESTS_LIMIT = 5
  DEFAULT_REBASE_STRATEGY = "auto"
  DEFAULT_UPDATE_SCHEDULE_DAY_OF_WEEK = "monday"
  DEFAULT_UPDATE_SCHEDULE_CRON_EXPRESSION = "@daily"
  DEFAULT_UPDATE_SCHEDULE_TIMEZONE = "UTC"
  DEFAULT_PULL_REQUEST_BRANCH_NAME_SEPARATOR = "/"

  ALLOWED_UPDATE_TYPES = %w(direct production development).freeze
  ALLOWED_SUBDEPENDENCY_UPDATE_TYPES = ["all", "indirect", nil].freeze

  REGISTRY_WILDCARD = "*"

  belongs_to :repo
  belongs_to :multi_ecosystem_config, optional: true

  has_many :dependency_groups, -> { DependencyGroup.active.ordered }, inverse_of: :update_config
  has_many :ignore_conditions
  has_many :update_config_transitions
  has_many :update_jobs
  has_many :pull_requests
  has_many :pending_pull_requests,
           through: :update_jobs,
           inverse_of: :update_config
  has_many :update_config_registries
  has_many :multi_ecosystem_siblings, # rubocop:disable Rails/InverseOf
           -> { active.where.not(multi_ecosystem_config_id: nil) },
           class_name: "UpdateConfig",
           primary_key: :multi_ecosystem_config_id,
           foreign_key: :multi_ecosystem_config_id

  has_one :update_config_cooldown, dependent: :destroy
  has_one :account, through: :repo, inverse_of: :update_configs

  has_one :last_update_run,
          lambda {
            # This looks mad, but using `order` and `limit` would stop this
            # association from being used efficiently in eager loading (as
            # *all* the update runs would be eager-loaded, not just the most
            # recent one).
            #
            # If this becomes inefficient we can add a `most_recent` column to
            # the update_jobs table.
            where(pull_request_transition_id: nil).joins(
              "LEFT OUTER JOIN #{UpdateJob.table_name} AS tmp "\
              "ON tmp.update_config_id = #{UpdateJob.table_name}.update_config_id "\
              "AND tmp.pull_request_transition_id IS NULL "\
              "AND tmp.id > #{UpdateJob.table_name}.id",
            ).where(tmp: { id: nil })
          },
          class_name: "UpdateJob",
          inverse_of: :update_config

  belongs_to :last_scheduled_job,
             class_name: "UpdateJob",
             optional: true

  attribute :directory, StringFromBinary.new

  validates :package_manager, inclusion: { in: PackageManagers::ALL }
  validates :directory,
            length: { maximum: 1024 }
  validates :directory,
            if: proc { |uc| uc.active? },
            uniqueness: { conditions: -> { active },
                          case_sensitive: false,
                          scope: %i(repo_id package_manager target_branch multi_ecosystem_config_id),
                          allow_nil: true, }

  # Validate each directory path for length only if directories are provided
  validate :validate_directory_xor_directories
  validate :validate_directories, if: -> { directories.present? }
  validate :validate_unique_directories_within_record, if: -> { directories.present? }
  validate :validate_directories_are_sorted, if: -> { directories.present? }

  validates :update_schedule, inclusion: { in: UPDATE_SCHEDULES }
  validates :update_schedule_time_of_day, presence: true
  validates :update_schedule_day_of_week, inclusion: { in: DAYS }
  validates :update_schedule_timezone,
            inclusion: { in: TZInfo::Timezone.all_identifiers }

  validates :lockfile_only, inclusion: { in: [true, false] }
  validates :allowed_updates, presence: true, allowed_updates: true
  validates :commit_message_include_scope, inclusion: { in: [nil, true, false] }
  validates :commit_message_prefix, length: { maximum: 50 }
  validates :commit_message_prefix_development, length: { maximum: 50 }
  validates :pull_request_branch_name_separator,
            presence: true,
            inclusion: { in: BRANCH_NAME_SEPARATORS }
  validates :rebase_strategy, inclusion: { in: REBASE_STRATEGIES }
  validates :enable_beta_ecosystems, inclusion: { in: [true, false] }
  validate :update_strategy_is_valid

  before_validation :set_default_required_instance_size, on: :create
  after_update_commit :update_pr_base_branches, if: :target_branch_changed?

  scope :active,
        lambda {
          joins(:update_config_transitions).
            merge(UpdateConfigTransition.most_recent.active)
        }
  scope :deleted,
        lambda {
          joins(:update_config_transitions).
            merge(UpdateConfigTransition.most_recent.deleted)
        }
  scope :scheduled, -> { where.not(update_schedule: "never") }

  delegate :can_transition_to?, :transition_to!, :transition_to, :current_state,
           :last_transition, :in_state?, to: :state_machine
  delegate :using_config_file?, to: :repo

  serialize :allowed_updates, coder: JSON
  serialize :custom_labels, coder: NullableSerializer.new(Array)
  serialize :default_labels, coder: NullableSerializer.new(Array)
  serialize :default_assignees, coder: NullableSerializer.new(Array)
  serialize :monitored_files, coder: NullableSerializer.new(Array)
  serialize :directories, coder: NullableSerializer.new(Array)
  serialize :exclude_paths, coder: NullableSerializer.new(Array)

  after_create_commit :instrument

  # NOTE: This method is called from the repository push handler for all pushes
  # to all repositories. Expects updated_files_regex input from:
  # Dependabot::FileUpdaters.for_package_manager(pm).updated_files_regex
  def self.path_matches_updated_files_regex?(updated_files_regex, path)
    filename = File.basename(path)
    updated_files_regex.any? do |r|
      # Actions workflow files match the entire path, everything else matches
      # on the filename
      r.match?(path) || r.match?(filename)
    end
  end

  def active?
    in_state?(:active, :rate_limited)
  end

  def any_active_duplicates?
    params = {
      repo_id: repo_id,
      package_manager: package_manager,
      target_branch: target_branch,
      multi_ecosystem_config_id: multi_ecosystem_config_id,
    }

    if directories.present?
      params[:directories] = directories
    else
      params[:directory] = directory
    end

    UpdateConfig.where(**params).active.where.not(id: id).exists?
  end

  # If false, this UpdateConfig only applies to security updates
  def version_updates_enabled?
    open_pull_requests_limit != 0 && update_schedule != "never"
  end

  def update_subdependencies?
    allowed_updates.map(&:symbolize_keys).any? do |h|
      next false unless h.fetch(:update_type, "all") == "all"
      next false if h.key?(:dependency_name)

      ALLOWED_SUBDEPENDENCY_UPDATE_TYPES.include?(h[:dependency_type])
    end
  end

  # TODO: Allow vulnerable dependencies to bypass update type ignores
  def ignored_update?(updated_dependency, security_updates_only: false)
    matching_conditions = filter_matching_conditions(updated_dependency, security_updates_only: security_updates_only)
    matching_conditions.any? { |ic| ic.includes?(updated_dependency.version) }
  end

  def filter_matching_conditions(updated_dependency, security_updates_only:)
    config_ignore_conditions = ignore_conditions.map do |ic|
      Dependabot::Config::IgnoreCondition.new(
        dependency_name: ic.dependency_name,
        versions: [ic.version_requirement].compact,
        update_types: ic.update_types
      )
    end

    # NOTE: Build a dependency and ignore condition with the previous_version
    # that will ignore the updated dependency version
    previous_dependency = build_previous_dependency(updated_dependency)
    ignored_versions = Dependabot::Config::UpdateConfig.new(ignore_conditions: config_ignore_conditions).
                       ignored_versions_for(previous_dependency, security_updates_only: security_updates_only)
    ignored_versions.map do |version_requirement|
      IgnoreCondition.new(
        dependency_name: updated_dependency.name,
        version_requirement: version_requirement,
        update_config: self
      )
    end
  end

  def build_previous_dependency(previous_dependency)
    Dependabot::Dependency.new(
      name: previous_dependency.name,
      version: previous_dependency.previous_version,
      requirements: [],
      package_manager: previous_dependency.package_manager
    )
  end

  def registries
    if all_registries?
      repo.registries.for_package_manager(package_manager)
    else
      update_config_registries.map(&:registry)
    end
  end

  def cooldown
    update_config_cooldown&.cooldown_settings
  end

  def manifest_directories
    if directory.present?
      Directories.new(directory)
    else
      Directories.new(directories)
    end
  end

  def find_registry_by(type:, host:)
    registries.find do |registry|
      registry.registry_type == type.to_s && registry.key == host
    end
  end

  def automatically_rebase_prs?
    rebase_strategy == "auto"
  end

  def language
    Ecosystems.language_for_package_manager(package_manager)
  end

  # Handle a bug that seems to originate in MySQL date handling where 00-00 is
  # treated as a dummy date and converted to nil:
  # https://dev.mysql.com/doc/refman/5.7/en/date-and-time-types.html
  def update_schedule_time_of_day
    time = self[:update_schedule_time_of_day]
    return Time.zone.parse("2000-01-01 00:00") if time.nil?

    time
  end

  def cronjob_match?(local_time)
    Dependabot::CronjobValidator.cronjob_match?(self[:update_schedule_cron_expression], local_time)
  end

  def formatted_language
    case language
    when Languages::JAVASCRIPT then "JavaScript"
    when Languages::PHP then "PHP"
    when Languages::DEVCONTAINERS then "Dev Containers"
    when Languages::DOTNET then ".NET"
    when Languages::GITHUB_ACTIONS then "GitHub Actions"
    else language.capitalize
    end
  end

  def recently_triggered_scheduled_update_job?
    return false if last_scheduled_job.nil?

    cutoff = UpdateJob::MIN_RUN_INTERVAL.ago
    last_scheduled_job.created_at > cutoff
  end

  def supports_lockfile?
    PACKAGE_MANAGERS_WITH_LOCKFILES.key?(package_manager)
  end

  def supports_repository_access?
    # we don't allow access to private repositories from public
    # repositories
    return false unless repo.private?

    !risk_of_untrusted_code_execution?
  end

  def reject_external_code?
    return false if registries.empty?

    risk_of_untrusted_code_execution? && insecure_external_code_execution_denied?
  end

  def insecure_external_code_execution_denied?
    insecure_external_code_execution != "allow"
  end

  def risk_of_untrusted_code_execution?
    PACKAGE_MANAGERS_WITH_CODE_EXECUTION.include?(package_manager)
  end

  def formatted_lockfile_name
    return unless supports_lockfile?

    lockfiles = PACKAGE_MANAGERS_WITH_LOCKFILES[package_manager]
    raise "Package manager doesn't support lockfiles" unless lockfiles

    lockfiles.to_sentence(two_words_connector: " or ", last_word_connector: " or ")
  end

  def accessible_github_repo_ids
    repo_ids = [repo.github_id]

    repo_ids += account.repository_accesses.pluck(:github_id) if supports_repository_access?
    repo_ids += jit_accessed_internal_github_repo_ids

    repo_ids.uniq
  end

  def accessible_github_repos
    Repo.where(github_id: accessible_github_repo_ids)
  end

  def jit_accessed_internal_github_repo_ids
    Array(Dependabot.redis.smembers(jit_accessed_internal_repos_key)).map(&:to_i)
  end

  def add_jit_accessed_internal_github_repo_ids(repo_ids)
    Dependabot.redis.sadd(jit_accessed_internal_repos_key, repo_ids)
  end

  def remove_jit_accessed_internal_github_repo_ids(repo_ids)
    Dependabot.redis.srem(jit_accessed_internal_repos_key, repo_ids)
  end

  def jit_accessed_internal_repos_key
    "internal_accessed_repos:#{id}"
  end

  def event_stream
    @event_stream ||= Activity::UpdateConfigLogger.new(update_config: self)
  end

  # We currently only support debug as a feature flag as the debug-level logging
  # is not widely adopted in Core for it to be worth a customer's time, but in
  # future we should consider permitting `debug: true` to be set in their config
  # file.
  def debug_logging_enabled?
    repo.config_feature_enabled?(:debug_logging)
  end

  #######################
  # State machine setup #
  #######################

  def state_machine
    @state_machine ||= UpdateConfigStateMachine.new(
      self,
      association_name: :update_config_transitions,
      transition_class: UpdateConfigTransition,
    )
  end

  def telemetry_attributes
    {
      "gh.dependabot_api.update_config.id": id,
    }.merge(repo.telemetry_attributes)
  end

  private

  def name_normaliser
    Dependabot::Dependency.name_normaliser_for_package_manager(package_manager)
  end

  def target_branch_changed?
    saved_change_to_target_branch?
  end

  # TODO: Move to a background job
  #
  # This query running in an after_commit hook could pose problems as our
  # database grows.
  def update_pr_base_branches
    return unless active?
    return unless account.active?
    return if repo.paused?

    pull_requests.open.find_each do |pr|
      UpdatePullRequestBaseBranchJob.perform_later(pull_request: pr)
    end
  end

  def update_strategy_is_valid
    return unless requirements_update_strategy

    allowed_strategies = UPDATE_STRATEGIES.fetch(package_manager.to_s, [])
    return if allowed_strategies.include?(requirements_update_strategy)

    msg = if allowed_strategies.empty?
            "an update strategy cannot be specified for #{package_manager} deps"
          else
            "allowed update strategies are: #{allowed_strategies.join(', ')}"
          end

    errors.add(:requirements_update_strategy, msg)
  end

  def validate_directories_are_sorted
    return if directories == directories.sort

    errors.add(:directories, "must be sorted")
  end

  def set_default_required_instance_size
    self.required_instance_size ||=
      package_manager == PackageManagers::COMPOSER ? AWS_INSTANCE_MEDIUM : AWS_INSTANCE_SMALL
  end

  def instrument
    MetricsClient.increment("update_config.created",
                            tags: {
                              package_manager: package_manager,
                              update_schedule: update_schedule,
                            })
  end

  def validate_directory_xor_directories
    return unless directory.present? && directories.present?

    errors.add(:directories, "cannot be set when directory is set")
  end

  # Validates the length of directories. Each directory should have a maximum of 1024 characters.
  # If any directory has more than 1024 characters, or is not a string, an error is added to the errors object.
  def validate_directories
    directories.each do |dir|
      unless dir.is_a?(String) && dir.length <= 1024
        errors.add(:directories, "#{dir.inspect} must have fewer than 1024 characters")
      end
    end
  end

  # Validates that the directories are unique within the same record.
  def validate_unique_directories_within_record
    return if directories.map(&:downcase).uniq.length == directories.length

    errors.add(:directories, "cannot have duplicate directories")
  end
end
# rubocop:enable Metrics/ClassLength
