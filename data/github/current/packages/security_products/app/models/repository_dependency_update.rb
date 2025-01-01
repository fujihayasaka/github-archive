# typed: true
# frozen_string_literal: true

# Acts as an entry point for Dependabot updates on a Repository, providing
# an outcome for each request made by the source repository in the form of
# either a Pull Request or a user-facing error message.
class RepositoryDependencyUpdate < ApplicationRecord::Notify
  include GitHub::Validations
  # This value represents our service contract with Dependabot, after which we
  # should abandon jobs as failed.
  DEPENDABOT_MAX_WAIT = 24.hours
  # Manually requested jobs are expected to jump the queue and resolve much more
  # quickly.
  DEPENDABOT_MAX_WAIT_FOR_MANUAL = 40.minutes
  # Dependabot's update runner times out after 30 minutes. Under normal circumstances
  # it should reply with an error shortly after, so this time is set to allow for this
  # plus time to ingest and callback via GraphQL.
  #
  # see: https://github.com/dependabot/update-job-runner/blob/master/handler.go#L26

  # Dependabot update job log retention in AWS S3 (Deltaforce Production)
  # Update the following references when changing the retention:
  # https://github.com/github/dependabot-api/blob/d700dfcba1a48dcf6413d81e16e7ce9e7208e69e/app/models/update_job_logs.rb#L12
  # https://github.com/github/composer/blob/4b0629994d4d753b404479510f161819c970710c/sites/dfprod-us-east-1/main.tf#L42
  DEPENDABOT_UPDATE_JOB_LOG_RETENTION = 14.days

  DEFAULT_ERROR_TYPE  = "unknown_error".freeze
  DEFAULT_ERROR_TITLE = "Dependabot encountered an unknown error".freeze
  DEFAULT_ERROR_BODY  = <<~MD.chomp.freeze
                          Dependabot encountered an unknown error.

                          We've been notified of the problem, and are working to fix it.
                          MD

  TIMEOUT_ERROR_TYPE = "dependabot_timed_out".freeze
  TIMEOUT_ERROR_TITLE = "Dependabot has taken too long to create an update"
  TIMEOUT_ERROR_BODY = <<~MD.chomp.freeze
    Dependabot may be experiencing problems creating updates for this project.

    If this problem persists, please contact support.
  MD

  # - `pull_request_exists_for_security_update` dependabot has already created
  #   a pull request for the fixed version (open or closed, closed implying
  #   ignored), this can happen if a vulnerability is updated with a new range
  #   but the fixed version remains the same for the given major version
  # - `edited_pull_request_exists` dependabot has already created a pull
  #   request for the same dependency but it's been edited by someone other
  #   than dependabot so can't be superseded
  # - `pull_request_creation_halted` the pull request no longer needs to be
  #   created due to a deactivated install or existing pull request
  # - `update_not_possible` e.g. peer/parent dependency constraints prevents
  #   the dependency from being updated to the latest available version
  # - `security_update_dependency_not_found` the security update could not find
  #   the vulnerable dependency in the repository
  # - `security_update_not_found` Dependabot can't find a published or
  #   compatible non-vulnerable version, this can happen if the fixed version
  #   hasn't been published yet or the published version isn't compatible with
  #   the current enviroment (e.g. python version) or version (uses a
  #   different version suffix for gradle/maven)
  # - `security_update_not_possible` e.g. peer/parent dependency constraints
  #   prevents the dependency from being updated to a non-vulnerable version
  # - `security_update_not_needed` The dependency is no longer vulnerable
  # - `cancelled_update` the job could not be started due to deactivated
  #   install or invalid repo
  EXPECTED_ERRORS = %w(
    pull_request_exists_for_security_update
    edited_pull_request_exists
    pull_request_creation_halted
    security_update_dependency_not_found
    security_update_not_found
    security_update_not_possible
    security_update_not_needed
    update_not_possible
    cancelled_update
  ).freeze

  # - `tool_version_not_supported` when the detected version of a tool is not
  #   supported by dependabot
  # - `dependency_file_not_supported` when the current version can't be
  #   deteremined (e.g. missing lockfile)
  # - `git_dependencies_not_reachable` fetching dependencies from private git
  #   repositories
  # - `missing_environment_variable` unreachable private PHP dependencies
  # - `private_source_*` private registry credentials missing
  UNSUPPORTED_ERRORS = %w(
    tool_version_not_supported
    dependency_file_not_supported
    git_dependencies_not_reachable
    missing_environment_variable
    private_source_not_reachable
    private_source_authentication_failure
    private_source_timed_out
    private_source_certificate_failure
  ).freeze

  # The following errors are known error-cases in dependabot-core resulting in
  # a user-facing error message explaining why the update failed.
  USER_ERRORS = %w(
    branch_not_found
    directory_not_found
    dependency_file_not_found
    dependency_file_not_evaluatable
    dependency_file_not_parseable
    dependency_file_not_resolvable
    job_repo_not_found
    path_dependencies_not_reachable
    git_dependency_reference_not_found
    misconfigured_tooling
    go_module_path_mismatch
    bad_gitmodules
    all_versions_ignored
    pull_request_exists_for_latest_version
  ).freeze

  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain legacy_return_type: true
  belongs_to :pull_request, inverse_of: :dependency_updates
  belongs_to :repository_vulnerability_alert

  extend GitHub::Encoding
  force_utf8_encoding :body, :error_body, :error_title

  attribute :manifest_path, StringFromBinary.new

  enum :state, %i{
    requested
    complete
    error
  }

  enum :reason, %i{
    vulnerability
    upgrade
  }

  enum :trigger_type, %i{
    manual
    install
    scan
    push
    dry_run
  }

  validates_presence_of :repository, :manifest_path, :package_name
  validates :manifest_path, bytesize: { maximum: 1024 }
  validates :package_name, unicode3: true

  # A newly requested update should not a pull request or error content.
  validates_absence_of :pull_request, :error_title, :error_body, :error_type, if: :requested?

  # A completed update must have a pull request assigned.
  validates_presence_of :pull_request, if: :complete?

  # We require an error body and title when put into an errored state.
  validates_presence_of :error_body, :error_title, if: :error?
  validates_absence_of :pull_request, if: :error?

  # A vulnerability update must have an alert assigned at creation.
  validates_presence_of :repository_vulnerability_alert, if: :vulnerability?, on: :create

  validate :pull_request_belongs_to_repository
  validate :manifest_path_is_supported, on: :create
  validate :no_new_dry_run_triggers, on: :create

  scope :visible, -> { where(dry_run: false).where.not(trigger_type: :dry_run) }
  scope :for, ->(path:, package:) { where(manifest_path: path, package_name: package) }

  before_create :set_retry_flag

  after_commit :instrument_creation, on: :create
  after_commit :instrument_update, on: :update
  after_commit :enqueue_update_request_job, on: :create

  # Accepts a Repository to create dependency updates for all open
  # RepositoryVulnerabilityAlerts.
  #
  # No dependency updates are created if the Dependabot service is
  # paused for the Repository due to inactivity
  #
  # repository - A Repository to process
  # trigger:    - The event that triggered this request
  #
  # returns an Array of any persisted RepositoryDependencyUpdate objects
  def self.request_for_repository(repository, trigger:)
    return [] if repository.dependabot_updates_paused?

    RepositoryDependencyUpdate::RepositoryResolver.new(repository, trigger: trigger).create_updates
  end

  # Accepts a Repository and a dependency to create an update for.
  #
  # No dependency updates are created if the Dependabot service is
  # paused for the Repository due to inactivity
  #
  # repository:    - A Repository to process
  # manifest_path: - The manifest file path in the repository that specifies this dependency
  # package_name:  - The name of the package
  # trigger:       - The event that triggered this request
  #
  # returns a persisted RepositoryDependencyUpdate object, or false if no
  # object can be created
  def self.request_for_dependency(repository:, manifest_path:, package_name:, trigger:)
    # Manually triggered requests should by-pass any pause since they are a signal to Dependabot API
    # to remove the pause flag.
    return false if repository.dependabot_updates_paused? && trigger.to_s != "manual"

    RepositoryDependencyUpdate::DependencyResolver.new(repository: repository,
                                                       manifest_path: manifest_path,
                                                       package_name: package_name,
                                                       trigger: trigger).create_update
  end

  # Accepts a manifest path and returns a boolean value if Dependabot is expected
  # to successfully create a Pull Request for the given manifest type.
  def self.manifest_path_supported?(manifest_path)
    DependencyManifestFile.supported_by_dependabot?(path: manifest_path)
  end

  # Returns a symbol representing the package manager involved in this update.
  #
  # NOTE: The returned value is expected to match the Dependabot dictionary:
  # https://github.com/github/dependabot-api/blob/master/app/actions/parse_config_file.rb#L26-L42
  #
  # e.g. :rubygems in github/github is :bundler in github/dependabot-api
  def package_manager
    @package_manager ||= dependabot_package_manager
  end

  def dry_run?
    dry_run || super
  end

  # Returns true if Dependabot is currently producing or has produced a Pull Request
  def requested_or_proposed?
    requested? || proposed_change_exists?
  end

  # Returns true if Dependabot has created a Pull Request
  def proposed_change_exists?
    complete? && pull_request
  end

  # Returns true if a PR has been created and closed by the user, signalling
  # that Dependabot should ignore this specific fixed version.
  def proposed_change_ignored?
    pr = pull_request
    return false unless pr && proposed_change_exists?

    pr.closed? && !pr.merged?
  end

  def mark_as_errored(title:, body:, type:)
    update!(state: "error",
            error_title: title,
            error_body: body,
            error_type: type)
  end

  def mark_as_complete(pull_request:)
    update!(state: "complete",
            pull_request: pull_request)
  end

  def hydro_entity_payload
    {
      id_value: id,
      state: state,
      reason: reason,
      trigger: trigger_type,
      manifest_path: manifest_path,
      package_name: package_name,
      error_title: error_title,
      error_body: error_body,
      error_type: error_type,
      created_at: created_at,
      updated_at: updated_at,
      # We still have rows with `trigger_type` of `dry_run`, so we cannot
      # rely on the attribute until they are cleaned up.
      #
      # See: https://github.com/github/dependabot-api/issues/442
      dry_run: dry_run?,
    }
  end

  # Returns true if the update was set to errored by the cleanup job instead
  # of the Dependabot service.
  def timed_out?
    error_type == "dependabot_timed_out"
  end

  # Returns true if the maximum_resolution_time permitted for the update has passed,
  # indicating that Dependabot has likely abandoned the job.
  def dependabot_has_timed_out?
    return false unless requested?

    (Time.now.utc - T.must(created_at).utc) > maximum_resolution_time
  end

  # Forces the object into an error state with appropriate error title and description
  # for a Dependabot service timeout.
  #
  # This state can be ovewritten by the Dependabot service if it responds at a later
  # point in time.
  def cleanup_dependabot_time_out!
    update!(
      error_title: RepositoryDependencyUpdate::TIMEOUT_ERROR_TITLE,
      error_body: RepositoryDependencyUpdate::TIMEOUT_ERROR_BODY,
      error_type: RepositoryDependencyUpdate::TIMEOUT_ERROR_TYPE,
      state: :error
    )

    GitHub.dogstats.increment(
      "repository_dependency_update.cleaned_up",
      tags: ["trigger:#{trigger_type}",
      "installed:#{T.must(repository).dependabot_installed?}"]
    )

    GlobalInstrumenter.instrument("repository_dependency_update.cleaned_up", {
      repository_dependency_update: self,
      repository: repository,
    })
  end

  private

  def dependabot_package_manager
    dg_package_manager = DependencyManifestFile.corresponding_package_type(path: manifest_path)

    return :unknown unless dg_package_manager

    case dg_package_manager
    when :rubygems then :bundler
    when :npm then :npm_and_yarn
    when :go then :go_modules
    else dg_package_manager
    end
  end

  def instrument_creation
    GitHub.dogstats.increment("repository_dependency_update.created",
                              tags: [
                                "trigger:#{trigger_type}",
                                "package_manager:#{package_manager}",
                                "retry:#{retry?}",
                              ])

    GlobalInstrumenter.instrument("repository_dependency_update.created", {
      repository_dependency_update: self,
      repository: repository,
    })
  end

  def instrument_update
    return unless saved_change_to_attribute? :state

    duration = Time.now - T.must(created_at)
    tags = [
      "trigger:#{trigger_type}",
      "package_manager:#{package_manager}",
      "state:#{state}",
      "viable_update:#{viable_update?}",
      "retry:#{retry?}",
      "lt_5m:#{duration < 5.minutes}",
      "lt_20m:#{duration < 20.minutes}",
      "lt_12h:#{duration < 12.hours}",
      "lt_24h:#{duration < 24.hours}",
    ]
    GitHub.dogstats.distribution("repository_dependency_update.dist.duration", duration, tags: tags)

    case state
    when "complete"
      instrument_complete
    when "error"
      instrument_error
    end
  end

  def instrument_complete
    GitHub.dogstats.increment("repository_dependency_update.completed",
                              tags: [
                                "trigger:#{trigger_type}",
                                "package_manager:#{package_manager}",
                                "retry:#{retry?}",
                              ])

    # TODO: Remove
    #
    # See: https://github.com/github/observability/issues/2757
    #
    # This metric is essentially a duplicate of the above as we've observed
    # a lossy count on it, so the distribution is essentially a duplicate
    # where we will count the number of reports rather than the actual value
    # as a comparison.
    GitHub.dogstats.distribution("repository_dependency_update.dist.completed_debug",
      1, # as noted, this is just a dummy value
      tags: [
        "trigger:#{trigger_type}",
        "package_manager:#{package_manager}",
        "retry:#{retry?}",
      ])

    GlobalInstrumenter.instrument("repository_dependency_update.complete", {
      repository_dependency_update: self,
      repository: repository,
      pull_request: pull_request,
    })
  end

  def instrument_error
    GitHub.dogstats.increment("repository_dependency_update.errored",
                              tags: [
                                "trigger:#{trigger_type}",
                                "package_manager:#{package_manager}",
                                "retry:#{retry?}",
                                "viable_update:#{viable_update?}",
                                "timed_out:#{timed_out?}",
                              ])

    GlobalInstrumenter.instrument("repository_dependency_update.errored", {
      repository_dependency_update: self,
      repository: repository,
    })
  end

  # Returns true if the update is successful or viable to succeed. Excludes
  # expected errors and unsupported features (private registries) from
  # Dependabot's SLO on dependency update success rate.
  public def viable_update?
    (EXPECTED_ERRORS + UNSUPPORTED_ERRORS + USER_ERRORS).exclude?(error_type)
  end

  def enqueue_update_request_job
    return unless GitHub.dependabot_enabled?

    repo = repository
    return unless repo

    if repo.dependabot_installed?
      enqueue_vulnerability_update_in_hydro
    else
      # If the user has requested this update from the UI,
      # or vulerability alert was created, let's go ahead and
      # install Dependabot so we can complete it.
      # This will call back into #enqueue_vulnerability_update_in_hydro after
      # the installation is finished.
      Dependabot.enroll_for_single_update(dependency_update: self)

      # If we are performing a just-in-time install for a non-manual update, it
      # is happening as a result of a 'leak' in onboarding pipeline for that trigger,
      # which we are attempting to mitigate.
      #
      # See: https://github.com/github/dependabot-updates/issues/2537
      return if manual?

      GitHub.dogstats.increment("repository_dependency_update.jit_install_enqueued",
        tags: [
          "trigger:#{trigger_type}",
          "package_manager:#{package_manager}",
        ])

      GitHub.logger.info("just-in-time install performed",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.repo.id": repo.id,
        "gh.repo.jit.trigger_type": trigger_type,
      )
    end
  end

  # In the case a dependabot installation has just been performed, we can pass the install id, otherwise
  # we must query for it
  public def enqueue_vulnerability_update_in_hydro(dependabot_install_id: T.must(repository).dependabot_install.id)
    alert = repository_vulnerability_alert
    return unless vulnerability? && alert

    GlobalInstrumenter.instrument("repository_dependency_update.created.vulnerability", {
      repository_dependency_update: self,
      repository_vulnerability_alert: repository_vulnerability_alert,
      security_advisory: T.must(alert.vulnerability).becomes(SecurityAdvisory),
      security_vulnerability: T.must(alert.vulnerable_version_range).becomes(SecurityVulnerability),
      github_bot_install_id: dependabot_install_id,
    })
  end

  def maximum_resolution_time
    return DEPENDABOT_MAX_WAIT_FOR_MANUAL if manual?

    DEPENDABOT_MAX_WAIT
  end

  # We must ensure we don't associate another Repository's Pull Request by mistake.
  def pull_request_belongs_to_repository
    pr = pull_request
    repo = repository
    return unless pr && repo

    unless pr.repository == repo
      errors.add(:pull_request, "Pull Request must belong to Repository '#{repo.nwo}'")
    end
  end

  def manifest_path_is_supported
    unless self.class.manifest_path_supported?(manifest_path)
      errors.add(:manifest_path, "Dependabot cannot perform upgrades on this manifest file")
    end
  end

  def no_new_dry_run_triggers
    if trigger_type == "dry_run"
      errors.add(:trigger_type, "`dry_run` is no longer supported for new data.")
    end
  end

  def set_retry_flag
    # retry must not be nil, so ensure we prefer false if there is no repository alert
    self.retry = repository_vulnerability_alert&.repository_dependency_updates&.any? || false
  end
end
