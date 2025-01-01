# typed: false
# frozen_string_literal: true

class Deployment < ApplicationRecord::Domain::IssuesPullRequests
  include Instrumentation::Model
  include GitHub::Relay::GlobalIdentification
  include GitHub::UTF8
  include GitHub::Validations
  include GitHub::Memoizer
  include GitHub::ResilienceMixin
  include GitHub::BatchedScope

  extend GitHub::SimplePagination
  extend GitHub::ResilienceMixin

  include Permissions::Attributes::Wrapper
  self.permissions_wrapper_class = Permissions::Attributes::Deployment

  ABANDONMENT_THRESHOLD = 30.minutes

  after_commit :create_environment, on: :create
  after_commit :trigger_creation_events, on: :create
  after_commit :trigger_issue_deployed_events, on: :create
  after_commit :notify_socket_subscribers, on: :create
  after_commit :destroy_issue_events, on: :destroy

  before_create :set_latest_environment
  before_save :truncate_ref_utf8
  before_save :set_tree_oid

  validates_presence_of :sha, :creator_id, :repository_id
  validate :validate_sha, :validate_environment_encoding

  validates_length_of :latest_environment, maximum: 255, allow_nil: true
  validates_length_of :environment, maximum: 255, allow_nil: true
  validates_length_of :task, within: 1..128
  validates :description, bytesize: { maximum: MYSQL_TEXT_FIELD_LIMIT }, unicode: true
  validates :payload, bytesize: { maximum: MYSQL_TEXT_FIELD_LIMIT }, unicode: true

  belongs_to :creator, class_name: "User"
  # rubocop:todo Rails/InverseOf
  belongs_to :performed_via_integration,
    foreign_key: :performed_by_integration_id,
    class_name: "Integration"
  # rubocop:enable Rails/InverseOf

  belongs_to :repository
  destroy_in_background_with :repository
  belongs_to :check_run, optional: true, inverse_of: :deployment

  # belongs_to :latest_status,
  #   foreign_key: :latest_deployment_status_id,
  #   class_name: "DeploymentStatus"

  default_scope { order(created_at: :desc) }

  scope :by_sha, lambda { |sha| where(sha: sha) }

  scope :by_check_runs, ->(check_runs, repository) {
    from("#{Deployment.quoted_table_name} FORCE INDEX (index_deployments_on_check_run_id)")
      .where(check_run: check_runs)
      .where(repository: repository)
  }

  scope :production_environment, -> { where(production_environment: true) }

  has_many :statuses, -> { order("id DESC") },
                      dependent: :destroy,
                      class_name: "DeploymentStatus"

  has_one :latest_status, -> { order("id DESC") }, class_name: "DeploymentStatus"
  has_one :terminal_status, -> { where(state: %W[success failure error]).order("id DESC") }, class_name: "DeploymentStatus"

  # Find deployments whose latest status was successful. Keep in sync with #active?.
  scope :active, -> do
    deployments = arel_table
    deployment_statuses = DeploymentStatus.arel_table
    latest_status_id_for_deployment = deployment_statuses
      .project(deployment_statuses[:id].maximum)
      .where(deployment_statuses[:deployment_id].eq(deployments[:id]))
    joins(:statuses).merge(DeploymentStatus.success)
      .where(deployment_statuses[:id].eq(latest_status_id_for_deployment))
  end

  delegate :log_url, to: :latest_status, allow_nil: true

  def self.for_tree_oid(tree_oid, repository:)
    repository.deployments.where(tree_oid: tree_oid)
  end

  def self.tree_oid_key(tree_oid, repository:)
    "deployments-for-tree.#{repository.id}.#{tree_oid}"
  end

  def payload
    utf8(read_attribute(:payload))
  end

  def description
    utf8(read_attribute(:description))
  end

  # Deprecated in favor of #current_state
  # Returns the state for the most recently created DeploymentStatus object
  #
  # Returns a String or nil
  def latest_state
    return latest_status.state if latest_status
    return "abandoned" if abandoned?
    "pending"
  end

  def async_state
    async_latest_status.then { state }
  end

  # Public: The current state of this deployment, based on the latest status,
  #   the deployment's settings, and the time.
  def state
    status_state = latest_status&.state

    if status_state.nil?
      return "abandoned" if created_at < ABANDONMENT_THRESHOLD.ago
      return "pending"
    end

    return "active" if status_state == "success"
    return "destroyed" if transient_environment? && status_state == "inactive"
    status_state
  end

  # Public: Check if the deployment's latest status was success.
  #
  # Keep in sync with `.active` scope.
  #
  # Returns a Boolean.
  def active?
    state == "active"
  end

  # The current combined status state for the repo@ref
  #
  # Returns a new combined status object for the Deployment
  def combined_status
    @combined_status ||= CombinedStatus.new(repository, sha,
      statuses: Statuses::Service.current_for_shas(repository_id: repository_id, shas: sha),
      check_runs: CheckRun.latest_for_sha_and_event_in_repository(sha, repository))
  end

  # Return context/state pairs to surface which services are failing
  #
  # Returns an Array of Hashes, one for each unique context for the commit
  def combined_status_contexts
    combined_status.status_checks.map do |status|
      { context: status.context, state: status.state }
    end
  end

  # Return a list of unique context names
  #
  # This list of contexts is used to verify commit statuses when no required
  # contexts are specified at creation time.
  #
  # Returns an Array of Strings, the context names
  def unique_context_names
    combined_status.status_checks.map { |status| status.context }.uniq
  end

  # Return a list of context names that are currently in a "success" state
  #
  # Returns an Array of Strings, the successful context names
  def successful_context_names
    result = combined_status_contexts.map do |status|
      status[:context] if status[:state] == DeploymentStatus::SUCCESS
    end
    result.compact
  end

  # Generate a shortened sha for easier displaying
  #
  # Returns the first 8 characters of a sha
  def short_sha
    sha[0..7]
  end

  # Generate the payload as a hash for dumping to JSON
  #
  # Returns the @payload as parsed json or an empty hash on parse error
  def json_payload
    GitHub::JSON.decode(self.payload)
  rescue StandardError # rubocop:todo Lint/GenericRescue
    {}
  end

  # Get the specified ref or default branch for the repo
  #
  # Returns the ref specified at creation time or falls back to repo defaults.
  def ref
    @ref || attributes["ref"] || repository&.default_branch
  end

  # The ref's name minus the ref namespace prefix.
  #
  # Returns the ref short name as refs/heads/main -> main
  def ref_name
    if ref.start_with?("refs/tags/")
      return ref.delete_prefix("refs/tags/")
    end

    ref.delete_prefix("refs/heads/")
  end

  # Return whether or not we should bring this ref up to date with default_branch
  #
  # Returns true if a merge should be attempted, false otherwise
  def auto_merge?
    @auto_merge && behind_default_branch?
  end

  # Set the auto_merge attribute based on form input. Defaults to true
  #
  # Returns nothing
  def auto_merge=(value)
    @auto_merge = value.nil? ? true : !!value
  end

  # Determine if any required contexts are in a non "success" state
  #
  # Return - true if deployment should be aborted due to required context conflicts
  def failed_commit_statuses?
    required_contexts.any? && !valid_commit_statuses?
  end

  # Validated if the required contexts for deployment are valid.
  #
  # Check the incoming array of required contexts against the successful contexts for the commit.
  #
  # Returns: true if all commit status contexts are 'success', false otherwise
  def valid_commit_statuses?
    return true if required_contexts.empty?

    contexts = successful_context_names
    return false if contexts.empty?
    required_contexts.each do |context|
      return false unless contexts.include?(context)
    end
    true
  end

  # Set the required commit status contexts to validate before creation.
  #
  # Returns nothing
  def required_contexts=(value)
    @required_contexts = value.nil? ? unique_context_names : value
  end

  # An array of named contexts that must be in a "success" state
  #
  # Returns an Array of Strings for named commit statuses
  def required_contexts
    @required_contexts ||= unique_context_names
  end

  # Check if the requested deployment sha is behind the default branch.
  #
  # In the certain cases we want to ensure that the requested deployment
  # is caught up with the default branch, this tells us if we need to.
  #
  # Returns true if the sha is behind the default branch, false otherwise.
  def behind_default_branch?
    repository.comparison(repository.default_branch, sha).behind?
  end

  # Merge the default branch into the requested Deployment ref
  #
  # Returns true if successful, false otherwise.
  def merge_for(actor, options = { message: "Auto-Merging for deployment" })
    return false unless behind_default_branch?

    base_ref = repository.heads.find(ref)
    return false unless base_ref

    merge_commit, error, error_message = base_ref.merge(actor, repository.default_branch, options)
    merge_commit.present?
  end

  def pull_requests
    return @pull_requests if defined?(@pull_requests)

    @pull_requests = PullRequest.where(
      repository_id: repository_id,
      head_sha: sha,
    )
  end

  def merge_queue
    return if repository.blank?

    return @merge_queue if defined?(@merge_queue)
    @merge_queue = MergeQueue.for_locked_oid(repository:, oid: sha).first
  end

  # Check if the requested deployment ever got picked up by a service.
  #
  # In certain cases deployments can be requested that weren't ever handled
  # by a 3rd party. We detect this by the absence of any deployment status
  # relations on a deployment that's older than 30 minutes.
  #
  # Returns true if nothing will likely pick this up, false otherwise.
  def abandoned?
    statuses.empty? && created_at < 30.minutes.ago
  end

  # Public: Whether the given user can see this deployment.
  def readable_by?(actor)
    repository && repository.readable_by?(actor)
  end

  # Set all the previous successful Deployments to the same environment as this
  # Deployment as inactive by creating a new, inactive DeploymentStatus.
  def set_previous_environment_deployments_inactive!(include_production: false, environment_url: nil)
    latest_status = self.reload.statuses.first
    return unless latest_status&.succeeded?
    statuses_to_update = with_read do
      result = Deployment.where(repository_id: repository_id, latest_environment: latest_environment,
                               latest_status_state: DeploymentStatus::SUCCESS,
                               transient_environment: 0)
                         .where.not(id: id)
                         .limit(1000)
      result = result.where(production_environment: 0).or(result.where(production_environment: include_production))

      deployments_ids = result.map(&:latest_deployment_status_id)
      status = DeploymentStatus.where(id: deployments_ids)
      status = status.where("(ISNULL(environment_url) OR environment_url = COALESCE(?, environment_url))", environment_url)

      status.to_a
    end

    statuses_to_update.each_slice(100) do |status_group|
      GitHub.dogstats.count("deployment.status.create_inactive", status_group.size)

      status_group.each do |status|
        throttle_with_retry do
          status_hash = {
            state: "inactive",
            deployment_id: status.deployment_id,
            creator_id: status.creator_id,
            environment: latest_environment,
          }

          # Maintain the log_url of the previously successful DeploymentStatus
          status_hash[:log_url] = status.log_url

          with_write { DeploymentStatus.create(status_hash) }
        end
      end
    end
  end

  def dashboard_channel
    repository.deployments_dashboard_environment_channel(environment)
  end

  sig { params(pull: PullRequest).returns(GitHub::BatchedScope::BatchedScopeQuery[Deployment]) }
  def self.for_pull_request(pull)
    repo = Repository.new(id: pull.repository_id)
    ids = pull.events.where(repository_id: pull.repository_id, event: "deployed").pluck(:deployment_id)
    ids += Deployment.where(repository_id: pull.repository_id, sha: pull.head_sha).pluck(:id)

    batched_scope(:id, values: ids)
  end

  def self.current_production_deployments_for_merge_queue(merge_queue)
    current_deployments_for_merge_queue(merge_queue).production_environment
  end

  def self.current_deployments_for_merge_queue(merge_queue)
    if sha = merge_queue.locked_entry&.head_sha
      Deployment.where(sha:, repository: merge_queue.repository_id)
    else
      Deployment.none
    end
  end

  def notify_socket_subscribers
    pull_requests.each do |pull_request|
      pull_request.notify_socket_subscribers
      pull_request.notify_subscribers_of_successful_deployment if succeeded?
    end

    merge_queue&.notify_socket_subscribers

    GitHub::WebSocket.notify_deployment_channel(self, dashboard_channel, {
      wait: default_live_updates_wait,
    })
  end

  # Public: Check if the deployment was successful.
  def succeeded?
    latest_status_state == DeploymentStatus::SUCCESS
  end

  def workflow_run
    #TODO optimize this
    Actions::WorkflowRun.where(check_suite_id: CheckRun.where(id: check_run_id).pluck(:check_suite_id)).first
  end

  private

  def set_latest_environment
    self.latest_environment = environment
  end

  def truncate_ref_utf8
    return unless ref.present?
    # identify first 4-byte character
    posn = ref.chars.index { |c| c.bytes.count >= 4 }
    return if posn.nil?
    self.ref = ref[0..posn - 1]
  end

  def event_payload
    # TODO: Normalize repository prefix to repo
    {
      event_prefix => self,
      :repository  => repository,
      :creator     => creator,
    }
  end

  def validate_sha
    if !GitRPC::Util.valid_full_oid?(sha)
      errors.add(:sha, "must be a 40 character SHA1")
    end
  end

  def validate_environment_encoding
    if environment != nil && !GitHub::UTF8.valid_unicode3?(environment)
      errors.add(:environment, "contains unicode characters above 0xffff")
    end
    if latest_environment != nil && !GitHub::UTF8.valid_unicode3?(latest_environment)
      errors.add(:latest_environment, "contains unicode characters above 0xffff")
    end
  end

  def create_environment
    environment_id = Environment.create_for_repository(repository_id, environment)&.id
    update(latest_environment_id: environment_id, environment_id: environment_id)
  end

  def trigger_creation_events
    instrument :create
    GitHub.dogstats.increment("deployment", tags: ["action:create"])
  end

  def trigger_issue_deployed_events
    pull_requests.each do |pull_request|
      pull_request.issue.create_deployed_event(self)
    end
  end

  def destroy_issue_events
    return unless GitHub.flipper[:destroy_deployment_issue_events].enabled?(repository)

    issue_ids = pull_requests.includes(:issue).map(&:issue).map(&:id)
    IssueEvent.where(issue_id: issue_ids, event: "deployed").joins(:issue_event_detail).where(issue_event_detail: { deployment_id: self.id }).destroy_all
  end

  def set_tree_oid
    return unless repository && tree_oid

    # the keys we write to `GitHub.kv` last for 1 week, so we will
    # dual write to the new `deployments.tree_oid` column for at least 1 week.
    self.tree_oid = tree_oid
  end

  memoize def tree_oid
    return nil unless repository && sha

    begin
      repository.commits.find(sha)&.tree_oid
    rescue GitRPC::Error => e
      nil
    end
  end
end
