# typed: true
# frozen_string_literal: true

class Milestone < ApplicationRecord::Domain::IssuesPullRequests
  include Issues::IMilestone
  include GitHub::UTF8
  include GitHub::UserContent
  include Instrumentation::Model
  include GitHub::Relay::GlobalIdentification
  include GitHub::Prioritizable::Context
  include Spam::Spammable
  include LegacyImportable
  include GitHub::Tracing
  include MemexProjectColumn::IDataSource
  include GitHub::BatchedScope
  include Repositories::BelongsToRepository
  include Milestone::PrioritizationDependency
  include GitHub::Memoizer

  States = %w(open closed)

  MAX_DESCRIPTION_LENGTH = 8 * 1024

  DUE_ON_MIN = Time.parse("1900-01-01T00:00:00Z")
  DUE_ON_MAX = Time.parse("2999-12-31T23:59:59Z")

  HYDRO_UPDATE_EVENT_ATTRIBUTES = %i(
    description
    due_on
    state
    title
  )

  HYDRO_UPDATE_EVENT_PREVIOUS_VALUE_ATTRIBUTES = HYDRO_UPDATE_EVENT_ATTRIBUTES.map do |name|
    "previous_#{name}".to_sym
  end

  has_many :issues, inverse_of: :milestone

  has_many :issue_priorities, inverse_of: :milestone, validate: false
  destroy_dependents_in_background :issue_priorities

  prioritizes :issues, with: :issue_priorities, conditions: "issues.state = 'open'"

  has_many :pull_request_issues,
    -> { where("pull_request_id IS NOT NULL") },
    class_name: "Issue"

  belongs_to_repository_via_domain inverse_of: :milestones
  delete_in_background_with :repository
  def entity = repository
  def async_entity = async_repository

  belongs_to :created_by, class_name: "User"

  setup_spammable(:created_by)

  validates_uniqueness_of :title, scope: :repository_id, case_sensitive: true
  validates_presence_of   :title
  validates_presence_of   :repository_id
  validates_presence_of   :created_by_id
  validates_inclusion_of  :state, in: States
  validates_length_of     :title, maximum: 255
  validate :ensure_creator_is_not_blocked, on: :create
  validates :description, :body, :title, bytesize: { maximum: MYSQL_UNICODE_BLOB_LIMIT },
    unicode: true, allow_blank: true, allow_nil: true

  validates :due_date, inclusion: { in: (DUE_ON_MIN..DUE_ON_MAX), message: "must be between year 1900 and 2999" },
    allow_nil: true

  before_validation :set_default_state, on: :create
  before_destroy :instrument_delete # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  before_save  :set_closed_at # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_create :set_number! # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_create, on: :create # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_closed_or_opened, on: :update # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_update, on: :update # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_hydro_update_event, on: :update, if: :should_instrument_hydro_update_event? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_hydro_delete_event, on: :destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_commit :queue_webhook_delivery, on: :destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :nullify_milestone_id_references, on: :destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_save :update_issues # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  scope :open_milestones,   -> { where(state: "open") }
  scope :closed_milestones, -> { where(state: "closed") }

  scope :sorted_by, -> (order_str, direction) {
    opts = { order: "milestones.updated_at DESC" }

    if !order_str.blank?
      case order_str
      when "due_date", "due_on"
        opts[:order] = "milestones.due_on"
      when "completeness"
        opts[:order] = "(milestones.closed_issue_count / (milestones.open_issue_count+milestones.closed_issue_count))"
      when "count"
        opts[:order] = "milestones.open_issue_count + milestones.closed_issue_count"
      when "created_at"
        opts[:order] = "milestones.created_at"
      when "number"
        opts[:order] = "milestones.number"
      when "title"
        opts[:order] = "milestones.title"
      else
        opts[:order] = "milestones.updated_at"
      end
      opts[:order] += (direction == "asc" ? " ASC" : " DESC")
    end

    order(Arel.sql(opts[:order])).order("milestones.id #{direction == "asc" ? "ASC" : "DESC"}")
  }

  scope :sorted_by_state, -> (states = []) {
    return all if states.empty?

    sanitized_states = states.map { |state| Repository.connection.quote(state) }
    case_statement = "CASE #{sanitized_states.each_with_index.map { |state, index| "WHEN state = #{state} THEN #{index}" }.join(' ')} ELSE #{sanitized_states.length} END"

    order(Arel.sql(case_statement))
  }

  trace_method :prioritize_dependent!, span_attribute_extractor: -> (context, *args, **kwargs) { context.trace_tags(*args, **kwargs) }

  def pull_requests
    pull_request_issues.all.map { |issue| issue.pull_request }
  end

  def open_pull_requests
    pull_request_issues.open_issues.map { |issue| issue.pull_request }
  end

  def closed_pull_requests
    pull_request_issues.closed_issues.map { |issue| issue.pull_request }
  end

  def open_issues
    issues.open_issues
  end

  def closed_issues
    issues.closed_issues
  end

  def open_issues_count
    issues.without_pull_requests.count
  end

  def open_pull_requests_count
    pull_request_issues.open_issues.count
  end

  def body
    description
  end

  attribute :description, StringFromBinary.new
  attribute :title, StringFromBinary.new

  def user_id
    user.id
  end

  def user
    created_by
  end

  def last_modified_at
    @last_modified_at ||= T.unsafe(self).last_modified_with :created_by
  end

  # we have to do this until Rails 3
  def labels
    Label.for_milestone(self.id)
  end

  def to_param
    number.to_s
  end

  ############################################################################

  def progress_percentage
    open_issue_count = T.unsafe(self).open_issue_count
    closed_issue_count = T.unsafe(self).closed_issue_count

    total = (open_issue_count + closed_issue_count).to_f
    total_closed = self.closed_issue_count.to_f
    total == 0 ? 0 : (total_closed / total) * 100
  end

  # Private: If the title of the milestone has changed, then we need to
  # update the search records for all the issues and pull requests associated
  # with this milestone. Called via an after_save.
  def update_issues
    return self unless saved_change_to_title?
    Issues::ReindexIssuesForAssociationJob.enqueue(:milestone, self.id)

    self
  end

  # Absolute permalink URL for this milestone.
  def url(allow_temporary_subdomains: true)
    scheme_and_domain = if allow_temporary_subdomains
      GitHub.url
    else
      domain = GitHub.dynamic_lab? ? GitHub.host_domain : GitHub.host_name
      "#{GitHub.scheme}://#{domain}"
    end

    "%s/%s/milestones/%s" % [
      scheme_and_domain,
      T.must(repository).name_with_display_owner,
      UrlHelper.escape_path(title),
    ]
  end
  alias_method :permalink, :url

  # Repository path for the milestone without a domain
  sig { returns(String) }
  def repository_path
    "/%s/milestone/%s" % [T.must(repository).name_with_display_owner, number]
  end

  # Determines whether the milestone is past due based on the viewer's
  # localized time. This may result in a milestone being past_due? in one
  # timezone (where it's the next calendar date) while it's not in another
  # timezone where it's still the due date.
  #
  # Returns a boolean
  def past_due?
    return false unless due_date

    Date.current > due_date
  end

  # The actual due_on timestamp is stored as midnight UTC. We ensure it's still
  # UTC before converting it to a date so that it is consistent for all viewers
  # regardless of timezone.
  #
  # Returns a Date or nil
  def due_date
    T.unsafe(self).due_on.utc.to_date if due_on
  end

  def due_on=(val)
    date =
      if val.present?
        parsed_date(val)
      else
        nil
      end
    super(date)
  end

  # Public: Preserve the actor performing the change, toggle this Milestone to
  # the opposite state, and immediately persist
  def toggle_state!
    self.update! state: next_state
  end

  # Public: What is the next valid state for this Milestone?
  def next_state
    closed? ? "open" : "closed"
  end

  # Public: Returns truthy if this Milestone is closed
  def closed?
    self.state == "closed"
  end

  # When was this milestone closed?
  # Returns a Date if it's closed, nil if not
  def closed_at
    return if open?

    read_attribute(:closed_at) || updated_at
  end

  def open?
    self.state == "open"
  end

  # Public: Whether the given user can see this milestone.
  def readable_by?(actor)
    return false unless repository = self.repository
    T.cast(repository, Repository).readable_by?(actor) # rubocop:disable GitHub/AvoidCast
  end

  # Public: Indicates if a milestone can be closed by an actor.
  #
  # actor - The User to check.
  #
  # Returns a Promise<Boolean>.
  def async_closable_by?(actor)
    return Promise.resolve(false) unless actor.present?

    async_repository.then do |repo|
      next false unless repo.present?
      repo.async_writable_by?(actor)
    end
  end

  # If a user can close a milestone, they can also reopen it.
  alias :async_reopenable_by? :async_closable_by?

  def notify_subscribers
    channel = GitHub::WebSocket::Channels.milestone_prioritized(self)

    GitHub::WebSocket.notify_repository_channel(repository, channel, {
      timestamp: updated_at.to_i,
      wait: default_live_updates_wait,
      client_uid: GitHub.context[:client_uid],
   })
  end

  # Finds and sets the next number in the sequence scoped by
  # repository_id.
  def set_number!
    ensure_sequence_exists

    next_sequence_number = Sequence.next sequence_context

    update_column(:number, next_sequence_number)
  end

  def sequence_type
    RepositoryMilestonesSequence
  end

  # The user who performed the action as set in the GitHub request context. If the context doesn't
  # contain an actor, fallback to the ghost user.
  def actor
    @actor ||= (User.find_by(id: GitHub.context[:actor_id]) || User.ghost)
  end

  def event_prefix
    :milestone
  end

  def event_payload(action)
    event_actor = (action == :created ? created_by : actor)
    {
      milestone_id: id,
      actor_id: event_actor.try(:id),
    }
  end

  def instrument_create
    GitHub.instrument "milestone.create", event_payload(:created)
  end

  def instrument_closed_or_opened
    return unless previous_changes["state"].present?

    if state == "closed"
      GitHub.instrument "milestone.close", event_payload(:closed)
    elsif state == "open"
      GitHub.instrument "milestone.open", event_payload(:opened)
    end
  end

  def instrument_update
    return if previous_changes.empty? || previous_changes["state"].present?

    changes_payload = {}.tap do |hash|
      hash[:old_description] = previous_changes["description"].first if previous_changes["description"].present?
      hash[:old_due_on] = previous_changes["due_on"].first if previous_changes["due_on"].present?
      hash[:old_title] = previous_changes["title"].first if previous_changes["title"].present?
    end

    return if changes_payload.empty?

    GitHub.instrument "milestone.update", event_payload(:edited).merge(changes: changes_payload)
  end

  # Public: Queues up the `deleted` milestone event if a milestone is deleted.
  #
  # We *do not* queue a `deleted` event if the repository owner is deleted. It
  # means, most likely, that the user has deleted itself, and this event is
  # firing as part of the callback destruction process. The webhook is eventually
  # fired by `DestroyUserCallbacks#prepare_demilestoned_events`; see also
  # https://git.io/v1L1o for more information.
  #
  # Returns nothing.
  def instrument_delete
    if actor&.spammy? || repo_owner_destroyed?
      @delivery_system = nil
      return
    end

    event = Hook::Event::MilestoneEvent.new(milestone_id: self.id, action: :deleted, actor_id: actor.try(:id), triggered_at: Time.now)
    @delivery_system = Hook::DeliverySystem.new(event)
    @delivery_system.generate_hookshot_payloads
  end

  def queue_webhook_delivery
    return if repo_owner_destroyed?
    raise "`generate_webhook_payload' must be called before `queue_webhook_delivery'" unless defined?(@delivery_system)
    @delivery_system&.deliver_later
  end

  def issues_to_render_for_viewer(viewer, state: :open, page: 1, per_page: GitHub::Prioritizable::MAXIMUM_PRIORITIZABLE_ITEM_COUNT)
    # Load the issues that match the specified state
    issues_to_render =
      if state == :open
        prioritized_issues
      else
        issues.closed_issues.reorder("closed_at DESC")
      end

    # Paginate the remaining issues.
    issues_to_render = issues_to_render.paginate(page: page, per_page: per_page)

    # Prefill the issues' associations.
    IssuePrefiller.prefill(issues_to_render, repository: repository)

    # Prefill status checks.
    pulls = issues_to_render.map(&:pull_request).compact
    if pulls.any?
      GitHub::PrefillAssociations.prefill_batch_method(pulls, :base_branch_rule_evaluator)
      PullRequest.attach_statuses(repository, pulls)
    end

    if viewer.present?
      # Prefill the issues' read statuses.
      read_issues = Issue.read_for(viewer, issues_to_render)
      issues_to_render.each do |issue|
        issue.read_by_current_user = read_issues.include?(issue.id)
      end
    end

    issues_to_render
  end

  def memex_denormalized_value
    {
      type: self.class.name,
      value: memex_project_column_value.to_hash
    }
  end

  sig { override.returns(MemexProjectColumnValue::SerializableValue) }
  memoize def memex_project_column_value
    user_login, repo_name = T.must(repository).name_with_display_owner.split("/")
    MemexProjectColumnValue::Milestone.new(
      id: id,
      number: number,
      state: state,
      title: title,
      url: T.unsafe(GitHub::Application).routes.url_helpers.milestone_path(user_id: user_login, repository: repo_name, number: number),
      due_date: due_date,
      repo_name_with_owner: T.must(repository).name_with_display_owner,
    )
  end

  def memex_suggestion_hash(selected:)
    memex_project_column_value.to_hash.merge(selected: selected)
  end

  def async_target_for_conditional_access
    async_repository.then { |x| T.must(x).async_target_for_conditional_access }
  end

  protected

  def set_default_state
    self.state = "open" if self.state.blank?
  end

  # If this milestone was just closed set closed_at to the time.
  # before_save callback
  def set_closed_at
    return unless state_changed?

    if state == "closed"
      self.closed_at = Time.current
    elsif state == "open"
      self.closed_at = nil
    end

    true
  end

  # Implement GitHub::Prioritizable::Context#rebalance_job_class
  def rebalance_job_class(association: nil)
    RebalanceMilestoneJob
  end

  private

  def nullify_milestone_id_references
    NullifyMilestoneIdReferencesJob.perform_later(
      id,
      title,
      GitHub.context[:actor_id],
      create_demilestoned_events: !repo_owner_destroyed?,
      repository_id: repository_id
    )
  end

  def should_instrument_hydro_update_event?
    hydro_update_event_attribute_changes.present?
  end

  def instrument_hydro_update_event
    GlobalInstrumenter.instrument("milestone.update", hydro_update_event_payload)
  end

  def instrument_hydro_delete_event
    GlobalInstrumenter.instrument("milestone.delete", base_hydro_event_payload)
  end

  def hydro_update_event_attribute_changes
    previous_changes.keys & HYDRO_UPDATE_EVENT_ATTRIBUTES.map(&:to_s)
  end

  def hydro_update_event_payload
    previous_attribute_values = HYDRO_UPDATE_EVENT_ATTRIBUTES.reduce({}) do |memo, attribute|
      memo["previous_#{attribute}".to_sym] = if previous_changes[attribute].present?
        previous_changes[attribute].first
      else
        public_send(attribute)
      end
      memo
    end

    base_hydro_event_payload.merge(previous_attribute_values)
  end

  def base_hydro_event_payload
    {
      actor: actor,
      milestone: self
    }
  end

  def parsed_date(text)
    Date.strptime(text.to_s, "%Y-%m-%d").to_time(:utc)
  rescue ArgumentError
    nil
  end

  # This is a set of checks against the milestone's parent repo, to determine
  # if it should be removed from the index.
  #
  # Some reasons the parent repo might not be searchable:
  #   - repo not routed on the file servers
  #   - repo's user is a spammer
  #   - disabled by an admin
  #   - no associated issues
  #
  # Return `true` if we should add the milestone to the search index; return
  # `false` if we should not.
  #
  def parent_repo_is_searchable?
    return false unless repository = self.repository
    return false unless repository.active?

    # If the parent repo has no issues
    return false if !repository.has_issues?

    # When the parent repo user is spammy
    return false if T.unsafe(repository).spammy?

    # When the parent repo has been disabled for any reason
    return false if repository.disabled?

    # When the parent repo has been disabled for DMCA and similar reasons
    return false if T.cast(repository, Repository).access.disabled? # rubocop:disable GitHub/AvoidCast

    true
  end

  def ensure_creator_is_not_blocked
    if user && T.cast(repository, T.nilable(Repository))&.owner_blocking?(user) # rubocop:disable GitHub/AvoidCast
      errors.add :user, "is blocked"
    end
  end

  # Internal.
  def max_textile_id
    GitHub.max_textile_milestone_id
  end

  # If the owner is nil, the repo is being destroyed by a user that no longer
  # exists. We'll queue dependent milestone events in the destroy_user_callback
  # sequence
  def repo_owner_destroyed?
    entity.owner.nil?
  end

  def ensure_sequence_exists
    if !Sequence.exists? sequence_context
      Sequence.create sequence_context
    end
  end

  def sequence_context
    self
  end
end
