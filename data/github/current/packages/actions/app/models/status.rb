# typed: false
# frozen_string_literal: true

# A Repository commit status.
#
# It's worth noting that the tree_oid and commit_oid fields store binary
# versions of the sha1 we get back from git. Which are 20 bytes long and will
# require special care while attempting to query them.
#
# For example - the following will pass through the hex sha1 of `master_oid`
# as-is to MySQL, which obviously isn't what we want against binary columns:
#   master_oid = repo.rpc.rev_parse("master")
#   repo.statuses.where(commit_oid: master_oid).first
#
# Instead you need to decode the string into its binary form before handing it
# to ActiveRecord:
#   master_sha1 = repo.rpc.rev_parse("master")
#   master_oid = GitHub::Hex.dump(master_sha1)
#   repo.statuses.where(commit_oid: master_oid).first
#
# This will ensure the query is using the binary (20 byte) version.
#
# See also repository/statuses_dependency.rb
class Status < ApplicationRecord::Domain::RepositoriesActionsChecks
  include Instrumentation::Model
  include GitHub::Validations

  EXPECTED = "expected".freeze
  ERROR    = "error".freeze
  FAILURE  = "failure".freeze
  PENDING  = "pending".freeze
  SUCCESS  = "success".freeze

  States = %W[expected error failure pending success].freeze

  MAX_PER_SHA_AND_CONTEXT = 900

  belongs_to :creator, class_name: "User"
  belongs_to :repository
  belongs_to :oauth_application
  alias_method :entity, :repository
  alias_method :async_entity, :async_repository

  alias_attribute :head_sha, :sha
  attribute :is_archived, :boolean, default: false

  after_commit :deliver_hook_event, on: :create
  after_commit :instrument_create, on: :create
  after_commit :notify_socket_subscribers, on: :create
  after_commit :update_pull_request_mergeable_state, on: :create
  after_commit :call_auto_merge_job_enqueuer, on: :create

  before_create :normalize_context

  serialize :commit_oid, coder: GitHub::Hex
  serialize :tree_oid, coder: GitHub::Hex

  before_save :fill_commit_and_tree_oid, if: :fill_commit_and_tree_oid?

  validate :validate_sha
  validate :limit_per_sha_and_context

  validates :context, :description, :target_url, unicode3: true
  validates_presence_of :sha, :creator_id, :repository_id, :context
  validates_inclusion_of :state, in: States - %W[expected]
  validates_length_of :description, maximum: 140, allow_nil: true
  validates_length_of :context, maximum: 255, allow_nil: false
  validates :target_url, bytesize: { maximum: MYSQL_TEXT_FIELD_LIMIT }, allow_nil: true, unicode: true
  validates_format_of :target_url, with: /\Ahttp/,
    on: :create, message: "must use http(s) scheme", allow_blank: true

  extend GitHub::Encoding
  force_utf8_encoding :target_url

  scope :before, lambda { |timestamp| where("created_at < ?", timestamp) }

  extend GitHub::Encoding
  force_utf8_encoding :target_url

  # Public: Specifies a stable sort order for Statuses. Use with
  # Enumerable#sort_by.
  #
  # It first puts a placeholder value for `number`, because statuses don't have `number`
  # Sorts first by state, then by context, then by id (to break any ties).
  def sort_order
    [CheckRun::MAX_NUMBER_VALUE, StatusCheckConfig::STATE_SORT_ORDER[self.state], context, id]
  end

  # Internal: validate the Status is created with a valid SHA.
  def validate_sha
    if !GitRPC::Util.valid_full_oid?(sha)
      errors.add(:sha, "must be a 40 character SHA1")
    end
  end

  # Internal: used to fill the commit_oid and tree_oid fields
  # Filling commit_oid here is temporary and should go away once we've fully
  # transitioned off of `sha`
  def fill_commit_and_tree_oid
    self.commit_oid = self.sha
    self.tree_oid = repository.commits.find(self.sha).tree_oid

    # Make sure we don't halt the callback chain before save
    true
  end

  # Internal: Returns true if commit_oid or tree_oid need to be set, or false.
  def fill_commit_and_tree_oid?
    !commit_oid? || !tree_oid?
  end

  # Internal: validate that users aren't creating a ridiculous number of Status
  # objects per sha.  This normally only happens due to bugs in client scripts.
  def limit_per_sha_and_context
    count = if sha && repository&.id && context
      GitHub.dogstats.time "status", tags: ["action:limit_per_sha_and_context_query"] do
        Statuses::Service.count_per_sha_and_context(repo_id: repository.id, sha: sha, context: context)
      end
    else
      0
    end
    if count >= MAX_PER_SHA_AND_CONTEXT
      GitHub.dogstats.increment "status", tags: ["action:limit_per_sha_and_context", "error:exceeds_limit_per_sha_and_context"]
      errors.add :base, "This SHA and context has reached the maximum number of statuses."
    end
  end

  # Public - check if the state is 'success'
  #
  # Returns true if the state is 'success', otherwise it returns false.
  def succeeded?
    state == "success"
  end
  alias_method :successful?, :succeeded?

  # Public - check if the state is 'pending'
  #
  # Returns Boolean
  def pending?
    state == "pending"
  end

  # Public - check if the status failed or errored. We don't collapse the statuses
  #          section if either is the case
  #
  # Returns a Boolean
  def failed_or_errored?
    state == "failure" || state == "error"
  end
  alias_method :failed?, :failed_or_errored?


  # Find all branches containing the status sha.
  #
  # Returns an Array of String branch names
  def branches
    return @branches if defined?(@branches)

    @branches = repository.rpc.branch_contains(sha)

    # Always return the default branch first, if it exists
    if @branches.delete(repository.default_branch)
      @branches.unshift(repository.default_branch)
    end

    @branches
  rescue GitRPC::Error
    []
  end

  # Return the commit that this status references
  #
  # Returns a Commit
  def commit
    @commit ||= repository.commits.find(sha)
  end

  # Public: Is this Status required for a pull request?
  def required_for_pull_request?(pull)
    async_required_for_pull_request?(pull).sync
  end

  def async_required_for_pull_request?(pull)
    return Promise.resolve(false) unless policy_evaluator = pull.base_branch_rule_evaluator
    return Promise.resolve(false) unless policy_evaluator.required_status_checks_enabled?

    policy_evaluator.async_has_required_status_check?(context)
  end

  # Internal: Do the actual WebSocket notification
  def notify_socket_subscribers
    data = {
      timestamp: created_at,
      wait: default_live_updates_wait,
      reason: "status ##{id} #{state} created",
    }
    # Notify associated commit channel that the status has changed
    channel = GitHub::WebSocket::Channels.commit(repository, sha)
    GitHub::WebSocket.notify_repository_channel(repository, channel, data)
  end

  # For those times when you want the status just prior to this one.
  #
  # Returns a Status or nil.
  def previous_status
    return @previous_status if defined? @previous_status

    @previous_status = Statuses::Service.previous_status(repo_id: repository_id, sha: sha, status_id: self.id, context: context)
  end

  # Returns the previous status state.
  def previous_state
    previous_status.nil? ? nil : previous_status.state
  end

  # Internal: Update the search document for each pull request associated with
  # the commit SHA. We only want to perform this update if the state is
  # different than the previous state.
  #
  # Returns true.
  def update_pull_request_mergeable_state
    return true unless state != previous_state

    related_pull_requests.each { |pull_request| pull_request.synchronize_search_index }

    true
  end

  def related_pull_requests
    return @related_pull_requests if defined?(@related_pull_requests)
    @related_pull_requests = PullRequest.where(repository_id: repository_id, head_sha: sha).limit(GitHub.duplicate_head_sha_limit)
  end

  def application
    oauth_application
  end

  # Internal: if the status was created by a Bot, what is the Integration
  # behind that Bot.
  #
  # Returns an Integration or nil
  def integration
    return nil unless creator.is_a?(Bot)
    creator.integration
  end

  # Internal: if the status was created by a Bot, what is the Integration ID
  # behind that Bot.
  #
  # Returns an Integration ID or nil
  def integration_id
    return nil unless creator.is_a?(Bot)
    creator.integration&.id
  end

  # Statuses are immutable.
  # We create a new Status with the same context when the state changes.
  # This method is so that we can have a unified API for check runs and
  # statuses for the PR timeline, PR view, and commit view.
  def state_changed_at
    created_at
  end

  # The duration is unknown for statuses.
  # We don't display it.
  def duration_in_seconds
    0
  end

  def platform_type_name
    "StatusContext"
  end

  # For compatibility with checks
  def contextual_name
    context
  end

  # If the feature flag is enabled for auto-merge, put PR's in the queue
  def call_auto_merge_job_enqueuer
    return unless succeeded?
    related_pull_requests.each do |pull|
      pull.enqueue_auto_merge_job_if_enabled
    end
  end

  private

  def deliver_hook_event
    return if spammy_user_acting_outside_own_repos?

    event_payload = {
      event_prefix => self,
      :triggered_at => Time.now,
    }

    ActiveRecord::Base.connected_to(role: :reading) do
      event = Hook::Event::StatusEvent.new(event_payload)
      delivery_system = Hook::DeliverySystem.new(event)
      delivery_system.generate_hookshot_payloads
      delivery_system&.deliver_later
    end
  end

  def instrument_create
    GlobalInstrumenter.instrument("repository.commit_status", { status: self }) unless GitHub.enterprise?
    instrument :created, { id: self.id, state: self.state, repository_id: repository_id, sha: sha }
  end

  def creator_allowed?
    repository.permit?(creator, :write)
  end

  def spammy_user_acting_outside_own_repos?
    creator.spammy? && !creator_allowed?
  end

  def normalize_context
    context.strip! if context.present?
  end
end
