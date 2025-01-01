# typed: false
# frozen_string_literal: true

class DeploymentStatus < ApplicationRecord::Domain::IssuesPullRequests
  include Instrumentation::Model
  include GitHub::Relay::GlobalIdentification
  include GitHub::Validations

  SUCCESS = "success".freeze
  INACTIVE = "inactive".freeze
  IN_PROGRESS = "in_progress".freeze

  STATES = [IN_PROGRESS, "queued", "pending", SUCCESS, "failure", INACTIVE, "error", "waiting"].freeze

  belongs_to :creator, class_name: "User"
  belongs_to :deployment
  # rubocop:todo Rails/InverseOf
  belongs_to :performed_via_integration,
    foreign_key: :performed_by_integration_id,
    class_name: "Integration"
  # rubocop:enable Rails/InverseOf

  before_validation :set_repository_id, on: :create
  before_validation :strip_url_whitespace

  # `after_commit` callbacks are run in reverse order to how they're defined.
  # We do not want to create an environment here if the deployment status is inactive.
  after_commit :create_environment, on: :create, if: :should_create_environment?
  after_commit :instrument_create, on: :create
  after_commit :instrument_update, on: :update
  after_commit :instrument_deployment_review_requested, on: :create, if: :deployment_pending_approval?
  after_commit :track_state_stats
  after_commit :trigger_environment_changed_events, on: :create
  after_commit :notify_socket_subscribers, on: :create
  after_commit :update_deployments_latest_status_and_environment, on: :create # keep after `notify_socket_subscribers`
  after_commit :call_auto_merge_job_enqueuer, on: :create, if: :succeeded?

  before_save :set_environment

  validate :validate_environment_encoding

  validates_presence_of :creator_id
  validates_presence_of :deployment_id
  validates_inclusion_of :state, in: STATES
  validates_length_of :description, maximum: 140, allow_nil: true
  validates :description, unicode3: true
  validates_length_of :environment, maximum: 255, allow_nil: true
  validates_format_of :environment_url, :log_url, with: /\Ahttp/,
    on: :create, message: "must use http(s) scheme", allow_blank: true
  validate :limit_per_deployment, on: :create
  validates :repository_id, presence: true, on: :create

  extend GitHub::RenameColumn
  rename_column target_url: :log_url

  delegate :notify_socket_subscribers, to: :deployment

  # Filter deployment statuses to just those that were successful. Keep in sync with #succeeded?.
  scope :success, -> { where(state: SUCCESS) }

  # Internal: the max number of DeploymentStatuses per Deployment
  def self.max_per_deployment
    100
  end

  def update_deployments_latest_status_and_environment
    GitHub.logger.info("updating deployment latest status and environment", {
      "code.namespace" => self.class.name,
      "code.function" => "update_deployments_latest_status_and_environment",
      "gh.creator_id" => creator_id,
      "gh.repo.id" => repository_id,
      "gh.deployment_id" => deployment_id,
      "gh.deployment.ref" => deployment.ref,
      "gh.deployment.check_run_id" => deployment.check_run_id,
      "gh.deployment.previous_latest_deployment_status_id" => deployment.latest_deployment_status_id,
      "gh.deployment.new_latest_deployment_status_id" => id,
      "gh.deployment.previous_latest_status_state" => deployment.latest_status_state,
      "gh.deployment.new_latest_status_state" => state,
      "gh.deployment.previous_latest_environment" => deployment.latest_environment,
      "gh.deployment.new_latest_environment" => environment,
      "gh.deployment.previous_latest_environment_id" => deployment.latest_environment_id,
      "gh.deployment.new_latest_environment_id" => environment_id,
    })
    deployment.update(latest_deployment_status_id: id, latest_status_state: state, latest_environment: environment,
      latest_environment_id: environment_id)
  end

  # Internal: enforce a max number of DeploymentStatuses per Deployment
  # Fired via a validation
  def limit_per_deployment
    if deployment.statuses.count >= self.class.max_per_deployment
      errors.add :base, "This deployment has reached the maximum number of statuses."
    end
  end

  # Public - check if the state is 'success'
  #
  # Keep in sync with `success` scope.
  #
  # Returns true if the state is 'success', otherwise it returns false.
  def succeeded?
    state == SUCCESS
  end

  # Public - get the sha for the Deployment
  #
  # Returns the 40 character sha for the deployment
  def sha
    deployment.sha
  end

  # Public - get the repository for the Deployment
  #
  # Returns the Repository associated with the status
  def repository
    deployment.repository
  end

  # Public - is this the latest status on a deployment?
  def latest_status?
    deployment.latest_status.id == self.id
  end

  def encoded_log_url
    log_url.dup&.force_encoding("UTF-8")
  end

  private

  def set_repository_id
    self.repository_id = deployment&.repository_id
  end

  def event_payload
    event_context
  end

  def event_context(prefix: event_prefix)
    {
      "#{prefix}_id".to_sym => id,
      "#{prefix}_state".to_sym => state,
      "public_repo".to_sym => repository&.public?,
    }
  end

  def instrument_create
    instrument :create
  end

  def instrument_update
    instrument :update
  end

  def instrument_deployment_review_requested
    GitHub::instrument "deployment_review.requested", {
        deployment_status_id: id
    }
  end

  def track_state_stats
    GitHub.dogstats.increment("deployment_status", tags: ["state:#{state}"])
  end

  def deployment_pending_approval?
    state == "waiting"
  end

  def should_create_environment?
    state != INACTIVE
  end

  def validate_environment_encoding
    if environment != nil && !GitHub::UTF8.valid_unicode3?(environment)
      errors.add(:environment, "contains unicode characters above 0xffff")
    end
  end

  # If an explicit environment is not set,
  # a DeploymentStatus environment will default to
  #  - The environment of the previous status on the deployment, if it exists
  #  - Otherwise, the environment of the deployment
  def set_environment
    return if self.environment

    previous_status = deployment.statuses.order("id DESC").first

    if previous_status&.environment
      self.environment = previous_status.environment
      self.environment_id = previous_status.environment_id
    else
      self.environment = deployment.environment
      self.environment_id = deployment.environment_id
    end
  end

  # If this deployment status modified the environment of the deployment,
  # create an issue event.
  def trigger_environment_changed_events
    previous_environment = if deployment.statuses.count == 1
      deployment.environment
    else
      previous_status = deployment.statuses.second
      return if previous_status.nil?
      previous_status.environment
    end

    # No change in environment
    return if previous_environment == environment

    deployment.pull_requests.each do |pull_request|
      pull_request.issue.create_deployment_environment_changed_event(self)
    end
  end

  def call_auto_merge_job_enqueuer
    deployment.pull_requests.each do |pull_request|
      pull_request.enqueue_auto_merge_job_if_enabled
    end
  end

  def strip_url_whitespace
    return unless environment_url
    self.environment_url = environment_url.strip.presence
  end

  def create_environment
    if environment
      environment_id = Environment.create_for_repository(repository.id, environment)&.id
      update(environment_id: environment_id)
    end
  end
end
