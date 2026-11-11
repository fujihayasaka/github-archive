# frozen_string_literal: true

require "dependabot/utils"
require "nullable_serializer"

# PullRequest provides a durable link in dependabot-api to a pull request
# created by Dependabot in github.com and maintains state for dependabot-api's
# concerns.
#
# On PendingPullRequests, PullRequests, and :pending PullRequests:
#
# Conceptually, a pull request starts life in dependabot-api as an instance of
# PendingPullRequest. A PendingPullRequest serves as a vessel to hold a
# reference to updater artifacts that we store in Azure and later retrieve in
# order to create a PullRequest in dependabot-api and a pull request in
# github.com. A PendingPullRequest is created in a :pending state;
# if a PullRequest is successfully created, the PendingPullRequest transitions
# to the :created state; otherwise, it eventually transitions to the
# :abandoned state.
#
# When the create_pr_in_pending_state feature is enabled, a PullRequest may
# also be created in a :pending state, via PullRequest.create_pending!.
# In this workflow, a PullRequest is created in the :pending state and an
# attempt is made to create a pull request in github.com. If creating a pull
# request in github.com succeeds, the :pending PullRequest is updated with
# the details of the github.com pull request and transitioned to the
# :up_to_date state; if it fails, the :pending PullRequest is deleted.
# By creating the PullRequest in dependabot-api first, we avoid the risk of
# creating a Dependabot pull request in github.com without a durable link to
# it in our service.
class PullRequest < ApplicationRecord
  T.unsafe(self).include Statesman::Adapters::ActiveRecordQueries[
    transition_class: PullRequestTransition,
    transition_name: :pull_request_transition,
    initial_state: PullRequestStateMachine.initial_state,
  ]

  DEPENDABOT_PR_TOKEN_PREFIX = "dependabot-pr_"

  NO_REBASE_AFTER_CUTOFF_PERIOD = 30.days

  PENDING_PR_NUMBER = nil
  PENDING_COMMIT_SHA = ("0" * 40).freeze

  belongs_to :update_job
  belongs_to :repo
  belongs_to :update_config
  belongs_to :dependency_group, optional: true
  has_many :updated_dependencies, dependent: :destroy

  has_many :pull_request_transitions, autosave: false, dependent: :destroy
  has_one :account, through: :repo, inverse_of: :pull_requests

  has_many :autofix_suggestion_jobs, inverse_of: :pull_request, dependent: :destroy

  validates :github_number,
            allow_nil: true,
            uniqueness: { scope: :repo_id }
  validates :multiple_dependencies, inclusion: { in: [true, false] }
  validates :head_commit_sha,
            presence: true,
            exclusion: { in: [PENDING_COMMIT_SHA], unless: :pending? }
  validates :dependabot_commit_sha,
            presence: true,
            exclusion: { in: [PENDING_COMMIT_SHA], unless: :pending? }
  validates :base_commit_sha, presence: true
  # The grouped_update flag _must_ be true if a DependencyGroup is associated.
  validates :grouped_update, inclusion: { in: [true] }, if: -> { dependency_group.present? }

  delegate :can_transition_to?, :transition_to!, :transition_to, :current_state,
           :last_transition, :in_state?, to: :state_machine
  delegate :multi_ecosystem_config, :multi_ecosystem_config_id, :multi_ecosystem_config_id?, to: :update_config

  serialize :affected_directories, coder: NullableSerializer.new(Array)

  scope :open, -> { in_state(:up_to_date, :updating) }
  scope :for_repo_github_id, ->(repo_github_id) { joins(:repo).where(repos: { github_id: repo_github_id }) }

  # This scope is used to determine if a PR has previously been merged (vs "currently merged")
  scope :previously_merged, lambda {
    where(
      id: includes(:pull_request_transitions).
            where(pull_request_transitions: { to_state: "merged", most_recent: nil })
    )
  }

  scope :exclude_pending, lambda {
    where.not(github_number: nil)
  }

  after_create :set_repo_pause_deadline

  def github_url
    "#{repo.github_url}/pull/#{github_number}"
  end

  def single_dependency?
    !multiple_dependencies?
  end

  def most_recent_update_job
    # Find transitions that have associated UpdateJobs
    latest_transition_with_job = pull_request_transitions.
                                 joins(:update_job).
                                 order(:sort_key).
                                 last

    latest_transition_with_job&.update_job || update_job
  end

  def diff
    installation_github_client.pull_request(
      repo.github_id,
      github_number,
      accept: "application/vnd.github.VERSION.diff",
    )
  end

  #######################
  # State machine setup #
  #######################

  def state_machine
    @state_machine ||=
      PullRequestStateMachine.new(
        self,
        association_name: :pull_request_transitions,
        transition_class: PullRequestTransition
      )
  end

  def create_rebase_update_jobs(manual: false)
    raise "Invalid state" unless in_state?(:updating)

    # Ordering of the dependencies list is important for multi-dependency
    # PRs because the update checker uses it to determine which is the
    # "primary" dependency being updated.
    dependencies = updated_dependencies.order(:id)

    # Carry over `security_updates_only`, which is set when the update job
    # is in response to a security alert.
    security_updates_only = update_job&.security_updates_only || false

    # Carry over `github_request_id` so that the new rebase job has a link
    # to the `RepositoryDependencyUpdate` record in GitHub.
    github_request_id = update_job&.github_request_id

    update_job_ids = rebase_update_config_ids.map do |update_config_id|
      create_rebase_update_job(update_config_id:, dependencies:, security_updates_only:, github_request_id:, manual:)
    end
    UpdateJob.where(id: update_job_ids)
  end

  def rebase_update_config_ids
    return multi_ecosystem_config.update_configs.ids if multi_ecosystem_config_id?

    [update_config.id]
  end

  def age_in_days
    return 0 unless created_at

    @age_in_days ||= (Time.now.utc.to_date - created_at.to_date).to_i
  end

  def event_stream
    @event_stream ||= Activity::PullRequestLogger.new(pull_request: self)
  end

  def too_old_for_automatic_rebase?
    return false unless created_at < NO_REBASE_AFTER_CUTOFF_PERIOD.ago

    MetricsClient.increment("compute_reduction", tags: { initiative: "no_rebase_after_cutoff_period" })
    true
  end

  def incorrectly_in_closed_state?
    transitions = state_machine.history
    return false if transitions.length < 2
    return false if transitions[-1].to_state != "closed"
    return false if transitions[-2].to_state != "merged"

    true
  end

  def currently_updating?
    current_transition = last_transition

    return false unless current_transition&.to_state == "updating"

    # Give an update 3 hrs to complete. Otherwise, assume the update has completed but
    # state was not properly updated.
    current_transition.created_at > 3.hours.ago
  end

  def open?
    in_state?(:up_to_date, :updating)
  end

  def pending?
    return true if in_state?(PullRequestStateMachine.initial_state) && !persisted?
    return true if in_state?(:pending)

    false
  end

  def dependabot_was_last_committer?
    dependabot_commit_sha == head_commit_sha
  end

  def broke_ci?
    base_commit_ci_status == GitHub::CheckRun::Conclusion::SUCCESS &&
      dependabot_commit_ci_status == GitHub::CheckRun::Conclusion::FAILURE
  end

  def autofix_candidate?
    return false unless broke_ci? && repo.autofix_enabled? && !head_commit_ci_status.nil?

    # autofixes are limited to supported languages with updates to version requirements
    supported_package_managers = AutofixSuggestionJob::AUTOFIX_SUPPORTED_LANGUAGES.flat_map do |lang|
      Ecosystems.package_managers_for_language(lang)
    end
    updated_dependencies.
      where(package_manager: supported_package_managers).
      where("requirements <> previous_requirements").
      any?
  end

  def telemetry_attributes
    {
      "gh.dependabot_api.pull_request.id": id,
    }.merge(most_recent_update_job&.telemetry_attributes || {})
  end

  def hashed_token
    Dependabot.redis.get("pr-hashed-token:#{id}")
  end

  def hashed_token=(value)
    Dependabot.redis.set("pr-hashed-token:#{id}", value, ex: 24.hours)
  end

  def actions_workflow_run_id=(value)
    Dependabot.redis.set("pr-actions-workflow-run-id:#{value}", id, ex: 24.hours)
  end

  private

  def set_repo_pause_deadline
    event_stream.record_event(Activity::PullRequestEvents::CREATED)
  end

  def create_rebase_update_job(update_config_id:, dependencies:, security_updates_only:, github_request_id:, manual:)
    raise "Invalid state" unless in_state?(:updating)

    update_config = UpdateConfig.find(update_config_id)
    ecosystem_package_manager = update_config.package_manager
    ecosystem_dependencies = dependencies.select { |dep| dep.package_manager == ecosystem_package_manager }
    directories = determine_directories(ecosystem_dependencies, update_config)

    UpdateJob.create(
      command: :recreate,
      directories: directories,
      update_config_id: update_config_id,
      pull_request_transition_id: last_transition&.id,
      dependencies: ecosystem_dependencies.map(&:name),
      github_request_id: github_request_id,
      pull_request_transition: last_transition,
      security_updates_only: security_updates_only,
      trigger_type: manual ? "manual_rebase" : "rebase",
      enqueue_scheduled_update_id: enqueue_scheduled_update_id,
    )
  end

  def determine_directories(ecosystem_dependencies, update_config)
    if update_config.multi_ecosystem_config_id
      dirs = ecosystem_dependencies.map(&:directory).uniq
      return dirs unless dirs.empty?

      return update_config.manifest_directories.to_a
    end

    affected_directories
  end

  def enqueue_scheduled_update_id
    @enqueue_scheduled_update_id ||= SecureRandom.uuid
  end

  def installation_github_client
    @installation_github_client ||=
      GitHubHelpers::ClientWithRetries.new(
        account: account,
      )
  end
end
