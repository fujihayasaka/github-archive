# typed: true
# frozen_string_literal: true

# Records various events that occur around an Issue or Pull Request. This is
# useful both for display on issue/pull request information pages and also to
# determine who should be notified of comments.
#
# Attributes
#   integer  :issue_id
#   integer  :actor_id
#   integer  :repository_id
#   string   :event
#   string   :commit_id
#   integer  :commit_repository_id
#   integer  :referencing_issue_id
#   integer  :performed_by_integration_id
#   datetime :created_at
#   tinyint  :user_hidden
#
# The issue and repository attributes identify the issue the event applies to
# and the repository that owns the issue. The actor is always the user that
# generated the event. The commit_id and commit_repository are only applicable
# to some events but identify the commit SHA1 and repository where that commit
# was made.
#
# Events
#   closed       - The issue was closed by the actor. When the commit_id is
#                  present, it identifies the commit that closed the issue using
#                  "closes / fixes #NN" syntax.
#   reopened     - The issue was reopened by the actor.
#   subscribed   - The actor subscribed to receive notifications for an issue.
#   unsubscribed - The actor unsubscribed from notifications for an issue.
#   merged       - The issue was merged by the actor. The commit_id attribute
#                  is the SHA1 of the HEAD commit that was merged. The
#                  commit_repository is always the same as the main repository in
#                  this case.
#   referenced   - The issue was referenced from a commit message. The
#                  commit_id attribute is the commit SHA1 of where that happened
#                  and the commit_repository is where that commit was pushed.
#   mentioned    - The actor was @mentioned in an issue body.
#   assigned     - The issue was assigned to the actor. The user who did the
#                  assignment is available via `subject`.
#   unassigned   - The issue was unassigned to the actor. The user who did the
#                  unassignment is available via `subject`.
#   review_requested - Review was requested of the `subject`. The user who did the
#                  request is available via `actor`.
#   review_request_removed - The review was unrequesed of the actor. The user who did the
#                  request_remove is available via `subject`.
#   labeled      - A label was added to the issue. The label name is accessible
#                  as `label_name`, the colors as `label_color` and
#                  `label_text_color`.
#   unlabeled    - A label was removed from the issue. The label name is
#                  accessible as `label_name`, the colors as `label_color` and
#                  `label_text_color`.
#   milestoned   - The issue had a milestone added to it. The id of the
#                  milestone is accessible as `milestone_id`, and the title of the
#                  milestone is accessible as `milestone_title`.
#   demilestoned - The issue had a milestone removed from it. The id of the
#                  milestone is accessible as `milestone_id`, and the title of the
#                  milestone is accessible as `milestone_title`.
#   renamed      - The issue's title was changed. The title was `title_was`,
#                  renamed to `title_is`, and the user id of who renamed it is
#                  `actor_id`.
#   locked       - The issue was locked by the actor.
#   unlocked     - The issue was unlocked by the actor.
#   connected    - The issue was connected to an issue or PR via the `subject`.
#   disconnected - The issue was disconnected from an issue or PR via the `subject`.
#   deployed     - The pull request was deployed by the actor.
#   deployment_environment_changed - The pull request deployment environment was changed.
#   head_ref_deleted  - The head branch was deleted by the actor.
#   head_ref_restored - The head branch was restored by the actor to the last known commit.
#   base_ref_force_pushed - The base branch was force pushed by the actor. The
#                           before and after values are available as `before_commit_oid`
#                           and `after_commit_oid`. The fully qualified ref name that was
#                           force pushed is available as `ref`.
#   head_ref_force_pushed - Same as base_ref_force_pushed, but about the head branch.
#   added_to_project         - The issue or PR was added to a project.
#   moved_columns_in_project - The issue or PR was moved between columns in a project.
#   removed_from_project     - The issue or PR was removed from the project.
#   converted_note_to_issue  - The issue was created by converting a note in a project to an issue.
#   marked_as_duplicate      - The issue was marked as a duplicate of another issue.
#   unmarked_as_duplicate    - The issue was marked as not being a duplicate of another issue.
#   user_blocked             - A user was blocked from the org through one of their comments on this issue
#   converted_to_discussion  - The issue was converted to a discussion.
#                              The new discussion is stored as the `subject`.
#   added_to_merge_queue     - The PR was added to the merge queue. The actor is the enqueuer and the subject
#                              is the author of the PR.
#   removed_from_merge_queue - The PR was removed from the merge queue. The actor is the dequeuer and the subject
#                              is the author that opened the PR.
#
# The closed, merged, and reopened events are useful for display purposes and
# are shown inline on the Pull Request Discussion page and Issues show page.
# The mentioned and subscribed types are useful for notification controls and
# may be used to include those users in the "people participating" display area.
class IssueEvent < ApplicationRecord::Domain::IssuesPullRequests
  include Instrumentation::Model
  include GitHub::Relay::GlobalIdentification
  include GitHub::UTF8
  include PreloadableAttributes
  include LegacyImportable
  include Coders::CodableColumn

  UNMARK_AS_DUPLICATE_URI_TEMPLATE = Addressable::Template.new("/{+nwo}/issues/{number}/duplicate").freeze
  GITOBJECT_TIMEOUT = 5

  attr_preloadable :can_view_actor, :dismissal_message, :commit, :subject, :direct_reference, :actor, :deployment, :deployment_status, :review_request
  attr_accessor :skip_hydro_event_instrumentation, :issue_transfer

  # Used to determine if these events should also be sent to hydro
  # see `instrument_event_for_hydro`
  HYDRO_EVENTS = %w(
    closed
    merged
    converted_to_discussion
    reopened
    milestoned
    demilestoned
    labeled
    unlabeled
    assigned
    unassigned
    review_requested
  ).freeze

  # These events change the state of a rollup summary.
  # see `update_summary_state`
  UPDATE_SUMMARY_STATE_EVENTS = %w(
    closed
    converted_to_discussion
    reopened
    merged
  ).freeze

  ISSUE_TIMELINE_GRAPHQL_SUBSCRIPTION_EVENTS = %w(
    closed
    reopened
    locked
    unlocked
    pinned
    unpinned
    labeled
    unlabeled
    renamed
    assigned
    unassigned
    comment_deleted
    user_blocked
    milestoned
    demilestoned
    referenced
    connected
    transferred
    converted_note_to_issue
    disconnected
    marked_as_duplicate
    unmarked_as_duplicate
    converted_to_discussion
  ).freeze

  # After any issue event of the following kinds are created the
  # user is subscribed to the issue, and notified in some cases.
  # see `auto_subscribe` and `notify_for_event?
  NOTIFICATION_EVENTS = %w(
    assigned
    closed
    converted_to_discussion
    merged
    ready_for_review
    reopened
    review_requested
    added_to_merge_queue
    removed_from_merge_queue
  ).freeze

  # Force push events is a staff-shipped feature.
  # This constant defines the different events triggered
  # when a user with the feature enabled force-pushed on a PR.
  FORCE_PUSH_EVENTS = %w(
    base_ref_force_pushed
    head_ref_force_pushed
  ).freeze

  PULL_REQUEST_EVENTS = %w(
    merged
    head_ref_deleted
    head_ref_restored
    base_ref_changed
    base_ref_deleted
    automatic_base_change_succeeded
    automatic_base_change_failed
    ready_for_review
    convert_to_draft
    review_dismissed
    review_requested
    review_request_removed
    added_to_merge_queue
    removed_from_merge_queue
    auto_merge_enabled
    auto_rebase_enabled
    auto_squash_enabled
    auto_merge_disabled
  ).freeze

  PROJECT_EVENTS = %w(
    added_to_project
    moved_columns_in_project
    removed_from_project
    converted_note_to_issue
  ).freeze

  PROJECT_V2_EVENTS = %w(
    added_to_project_v2
    converted_from_draft
    removed_from_project_v2
    project_v2_item_status_changed
  ).freeze

  PROTECTED_EVENTS = %w(
    comment_deleted
    locked
    unlocked
  ).freeze

  VALID_EVENTS = %w(
    closed
    reopened
    merged
    mentioned
    subscribed
    unsubscribed
    referenced
    labeled
    unlabeled
    assigned
    unassigned
    milestoned
    demilestoned
    locked
    unlocked
    renamed
    deployed
    deployment_environment_changed
    head_ref_deleted
    head_ref_restored
    base_ref_force_pushed
    head_ref_force_pushed
    base_ref_changed
    base_ref_deleted
    automatic_base_change_succeeded
    automatic_base_change_failed
    added_to_merge_queue
    removed_from_merge_queue
    ready_for_review
    review_dismissed
    review_requested
    review_request_removed
    convert_to_draft
    added_to_project
    moved_columns_in_project
    removed_from_project
    converted_note_to_issue
    comment_deleted
    marked_as_duplicate
    unmarked_as_duplicate
    transferred
    pinned
    unpinned
    user_blocked
    connected
    disconnected
    auto_merge_enabled
    auto_rebase_enabled
    auto_squash_enabled
    auto_merge_disabled
    converted_to_discussion
    added_to_project_v2
    converted_from_draft
    removed_from_project_v2
    project_v2_item_status_changed
  ).freeze

  # Used in #label_events_for scope
  # Filtered out of simple events as event details need to be validated when querying
  LABEL_EVENTS = %w(labeled unlabeled).freeze

  # Event types that require the viewer have permission to view event subject
  CROSS_ISSUE_SUBJECT_EVENTS = %w(
    marked_as_duplicate
    unmarked_as_duplicate
    connected
    disconnected
  ).freeze

  INVISIBLE_EVENTS = %w(mentioned subscribed unsubscribed).freeze

  ALLOWLISTED_SPAMMY_TIMELINE_EVENTS = %w(
    merged
  )

  # Subset of valid events displayed in the web UI.
  # Used in the #visible scope.
  VISIBLE_EVENTS = (VALID_EVENTS - INVISIBLE_EVENTS).freeze

  # Subset of valid events for simple event scope
  SIMPLE_EVENTS = (
    VALID_EVENTS -
    PULL_REQUEST_EVENTS -
    FORCE_PUSH_EVENTS -
    PROJECT_EVENTS -
    LABEL_EVENTS -
    CROSS_ISSUE_SUBJECT_EVENTS -
    %w(referenced deployed deployment_environment_changed)
  ).freeze

  # Subset of simple events used for the list of events displayed in the web UI
  SIMPLE_VISIBLE_EVENTS = (SIMPLE_EVENTS - INVISIBLE_EVENTS).freeze

  # The valid `subject` classes, which is stored on the `IssueEventDetail`
  # record for this event.
  VALID_SUBJECTS = %w(
    Bot
    Discussion
    Issue
    Mannequin
    Project
    PullRequestReviewPoint
    Repository
    Team
    User
  )

  # The Issue object the event occurred on. The Repository is also provided as
  # an attribute for fast lookups and searches by repository.
  belongs_to :issue
  belongs_to :repository
  def entity = repository
  def async_entity = async_repository
  def notifications_list = repository

  # The User the event applies to.
  belongs_to :actor, class_name: "User"

  # The repository where the commit was made for referenced events.
  belongs_to :commit_repository, class_name: "Repository"

  # The issue that made the reference for issue referenced events.
  belongs_to :referencing_issue, class_name: "Issue"

  # The integration that was used when the actor triggered this event.
  # rubocop:todo Rails/InverseOf
  belongs_to :performed_via_integration,
    foreign_key: :performed_by_integration_id,
    class_name: "Integration"
  # rubocop:enable Rails/InverseOf

  # All this stuff is required
  validates_presence_of :actor, :event
  validates_presence_of :repository_id, on: :create

  # Supported event types.
  validates_inclusion_of :event, in: VALID_EVENTS

  validate :subject_must_be_valid, on: :create
  validate :issue_or_commit_id

  # Keep the repository close.
  before_validation :assign_issue_repository, on: :create

  # Trigger dashboard/newsfeed events.
  after_commit :instrument_event, on: :create, unless: -> { T.bind(self, IssueEvent); skip_notifications? } # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_event_for_hydro, on: :create, unless: -> { T.bind(self, IssueEvent); skip_notifications? } # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  # Trigger notifications.
  after_commit :update_summary_state, on: :create, unless: -> { T.bind(self, IssueEvent); skip_notifications? } # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :subscribe_and_notify, on: :create, unless: -> { T.bind(self, IssueEvent); skip_notifications? } # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  # Temporarily track associated record for newsfeed events
  attr_accessor :assignee

  batch_method(:milestone) do |events|
    repo = events.first.repository

    milestones_by_id = T.let(nil, T.nilable(T::Hash[Integer, Milestone]))
    milestones_by_title = T.let(nil, T.nilable(T::Hash[String, Milestone]))

    events.index_with do |event|
      if !event.milestoned? && !event.demilestoned?
        nil
      elsif event.milestone_id
        if milestones_by_id.nil?
          milestone_ids = events.map(&:milestone_id).compact.uniq
          milestones_by_id = repo.milestones.where(id: milestone_ids).index_by(&:id)
        end

        milestones_by_id[event.milestone_id]
      else
        # legacy events might not have milestone_id set.
        if milestones_by_title.nil?
          milestone_titles = events.map(&:milestone_title).compact.uniq
          milestones_by_title = repo.milestones.where(title: milestone_titles).index_by(&:title)
        end

        milestones_by_title[event.milestone_title]
      end
    end
  end

  destroy_dependents_in_background :issue_event_author
  has_one :issue_event_author
  has_one :author, through: :issue_event_author, class_name: "User", disable_joins: true

  # The details of this issue event live in a separate table
  has_one :issue_event_detail, autosave: true, dependent: :delete

  default_scope { includes(:issue_event_detail) }

  def issue_transfer?
    defined?(issue_transfer) && issue_transfer == true
  end

  # Make sure an associated event detail instance is built
  def issue_event_detail
    populate_event_detail_from_serialized_attributes(
      super || build_issue_event_detail,
    )
  end

  # If this record had serialized_attributes use them to populate the
  # associated IssueEventDetail model attributes.
  # TODO: Remove this when the `issue_event.raw_data` column has been removed
  # (post data transition)
  def populate_event_detail_from_serialized_attributes(detail)
    if has_attribute?(:raw_data)
      raw_data.to_h.each do |key, value|
        # since encoding can be off inside the 'raw_data' serialized attribute,
        # convert to utf8 if the value is a 'String'.
        value = utf8(value) if value&.is_a? String

        begin
          detail.method("#{key}=".to_sym).call(value)
        rescue NameError
          # Raw data contained an unknown attribute. Nothing to be done.
        end
      end
    end
    detail
  end

  delegate :label, :label=,
    :label_id, :label_id=,
    :label_name, :label_name=,
    :label_color, :label_color=,
    :label_text_color, :label_text_color=,
    :milestone_id, :milestone_id=,
    :milestone_title, :milestone_title=,
    :subject, :subject=,
    :subject_id, :subject_id=,
    :subject_type, :subject_type=,
    :title_was, :title_was=,
    :title_is, :title_is=,
    :deployment_id, :deployment_id=,
    :deployment_status_id, :deployment_status_id=,
    :ref, :ref=,
    :before_commit_oid, :before_commit_oid=,
    :after_commit_oid, :after_commit_oid=,
    :message, :message=,
    :pull_request_review_id, :pull_request_review_id=,
    :pull_request_review_state_was, :pull_request_review_state_was=,
    :review_request_id, :review_request_id=,
    :column_name, :column_name=, :column_name?,
    :previous_column_name, :previous_column_name=,
    :card_id, :card_id=,
    :performed_by_project_workflow_action_id, :performed_by_project_workflow_action_id=, :performed_by_project_workflow_action_id?,
    :lock_reason, :lock_reason=,
    :block_duration_days, :block_duration_days=,
    :state_reason, :state_reason=,
    :project_id, :project_id=,
    :project_status, :project_status=,
    :project_previous_status, :project_previous_status=,
    to: :issue_event_detail

  def automated? = T.unsafe(self).performed_by_project_workflow_action_id?

  # TODO: Remove this when the `raw_data` column has been removed from
  # the `issue_details` table.
  # This is only to keep GitHub::Migrator::Importer#import_model happy.
  serialize :raw_data, coder: Coders::Handler.new(Coders::IssueEventCoder, compressor: GitHub::ZPack)

  # Include all valid events.
  # Used in the issue timeline API.
  scope :valid, -> {
    preload(:actor).where(event: VALID_EVENTS).order("issue_events.id ASC")
  }

  # Include a subset of valid events typically displayed to users on timelines and whatnot.
  # Used in the web UI.
  scope :visible, -> {
    preload(:actor).where(event: VISIBLE_EVENTS).order("issue_events.id ASC")
  }

  # Excludes users referencing issues from other issues or commits.
  scope :participatory, -> {
    conditions = %w(
        closed
        reopened
        merged
        referenced
        assigned
        unassigned
        labeled
        unlabeled
        milestoned
        demilestoned
        deployed
        deployment_environment_changed
      )

    where("issue_events.referencing_issue_id IS NULL AND issue_events.commit_repository_id IS NULL and issue_events.event in (?)", conditions)
  }

  scope :closes,             -> { where(event: "closed").order("issue_events.id ASC") }
  scope :reopens,            -> { where(event: "reopened").order("issue_events.id ASC") }
  scope :merges,             -> { where(event: "merged").order("issue_events.id ASC") }
  scope :assigns,            -> { where(event: "assigned").order("issue_events.id ASC") }
  scope :unassigns,          -> { where(event: "unassigned").order("issue_events.id ASC") }
  scope :review_requests,    -> { where(event: "review_requested").order("issue_events.id ASC") }
  scope :review_request_removes,  -> { where(event: "review_request_removed").order("issue_events.id ASC") }
  scope :mentions,           -> { where(event: "mentioned").order("issue_events.id ASC") }
  scope :referenced,         -> { where(event: "referenced").order("issue_events.id ASC") }
  scope :labels,             -> { where(event: "labeled").order("issue_events.id ASC") }
  scope :unlabels,           -> { where(event: "unlabeled").order("issue_events.id ASC") }
  scope :connects,           -> { where(event: "connected").order("issue_events.id ASC") }
  scope :disconnects,        -> { where(event: "disconnected").order("issue_events.id ASC") }
  scope :milestones,         -> { where(event: "milestoned").order("issue_events.id ASC") }
  scope :demilestones,       -> { where(event: "demilestoned").order("issue_events.id ASC") }
  scope :renames,            -> { where(event: "renamed").order("issue_events.id ASC") }
  scope :locks,              -> { where(event: "locked").order("issue_events.id ASC") }
  scope :unlocks,            -> { where(event: "unlocked").order("issue_events.id ASC") }
  scope :deployments,        -> { where(event: "deployed").order("issue_events.id ASC") }
  scope :closes_and_reopens, -> { where(event: %w(closed reopened)).order("issue_events.id ASC") }
  scope :head_ref,           -> { where(event: %w(head_ref_deleted head_ref_restored)).order("issue_events.id ASC") }
  scope :force_pushes,       -> { where(event: FORCE_PUSH_EVENTS).order("issue_events.id ASC") }
  scope :subscribes,         -> { where(event: "subscribed").order("issue_events.id ASC") }
  scope :marked_as_duplicates, -> { where(event: "marked_as_duplicate").order("issue_events.id ASC") }
  scope :unmarked_as_duplicates, -> { where(event: "unmarked_as_duplicate").order("issue_events.id ASC") }
  scope :deployment_environment_changes, -> { where(event: "deployment_environment_changed").order("issue_events.id ASC") }

  scope :issues, -> {
    joins(:issue).where("issues.pull_request_id IS NULL").order("issue_events.id ASC")
  }

  scope :pull_requests, -> {
    joins(:issue).where("issues.pull_request_id IS NOT NULL").order("issue_events.id ASC")
  }

  scope :reference_types, -> {
    where("event in ('closed', 'referenced') AND commit_id IS NOT NULL").order("issue_events.id ASC")
  }

  scope :mentioned_users, lambda { |issue|
    select("distinct actor_id").left_joins(:issue_event_author)
      .where(
        "issue_events.event = 'mentioned' AND issue_events.issue_id = ? AND issue_events.repository_id = ? AND (issue_event_authors.user_hidden = 0 OR issue_event_authors.user_hidden IS NULL)",
        issue.id, issue.repository_id
      )
  }

  scope :summarized_events, -> {
    where("event in (?)", UPDATE_SUMMARY_STATE_EVENTS).order("issue_events.id ASC")
  }

  delegate :pull_request, to: :issue

  # Delegate subscription logic to the Issue, since Issue monkeypatches these
  # methods in order to create `subscribed` events.
  delegate :subscribe, :subscribe_all, to: :issue

  def self.column_to_platform_type_name(column_name)
    if column_name == "renamed"
      "RenamedTitleEvent"
    else
      "#{column_name.camelize}Event"
    end
  end

  def self.platform_type_name_to_column(platform_name)
    if platform_name == "RenamedTitleEvent"
      "renamed"
    else
      platform_name.chomp("Event").underscore
    end
  end

  def async_subject
    async_issue_event_detail.then(&:async_subject)
  end

  def async_state_reason
    async_issue_event_detail.then(&:state_reason)
  end

  def async_visible_subject(abilities)
    async_subject.then do |subject|
      next unless subject
      subject_type = Platform::Helpers::NodeIdentification.type_name_from_object(subject)
      abilities.typed_can_see?(subject_type, subject).then { |can_read| subject if can_read }
    end
  end

  batch_method(:visible_subject_for) do |issue_events, viewer|
    permission = Platform::Authorization::Permission.new(viewer: viewer, origin: Platform::ORIGIN_INTERNAL)
    results = Promise.all(issue_events.map { |issue_event| issue_event.async_visible_subject(permission) }).sync

    issue_events.zip(results).to_h
  end

  # The Commit associated with this issue event. Always available on merge
  # and referenced event types. Sometimes available on close events if the issue
  # was closed from a commit message.
  #
  # For reference events, the commit can originate from a fork of the repository
  # that owns the issue.
  #
  # Returns a Commit object when commit_id is set and the object exists in the
  # repository. Returns nil when no commit exists.
  def commit
    return @commit if defined?(@commit)
    @commit = async_commit.sync
  end
  attr_writer :commit

  def async_commit
    return Promise.resolve(nil) unless commit?
    return Promise.resolve(@commit) if defined?(@commit)

    Promise.all([
      async_commit_repository,
      async_repository]).then do |commit_repository, repository|

      repo = commit_repository || repository
      next unless repo

      Platform::Loaders::GitObject.load(repo, commit_id, expected_type: :commit, timeout: GITOBJECT_TIMEOUT).rescue do |error|
        if error && error.class == GitRPC::Timeout
          GitHub.dogstats.increment("issue_event.git_object.load.timeout")
          next nil
        else
          raise error
        end
      end
    end
  end

  def closer
    return @closer if defined?(@closer)
    @closer = async_closer.sync
  end

  # The object which triggered this close event.
  #
  # Returns a Commit, Pull Request, Memex Project, or Issue
  def async_closer
    return Promise.resolve(nil) unless close?
    # in the case of duplicate, the referencing issue is not the closer
    return Promise.resolve(nil) if state_reason == "duplicate"
    return async_commit if commit?

    return async_batch_memex_project if auto_close_workflow_automation?

    async_referencing_issue_or_pull_request
  end

  def async_referencing_issue_or_pull_request
    async_referencing_issue.then do |issue|
      async_issue_or_pull_request_for(issue)
    end
  end

  def auto_close_workflow_automation?
    close? && automated? && T.unsafe(self).column_name?
  end

  batch_method(:memex_project) do |events|
    memex_project_workflow_actions_by_id = T.let(nil, T.nilable(T::Hash[Integer, MemexProjectWorkflowAction]))

    events.index_with do |event|
      if !event.auto_close_workflow_automation?
        nil
      elsif event.performed_by_project_workflow_action_id
        memex_project_workflow_action_ids = events.map(&:performed_by_project_workflow_action_id).compact.uniq
        memex_project_workflow_actions_by_id = MemexProjectWorkflowAction.where(id: memex_project_workflow_action_ids).includes(:memex_project).index_by(&:id)

        memex_project_workflow_actions_by_id[event.performed_by_project_workflow_action_id]&.memex_project
      end
    end
  end

  batch_method(:visible_closer_for) do |events, viewer|
    permission = Platform::Authorization::Permission.new(viewer: viewer, origin: Platform::ORIGIN_INTERNAL)
    results = Promise.all(events.map { |event| event.async_visible_closer(permission) }).sync
    events.zip(results).to_h
  end

  # The object which triggered this close event, filtered by the abilities of the viewer
  #
  # Returns the appropriate object or nil if the abilities check fails
  def async_visible_closer(abilities)
    return Promise.resolve(nil) unless abilities

    async_closer.then do |closer|
      next nil unless closer
      closer_type = Platform::Helpers::NodeIdentification.type_name_from_object(closer)
      abilities.typed_can_see?(closer_type, closer).then do |can_read|
        can_read ? closer : nil
      end
    end
  end

  # Is this a commit reference?
  def commit?
    !commit_id.nil?
  end

  def issue_reference?
    reference? && !referencing_issue_id.nil?
  end

  # Public: Returns true if the given User has permission to view the subject of this event and
  # the subject is an Issue.
  def subject_issue_readable_by?(viewer)
    return unless subject = T.unsafe(self).subject
    return false unless subject.is_a?(Issue)
    return false unless subject.repository

    subject.repository&.readable_by?(viewer) && !subject.hide_from_user?(viewer)
  end

  # Public: Returns a promise resolving to true if this event is reversible and
  #   the given User has permission to do so.
  def async_can_be_undone_by?(user)
    return Promise.resolve(false) unless marked_as_duplicate?

    async_issue_event_detail.then do |details|
      Platform::Loaders::DuplicateIssue.load(details.subject_id, issue_id).then do |duplicate_issue|
        async_can_unmark_duplicate_issue_as_duplicate?(duplicate_issue, user)
      end
    end
  end

  def can_unmark_duplicate_issue_as_duplicate?(duplicate_issue, user)
    async_can_unmark_duplicate_issue_as_duplicate?(duplicate_issue, user).sync
  end

  def async_can_unmark_duplicate_issue_as_duplicate?(duplicate_issue, user)
    return Promise.resolve(false) unless duplicate_issue
    return Promise.resolve(false) unless duplicate_issue.duplicate?

    duplicate_issue.async_repository.then do |repo|
      repo.async_owner.then do
        duplicate_issue.can_unmark_as_duplicate?(user)
      end
    end
  end

  def unmark_as_duplicate_path_uri
    async_unmark_as_duplicate_path_uri.sync
  end

  # Public: Returns a promise of a relative URI for a POST request to undo
  #   a marked_as_duplicate event. Returns a promise of nil for all other event types.
  def async_unmark_as_duplicate_path_uri
    return Promise.resolve(nil) unless marked_as_duplicate?

    Promise.all([
      async_issue,
      async_repository,
    ]).then do
      UNMARK_AS_DUPLICATE_URI_TEMPLATE.expand(
        number: T.must(issue).number,
        nwo: T.must(repository).nwo,
      ).freeze
    end
  end

  def async_project_column_name
    async_issue_event_detail.then(&:column_name)
  end

  def async_previous_project_column_name
    async_issue_event_detail.then(&:previous_column_name)
  end

  def async_project_card
    async_issue_event_detail.then do |detail|
      Platform::Loaders::ActiveRecord.load(::ProjectCard, detail.card_id)
    end
  end

  def async_visible_project_card(abilities)
    async_project_card.then do |project_card|
      next unless project_card

      abilities.typed_can_see?("ProjectCard", project_card).then { |can_read| project_card if can_read }
    end
  end

  def async_project
    async_project_card.then do |project_card|
      if project_card
        project_card.async_project
      elsif project_event?
        async_subject
      end
    end
  end

  def async_memex_project
    Platform::Loaders::ActiveRecord.load(MemexProject, project_id)
  end

  # this saves us an RPC call when all we need is the abbreviated OID
  def abbreviated_oid
    return nil unless commit?
    T.must(commit_id)[0, Commit::ABBREVIATED_OID_LENGTH]
  end

  def added_to_merge_queue?
    event == "added_to_merge_queue"
  end

  def close?
    event == "closed"
  end

  def merge?
    event == "merged"
  end

  def assigned?
    event == "assigned"
  end

  def review_requested?
    event == "review_requested"
  end

  def ready_for_review?
    event == "ready_for_review"
  end

  def removed_from_merge_queue?
    event == "removed_from_merge_queue"
  end

  def unassigned?
    event == "unassigned"
  end

  def milestoned?
    event == "milestoned"
  end

  def demilestoned?
    event == "demilestoned"
  end

  def async_milestone_title
    async_issue_event_detail.then do |issue_event_detail|
      issue_event_detail.milestone_title
    end
  end

  # Is this a reference?
  def reference?
    event == "referenced"
  end

  def marked_as_duplicate?
    event == "marked_as_duplicate"
  end

  def force_push?
    FORCE_PUSH_EVENTS.include?(event)
  end

  def ref_name
    async_ref_name.sync
  end

  def async_ref_name
    return @async_ref_name if defined?(@async_ref_name)

    @async_ref_name = async_issue_event_detail.then do |detail|
      detail.ref.sub(%r{\Arefs/heads/}, "")
    end
  end

  def project_event?
    T.unsafe(self).subject_type == Project.name
  end

  # The repository the commit belongs to
  # If commit_repository is not specified, this belongs to the issue repository
  #
  # commit_repository can be present when any of the following attributes are present:
  # - commit_id
  # - before_commit_oid
  # - after_commit_oid
  def repository_for_commit
    commit_repository || repository
  end

  # Checks if there is a block on either side of the relationship
  # To determine visibility
  def visible_to?(viewer)
    subject = T.unsafe(self).subject

    if subject && %w[Issue Project].include?(subject.class.name)
      return false unless subject.readable_by?(viewer)

      if viewer && viewer.using_auth_via_granular_actor?
        grant = case subject.class.name
        when "Issue"
          ProgrammaticActor::Grant.with(viewer).with_repository(subject.repository)
        when "Project"
          case subject.owner_type
          when "Repository"
            ProgrammaticActor::Grant.with(viewer).with_repository(subject.owner)
          else
            ProgrammaticActor::Grant.with(viewer).with_target(subject.owner)
          end
        end

        return false unless subject.readable_by?(grant)
      end
    end

    return false if actor&.hide_from_user?(viewer)

    if commit?
      return false if repository_for_commit.hide_from_user?(viewer)
    end

    viewer.nil? || !safe_actor.blocked_by?(viewer)
  end

  # Fallback on the ghost user when the original author's been deleted.
  # See User.ghost for more.
  def safe_actor
    actor || User.ghost
  end

  # Fallback on the ghost user when the original subject's been deleted.
  # See User.ghost for more.
  def safe_subject
    T.unsafe(self).subject || User.ghost
  end

  def deployment
    return unless deployment_id = T.unsafe(self).deployment_id
    @deployment ||= Deployment.where(id: deployment_id).first
  end

  def deployment_status
    return unless deployment_status_id = T.unsafe(self).deployment_status_id
    @deployment_status ||= DeploymentStatus.find_by(id: deployment_status_id)
  end

  def dismissed_review
    return unless pull_request_review_id = T.unsafe(self).pull_request_review_id
    PullRequestReview.where(id: pull_request_review_id).first
  end

  def review_request
    return @review_request if defined?(@review_request)
    @review_request = async_review_request.sync
  end

  def async_review_request
    return @async_review_request if defined?(@async_review_request)

    @async_review_request = async_issue_event_detail.then do |detail|
      next unless detail.review_request_id

      Platform::Loaders::ActiveRecord.load(::ReviewRequest, detail.review_request_id)
    end
  end

  def async_message_html
    Promise.all([async_message, async_message_context]).then do |message, message_context|
      GitHub::Goomba::MarkdownPipeline.async_to_html(message, message_context)
    end
  end

  def async_message
    async_issue_event_detail.then { |detail| detail.message }
  end

  def dismissal_message
    @dismissal_message ||= async_message_html.sync
  end

  # The HTML Pipeline context hash used when turning dismissal messages into HTML.
  def message_context
    async_message_context.sync
  end

  def async_message_context
    return @async_message_context if defined?(@async_message_context)

    @async_message_context = async_repository.then do |repository|
      # TODO: this mentions removed InsightsQueryFilter, but previously same code supported (also removed) MathFilter
      # It's unknown which other filters rely on this context to function correctly

      # We need to preload the owner here so that the `:insights_codeblocks.enabled?(owner)` call inside
      # `GitHub::Goomba::InsightsQueryFilter` does not fail with `Platform::Errors::AssociationRefused`
      # This preload can be removed when the `insights_codeblocks` flag is removed
      T.must(repository).async_owner.then do
        {
          entity: repository,
          base_url: GitHub.url,
          asset_proxy: GitHub.image_proxy_url,
          disable_asset_proxy: !GitHub.image_proxy_enabled?,
          whitelist: nil,
        }
      end
    end
  end

  # Public: For IssueTimeline compatibility
  def timeline_sort_by
    # In the case where a commit and a issue_event are created
    # within the same second we added second element into the
    # array so that the issue_event always comes after the commit
    [created_at, T.must(created_at) + 1.second]
  end

  # Does this issue event represent a reference from a commit that will close
  # the issue or PR once it's merged into the default branch?
  #
  # Returns a promise resolving to a boolean
  def async_will_close_subject?
    return Promise.resolve(false) unless reference?

    Promise.all([async_commit, async_issue]).then do |commit, _issue|
      next false unless commit.present?

      async_issue.then do |issue|
        reference = GitHub::HTML::IssueMentionFilter.extract_close_reference(commit.message, issue)
        !!(reference&.close?)
      end
    end
  end

  def will_close_subject
    return @will_close_subject if defined?(@will_close_subject)
    @will_close_subject = async_will_close_subject?.sync
    @will_close_subject
  end

  # Did the referenced commit cause the issue to be closed?
  #
  # Returns a promise resolving to a Boolean
  def async_has_closed_subject?
    return Promise.resolve(false) unless commit?
    async_issue.then { |issue| T.must(issue).already_closed_by_commit?(commit_id) }
  end

  def has_closed_subject?
    return @has_closed_subject if defined?(@has_closed_subject)
    @has_closed_subject = async_has_closed_subject?.sync
  end

  # Did the commit message itself reference the subject?
  #
  # Returns a promise resolving to a Boolean
  def async_direct_reference?
    Promise.all([async_commit, async_issue]).then do |commit, issue|
      next false if commit.nil? || issue.nil?

      commit.async_directly_references_issue?(issue)
    end
  end

  def direct_reference?
    return @direct_reference if defined?(@direct_reference)
    @direct_reference = async_direct_reference?.sync
  end

  # Public: Did the pusher author (or commit) the commit as well?
  #
  # Returns Promise<Boolean>
  def async_authored_by_pusher?
    Promise.all([async_commit, async_actor]).then do |commit, actor|
      next false if commit.nil? || actor.nil?

      actors = commit.author_actors.dup << commit.committer_actor
      user_promises = actors.map(&:async_user)

      Promise.all(user_promises).then { |users| users.include?(actor) }
    end
  end

  def authored_by_pusher?
    return @authored_by_pusher if defined?(@authored_by_pusher)
    @authored_by_pushed = async_authored_by_pusher?.sync
  end

  # Public: In the case that this is a merge event, is it revertable by the given user?
  #   It is revertable if the user has write access to the repo or one of its forks, the base
  #   ref still exists, and the commit matches the expectations of Commit#revertable_from?
  #   If the repo is being migrated, then no PRs are revertable (the revert PRs would be lost).
  #
  # user - The user who will be the actor for this revert.
  #
  # Returns a Boolean indicating whether the revert is possible.
  def async_revertable_by?(user)
    @revertable_by ||= Hash.new do |h, k|
      next Promise.resolve(false) unless user
      next Promise.resolve(false) unless merge?

      h[k] = Promise.all([
        async_repository,
        async_issue_or_pull_request,
        async_commit,
      ]).then do |repo, pull, commit|
        next false if repo.locked_on_migration?
        next false if repo.archived?
        next false unless pull.is_a?(PullRequest)
        next false unless pull.merged?
        next false unless commit
        next false unless commit.revertable_from?(pull.head_sha)

        pull.async_base_repository.then do |base_repo|
          next false if !base_repo
          base_repo.async_network.then do
            next false unless base_repo.heads.exist?(pull.base_ref.b)

            pull.async_pushable_repo_for(user).then { |pushable_repo| !!pushable_repo }
          end
        end
      end
    end

    @revertable_by[user]
  end

  def last_modified_at
    @last_modified_at ||=
      [created_at, actor && T.unsafe(actor).last_modified_at].compact.max
  end

  # Public: permalink for this notification. Used to link to the site from
  # email and web notifications.
  def permalink(include_host: true)
    issue = T.must(self.issue)

    if ready_for_review? && issue.pull_request
      return "#{issue.pull_request&.permalink(include_host: include_host)}/changes_since_last_review"
    end

    url = if issue.pull_request
      issue.pull_request&.permalink(include_host: include_host)
    else
      issue.permalink(include_host: include_host)
    end
    "#{url}#{anchor}"
  end

  def async_milestone
    return Promise.resolve(nil) unless milestoned? || demilestoned?

    async_issue_event_detail.then do |detail|
      if detail.milestone_id
        Platform::Loaders::ActiveRecord.load(::Milestone, detail.milestone_id)
      else
        # Older milestone events only recorded the milestone's title, so we
        # fall back to this logic if there's no milestone_id.
        Platform::Loaders::MilestoneByTitle.load(repository_id, detail.milestone_title)
      end
    end
  end

  def async_path_uri
    return @async_path_uri if defined?(@async_path_uri)

    @async_path_uri = async_issue.then { |x| T.must(x).async_path_uri }.then do |issue_path|
      event_path = issue_path.dup
      event_path.fragment = "event-#{id}"
      event_path
    end
  end

  def async_title_was
    async_issue_event_detail.then do |detail|
      detail.title_was
    end
  end

  def async_title_is
    async_issue_event_detail.then do |detail|
      detail.title_is
    end
  end

  # Public: the page anchor for this event. Used for referencing the event when viewing a PR or issue.
  def anchor
    "#event-#{id}"
  end

  # Public: Whether the given user can see this issue event.
  def readable_by?(actor)
    repository && repository&.readable_by?(actor)
  end

  # Internal: the "Thread" is the issue. Used by the notifications rollup logic.
  def notifications_thread
    issue
  end

  # In most cases, the notifications_author is the person who created the IssueEvent i.e the actor.
  # Due to the (unfortunate) flipped relation of actor_id in issue
  # events, we have to use issue_event.subject explicitly during assigned issue
  # events.
  #
  # NOTE: in the case where we don't know the notification author,
  # we fallback to the issue's notification author
  def notifications_author
    author = if assigned?
      T.unsafe(self).subject
    else
      actor
    end

    author || T.must(issue).notifications_author
  end

  def issue_or_pull_request
    async_issue_or_pull_request.sync
  end

  def async_issue_or_pull_request
    async_issue.then { |issue| async_issue_or_pull_request_for(issue) }
  end

  def subject_as_issue_or_pull_request
    return @subject_as_issue_or_pull_request if defined?(@subject_as_issue_or_pull_request)

    @subject_as_issue_or_pull_request = async_subject_as_issue_or_pull_request.sync
  end

  def async_subject_as_issue_or_pull_request
    async_subject.then do |subject|
      next unless subject.is_a?(Issue)
      async_issue_or_pull_request_for(subject)
    end
  end

  def cross_subject_repository?
    async_cross_subject_repository?.sync
  end

  def async_cross_subject_repository?
    async_subject.then do |subject|
      subject.repository_id != repository_id
    end
  end

  def cross_commit_repository?
    !!(commit_repository_id && repository_id != commit_repository_id)
  end

  def async_issue_event_detail
    if association(:issue_event_detail).loaded?
      Promise.resolve(issue_event_detail)
    else
      Platform::Loaders::ActiveRecord.load(::IssueEventDetail, id, column: :issue_event_id)
    end.then do |detail|
      populate_event_detail_from_serialized_attributes(detail || build_issue_event_detail)
    end
  end

  # Internal: Do we want to send a notification just for the event itself?
  # For example, closed and reopened events are both noteworthy in this regard.
  def notify_for_event?
    subject = T.unsafe(self).subject
    issue = T.must(self.issue)
    # Don't send yourself assignment notifications.
    return false if assigned? && actor == subject
    return false if review_requested? && actor == subject
    return false if event == "closed" && issue.pull_request? && issue.pull_request&.merged?
    return false if should_not_notify_team?
    return false if ready_for_review?

    NOTIFICATION_EVENTS.include?(event)
  end

  def should_not_notify_team?
    subject = T.unsafe(self).subject
    issue = T.unsafe(self.issue)

    review_requested? && issue && subject.is_a?(Team) && !subject.review_request_delegation_notify_team? &&
      ReviewRequest.exists?(pull_request_id: issue.pull_request_id, reviewer_type: "User", reviewer_id: subject.review_request_team_member_ids)
  end

  # Internal: Do we want to create notification subscriptions for the event?
  # This is different from notify_for_event? because there are cases where we
  # want to subscribe, but not deliver a notification. For example, if someone
  # assigns themself to an issue, we want them to be subscribed, but we wouldn't
  # send them a notification saying they've assigned themself.
  def subscribe_for_event?
    return false if should_not_notify_team?
    return false if ready_for_review?

    NOTIFICATION_EVENTS.include?(event)
  end

  # Returns the resulting state of the roll-up summary
  # denoted by the given IssueEvent.event
  def self.summary_state_for_event(event)
    (event == "reopened") ? :open : :closed
  end

  def event_actor(viewer:)
    async_event_actor(viewer: viewer).sync
  end

  def async_event_actor(viewer:, actor: nil)
    promise = actor.nil? ? async_actor : Promise.resolve(actor)

    promise.then do |actor|
      next nil if actor.nil?

      async_can_view_actor?(viewer, actor).then do |can_view_actor|
        next actor if can_view_actor

        async_repository.then do |repo|
          T.must(repo).async_owner.then do |owner|
            next owner if owner.is_a?(::Organization)
            User.ghost
          end
        end
      end
    end
  end

  def can_view_actor?(viewer)
    return @can_view_actor if defined? @can_view_actor
    @can_view_actor = async_can_view_actor?(viewer).sync
  end

  # returns if the current viewer is able to see the actor of the event
  def async_can_view_actor?(viewer, actor = nil)
    return Promise.resolve(true) unless PROTECTED_EVENTS.include? self.event

    promise = actor.nil? ? async_actor : Promise.resolve(actor)

    promise.then do |actor|
      next true if actor.is_a?(Bot)
      if GitHub.guard_audit_log_staff_actor?
        # always display staff actor as staff actor
        next true if actor && actor.id == User.staff_user.id
      end
      next false unless viewer
      next (viewer.installation.permissions["issues"] == :write) if viewer.is_a?(Bot)

      async_repository.then do |repo|
        T.must(repo).async_owner.then do |owner|
          next true if owner == viewer

          T.must(repo).async_member?(viewer).then do |member|
            next true if member
            if owner.is_a?(Organization)
              owner.async_member?(viewer)
            else
              false
            end
          end
        end
      end
    end
  end

  def platform_type_name
    ::IssueEvent.column_to_platform_type_name(event)
  end

  # Public: Enqueue a job to deliver mail and web notifications for noteworthy events.
  # This method is invoked via the SubscribeAndNotifyJob.
  def deliver_notifications
    if notify_for_event?
      GitHub.newsies.trigger(
        issue_event_notification,
        recipient_ids: explicit_recipient_ids,
        reason: subscribable_event_to_reason(event),
        event_time: created_at,
      )
    end
  end

  # Public: Returns an IssueEventNotification wrapping the IssuEvent.
  def issue_event_notification
    @issue_event_notification ||= IssueEventNotification.new(self)
  end

  def async_integration_for_user(user)
    async_performed_via_integration.then do |app|
      next unless app

      app.async_readable_by?(user).then do |is_viewable|
        app if is_viewable
      end
    end
  end

  protected

  # Grab the repository from the issue and store it here for fast repository
  # based lookups.
  def assign_issue_repository
    return self.repository if repository_id.present?
    return unless issue = self.issue

    ActiveRecord::Base.connected_to(role: :reading) do
      if repository_id.nil? && issue.repository_id.present?
        self.repository ||= Repositories::Public.get_active_or_deleted(issue.repository_id)
      end
    end
  end

  def subscribe_and_notify
    issue = T.unsafe(self.issue)

    if ISSUE_TIMELINE_GRAPHQL_SUBSCRIPTION_EVENTS.include?(event) && issue && !issue.pull_request?
      Platform::Schema.subscriptions.trigger(:issue_updated, { id: issue.global_relay_id }, object: { issue_timeline_updated: true })
    end
    if subscribe_for_event?
      SubscribeAndNotifyJob.perform_later(
        self,
        subscriber_reasons_and_ids: subscriber_reasons_and_ids,
        deliver_notifications: ::GitHub.send_notifications?,
      )
    end
  end

  def subscriber_reasons_and_ids
    subject = T.unsafe(self).subject
    subject_id = T.unsafe(self).subject_id

    @subscriber_reasons_and_ids ||= begin
      subscriber_ids = if review_requested? && subject.is_a?(Team)
        subject.notifiable_member_ids
      elsif review_requested? && subject.is_a?(User)
        [subject_id]
      elsif added_to_merge_queue? && subject != actor
        [subject_id, actor_id]
      elsif added_to_merge_queue? || removed_from_merge_queue?
        [subject_id]
      else
        [actor_id]
      end

      {
        subscribable_event_to_reason(event) => subscriber_ids,
      }
    end
  end

  def subscribable_event_to_reason(event)
    case event
    when "mentioned" then :mention
    when "assigned" then :assign
    when "review_requested" then :review_requested
    else :state_change
    end
  end

  def update_summary_state
    return unless UPDATE_SUMMARY_STATE_EVENTS.include?(event)

    UpdateRollupSummaryStateJob.perform_later(T.must(repository).id, T.must(issue).id, id)
  end

  def event_prefix() "issue.event".to_sym end

  def event_payload
    issue = T.unsafe(self.issue)
    subject = T.unsafe(self).subject
    label_id = T.unsafe(self).label_id
    milestone_id = T.unsafe(self).milestone_id

    payload = {
      event:   event,
      issue:   issue,
      actor:   actor,
      spammy:  actor.try(:spammy?) || (issue && issue.user && issue.user.spammy?),
      allowed: allowed?,
      repository_id: repository_id,
      organization_id: T.must(repository).organization_id,
      business: repository ? T.must(repository).organization&.business : nil,
    }

    if issue.present? && issue.pull_request?
      payload[:pull_request] = issue.pull_request
      payload[:primary_resource] = issue.pull_request.attributes
    end


    if subject.present?
      payload[:subject] = subject.to_s
      payload[:subject_id] = subject.id
      payload[:subject_type] = subject.class.name
    end

    if assignee.present?
      payload[:assignee] = assignee
    end

    if label_id.present?
      payload[:label_id] = label_id.to_i
    end

    if milestone_id.present?
      payload[:milestone_id] = milestone_id.to_i
    end

    payload
  end

  def allowed?
    issue = T.unsafe(self.issue)
    repository.permit?(actor, :write) && (issue.nil? || repository.permit?(issue.user, :write))
  end

  def instrument_event
    issue = T.unsafe(self.issue)
    class_name = issue.present? && issue.pull_request? ? "pull_request" : "issue"
    GitHub.dogstats.increment("#{class_name}.events.#{event}.count")

    instrument event
  end

  def instrument_event_for_hydro
    return unless HYDRO_EVENTS.include?(event)
    return if skip_hydro_event_instrumentation

    issue = T.must(self.issue)

    payload = {
      actor: safe_actor,
      issue: issue,
      repository: issue.repository,
      repository_owner: issue.repository&.owner,
      pull_request: issue.pull_request,
      event: self,
    }

    case event
    when "assigned", "unassigned"
      payload.merge!(assignees: issue.assignees)
    when "labeled"
      GitHub::PrefillAssociations.prefill_associations(issue.labels, :repository)

      payload.merge!(label: T.unsafe(self).label, labels: issue.labels)
    when "unlabeled"
      GitHub::PrefillAssociations.prefill_associations(issue.labels, :repository)

      payload.merge!(labels: issue.labels)
    end

    GlobalInstrumenter.instrument "issue.events.#{event}", payload
  end

  private

  def skip_notifications?
    issue_transfer? || importing?
  end

  # Private: some events have explicit recipients they should be sent to for notifications.
  # This is typically done to narrow down the scope of who receives a notification.
  #
  # Returns an Array of ids (Fixnums) or nil for the default behavior
  def explicit_recipient_ids
    return [actor_id] if assigned?

    subject = T.unsafe(self).subject
    subject_id = T.unsafe(self).subject_id

    if review_requested?
      if subject.is_a?(Team)
        subject.notifiable_member_ids.reject { |id| id == actor_id || id == T.must(issue).pull_request&.user&.id }
      elsif subject.is_a?(User)
        [subject_id]
      end
    end
  end

  # Private: validate the subject is one of the required types.
  # Fired via validations.
  def subject_must_be_valid
    return true unless subject = T.unsafe(self).subject

    unless VALID_SUBJECTS.include?(subject.class.to_s)
      errors.add(:subject, "must be one of #{VALID_SUBJECTS.join(', ')}")
    end
  end

  # Private: returns a promise of the issue's pull request if it has an associated PR,
  #   otherwise it returns a promise of the issue itself.
  def async_issue_or_pull_request_for(issue)
    return Promise.resolve(nil) if issue.nil?

    if issue.pull_request_id.nil?
      Promise.resolve(issue)
    else
      issue.async_pull_request
    end
  end

  def issue_or_commit_id
    return true if issue
    return true if commit_id
    errors.add(:issue, "must have an issue associated")
  end
end
