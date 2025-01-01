# typed: true
# frozen_string_literal: true

require "socket"

class PullRequest < ApplicationRecord::Domain::IssuesPullRequests
  include PullRequests::IPullRequest

  class Error < StandardError
  end

  class PermissionError < Error
    include GitHub::UIError

    sig { returns(String) }
    def ui_message
      "You don't have permission write to the base repository."
    end
  end

  class MergeConflictError < Error
    include GitHub::UIError

    sig { returns(String) }
    def ui_message
      "Merge conflict between head and base."
    end
  end

  class RebaseConflictError < Error
    include GitHub::UIError

    sig { returns(String) }
    def ui_message
      "Rebase conflict between head and base."
    end
  end

  class HeadMissing < Error
    include GitHub::UIError

    sig { returns(String) }
    def ui_message
      "Head ref does not exist."
    end
  end

  class RefMismatch < Error
    include GitHub::UIError

    sig { returns(String) }
    def ui_message
      "Head branch was modified. Review and try the merge again."
    end
  end

  class BaseBranchNotBehindError < Error
    include GitHub::UIError

    sig { returns(String) }
    def ui_message
      "There are no new commits on the base branch."
    end
  end

  class BaseNotChangeableError < Error
    include GitHub::UIError

    attr_reader :new_base_ref

    sig { returns(String) }
    def self.error_type_key
      to_s.underscore
    end

    sig { returns(String) }
    def error_type_key
      self.class.error_type_key
    end

    sig { params(pull: PullRequest, new_base_ref: T.untyped).void }
    def initialize(pull, new_base_ref)
      @pull = pull
      @new_base_ref = PullRequest.display_ref_name(new_base_ref.dup)
    end

    sig { returns(String) }
    def ui_message
      "Cannot change the base branch from '#{@pull.display_base_ref_name}' to '#{@new_base_ref}'."
    end
  end

  class BaseRefNotFoundError < BaseNotChangeableError
    sig { returns(String) }
    def ui_message
      "Proposed base branch '#{@new_base_ref}' was not found"
    end
  end

  class InvalidBaseRefNameError < BaseNotChangeableError
    sig { returns(String) }
    def ui_message
      "Proposed base branch '#{@new_base_ref}' is invalid"
    end
  end

  class RefPairingAlreadyExistsError < BaseNotChangeableError
    sig { returns(String) }
    def ui_message
      "A pull request already exists for base branch '#{@new_base_ref}' and head branch '#{@pull.display_head_ref_name}'"
    end
  end

  class ComparisonWouldBeEmptyError < BaseNotChangeableError
    sig { returns(String) }
    def ui_message
      "There are no new commits between base branch '#{@new_base_ref}' and head branch '#{@pull.display_head_ref_name}'"
    end
  end

  class ClosedError < BaseNotChangeableError
    sig { returns(String) }
    def ui_message
      "Cannot change the base branch of a closed pull request."
    end
  end

  class RefBeingRenamedError < BaseNotChangeableError
    sig { returns(String) }
    def ui_message
      "The base branch '#{@new_base_ref}' is being renamed."
    end
  end

  class LockedForMergeQueueError < BaseNotChangeableError
    sig { returns(String) }
    def ui_message
      "Cannot change the base branch because the branch has been added to a merge queue."
    end
  end

  class RevertError < Error; end

  # Default limit of commits to be returned.
  COMMIT_LIMIT = 250
  AUTO_CHANGE_BASE_MAX_PULL_REQUESTS = 50

  REVERT_URI_TEMPLATE = Addressable::Template.new("/{owner}/{name}/pull/{number}/revert").freeze
  DISMISS_MERGE_TIP_URI_TEMPLATE = Addressable::Template.new("/{owner}/{name}/pull/{number}/dismiss_protip").freeze
  RESTORE_HEAD_REF_URI_TEMPLATE = Addressable::Template.new("/{owner}/{name}/pull/{number}/undo_cleanup").freeze
  MERGE_QUEUE_ACTIONS = [:merge_queue_merge, :api_merge_queue_merge]
  MERGE_ACTION_MESSAGES = (MERGE_QUEUE_ACTIONS + [:merged_indirectly]).freeze

  include IssueTimeline
  include GitHub::Validations
  include Spam::Spammable
  include UserContentEditable
  include OrgBlockable
  include AbuseReportable
  include MemexProjectItem::Content
  include GitHub::ResilienceMixin

  include Issues::TimezoneTimestamp
  T.unsafe(self).timezone_timestamp :contributed_at

  include PullRequest::AnalyticsDependency
  include PullRequest::ChecksDependency
  include PullRequest::CloseIssueReferencesDependency
  include PullRequest::CountersDependency
  include PullRequest::FindersDependency
  include PullRequest::HovercardDependency
  include PullRequest::ImageDependency
  include PullRequest::MemexDependency
  include PullRequest::IssuesGraphDependency
  include PullRequest::MergeQueueDependency
  include PullRequest::PermissionsDependency
  include PullRequest::ProtectedBranchesDependency
  include PullRequest::ReviewsDependency
  include PullRequest::ReviewRequestsDependency
  include PullRequest::AutoMergeDependency
  include PullRequest::DiffViewDependency
  include PullRequest::DeploymentsDependency
  include PullRequest::SynchronizationDependency
  include PullRequest::CodeNavDependency
  include PullRequest::PresenceDependency
  include PullRequest::UserReviewedFilesDependency
  include PullRequest::DependabotDependency

  include GitHub::Relay::GlobalIdentification

  include PullRequest::CodeScanningDependency

  include GitHub::RateLimitedCreation

  include Permissions::Attributes::Wrapper
  self.permissions_wrapper_class = Permissions::Attributes::Issue

  include InteractionBanValidation
  include AuthorAssociable
  include LegacyImportable
  include Reactable
  include Prefillable
  include PreloadableAttributes
  include Repositories::Domain::Provider

  attr_preloadable :author_association_symbol

  belongs_to :repository
  belongs_to :user
  has_one :issue, validate: true, inverse_of: :pull_request, autosave: true
  has_one :auto_merge_request

  setup_spammable(:user)

  # Internal: an abstract collection, for the sub-resources of a Pull Request available for GitHub Apps
  sig { returns(Resources) }
  def resources
    PullRequest::Resources.new(self)
  end

  # repository for base and head refs
  belongs_to :base_repository, class_name: "Repository"
  belongs_to :head_repository, class_name: "Repository"

  # users that own that base and head repositories
  belongs_to :base_user, class_name: :User
  belongs_to :head_user, class_name: :User

  # reviews
  has_many :reviews, class_name: "PullRequestReview"
  destroy_dependents_in_background :reviews, sharding_key: :repository_id, sharding_value_key: :repository_id

  # review requests
  has_many :review_requests, -> { where(dismissed_at: nil) },
    autosave: true,
    extend: ReviewRequest::AssociationExtension,
    inverse_of: :pull_request

  has_many :review_requests_pending, -> { T.unsafe(self).not_dismissed.pending },
    class_name: "ReviewRequest"

  has_many :unscoped_review_requests, nil,
    class_name: "ReviewRequest",
    dependent: :delete_all

  has_many :updates, class_name: :PullRequestUpdate
  destroy_dependents_in_background :updates, sharding_key: :repository_id, sharding_value_key: :repository_id

  has_many :review_points, class_name: :PullRequestReviewPoint
  destroy_dependents_in_background :review_points, sharding_key: :repository_id, sharding_value_key: :repository_id

  has_many :review_comments, nil,
    class_name: "PullRequestReviewComment",
    inverse_of: :pull_request
  destroy_dependents_in_background :review_comments, sharding_key: :repository_id, sharding_value_key: :repository_id

  has_many :user_reviewed_files

  has_many :codespaces

  has_many :pull_request_sources, dependent: :destroy

  has_many :review_threads, -> {
    order(:pull_request_id, :created_at, :id)
  },
  class_name: "PullRequestReviewThread",
  inverse_of: :pull_request

  has_many :legacy_review_threads, -> {
    where(pull_request_review_id: nil).order(:pull_request_id, :created_at, :id)
  },
    class_name: "PullRequestReviewThread",
    inverse_of: :pull_request
  destroy_dependents_in_background :legacy_review_threads, sharding_key: :repository_id, sharding_value_key: :repository_id

  has_many :line_review_threads, -> (pull_request) {
    where(repository_id: pull_request.repository_id, subject_type: :line).order(:pull_request_id, :created_at, :id)
  },
  class_name: "PullRequestReviewThread",
  inverse_of: :pull_request

  has_many :file_review_threads, -> {
    where(subject_type: :file).order(:pull_request_id, :created_at, :id)
  },
  class_name: "PullRequestReviewThread",
  inverse_of: :pull_request

  has_many :last_seen_pull_request_revisions, dependent: :delete_all

  has_many :dependency_updates, -> {
    order(id: :desc)
  },
    class_name: :RepositoryDependencyUpdate,
    inverse_of: :pull_request,
    dependent: :destroy

  has_one :most_recent_vulnerability_dependency_update, -> { T.unsafe(self).order(id: :desc).visible.vulnerability.complete },
    class_name: :RepositoryDependencyUpdate,
    inverse_of: :pull_request

  has_one :conflict, -> { where(conflict_type: :merge_conflict) },
    class_name: "PullRequestConflict",
    dependent: :destroy

  has_one :rebase_conflict, -> { where(conflict_type: :rebase_conflict) },
    class_name: "PullRequestConflict",
    dependent: :destroy

  has_one :merge_queue_conflict, -> { where(conflict_type: :merge_queue_conflict) },
    class_name: "PullRequestConflict",
    dependent: :destroy

  has_many :close_issue_references
  destroy_dependents_in_background :close_issue_references

  # rubocop:todo Rails/InverseOf
  has_many :memex_project_items,
    ->(pull) { where(content_type: "PullRequest", repository_id: pull.repository_id) },
    class_name: "MemexProjectItem",
    foreign_key: :content_id
  # rubocop:enable Rails/InverseOf
  destroy_dependents_in_background(
    :memex_project_items,
    sharding_key: :repository_id,
    sharding_value_key: :repository_id,
  )
  after_touch :touch_memex_project_items # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  has_many :memex_projects, through: :memex_project_items

  has_one :pull_request_import, dependent: :destroy
  has_one :import, through: :pull_request_import

  has_one :last_push, class_name: :PullRequestLastPush, inverse_of: :pull_request, required: false, dependent: :destroy

  # This will create the following methods:
  #
  # - ready_state?
  # - ready_state!
  # - in_progress_state?
  # - in_progress_state!
  # - draft_state?
  # - draft_state!
  #
  enum :reviewable_state, { ready: 0, in_progress: 10, draft: 20 }, suffix: "state"

  # This will create the following methods:
  #
  # - fork_collab_denied?
  # - fork_collab_denied!
  # - fork_collab_allowed?
  # - fork_collab_allowed!
  #
  enum :fork_collab_state, { denied: 0, allowed: 1 }, prefix: "fork_collab"

  before_validation :record_concrete_commit_points, on: :create, unless: :importing?
  before_validation :set_contributed_at, on: :create
  before_validation :clean_refs_heads, on: [:create, :update]

  after_create :subscribe_author # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_create :clear_contributions_cache # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  # `after_commit` fires after both save and touch.
  after_commit :sync_issue_updated_at # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_save :record_tracking_ref_maintenance_required # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :maintain_tracking_ref_later, on: [:create, :update] # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_commit :enqueue_request_pull_request_reviewers_job, on: :create, if: :ready_for_review? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :notify_socket_subscribers, on: :update # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :synchronize_search_index # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  # Syncs to issues graph when PR is converted from or into a draft
  after_update :sync_issues_graph_data, if: :saved_change_to_reviewable_state? # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  validates_presence_of :head_ref, :base_ref
  validates_presence_of :head_sha, :base_sha
  validates_presence_of :contributed_at, on: :create
  validates_presence_of :head_user_id, :base_user_id
  validates_presence_of :head_repository_id, :repository_id, :base_repository_id

  validate :must_have_commits, on: :create, unless: :importing?
  validate :must_have_common_ancestor, on: :create, unless: :importing?
  validate :duplicate_check, on: :create, unless: :importing?
  validate :base_ref_is_not_being_renamed, on: :create
  validate :head_ref_is_real_branch, on: :create, unless: :importing?
  validate :validate_authorized_to_create_content, on: :create, unless: :importing?
  validate :validate_refs_readable, on: :create, unless: :importing?
  validate :user_can_interact, on: :create
  validate :validate_under_duplicate_head_sha_limit, on: :create

  validate :repository_and_base_repository_must_match,
    on: [:create, :update], unless: [:in_advisory_workspace?, :importing?]
  validate :head_repository_must_be_advisory_workspace,
    on: [:create, :update], if: :in_advisory_workspace?, unless: :importing?
  validate :base_repository_must_be_advisory_workspace_origin_repository,
    on: [:create, :update], if: :in_advisory_workspace?, unless: :importing?
  validate :base_ref_is_real_branch, on: [:create, :update], unless: :importing?, if: :base_ref_changed?
  validate :head_ref_is_not_namespaced, on: [:create, :update], unless: :importing?
  validate :head_ref_does_not_contain_refs_heads, on: [:create, :update]
  validate :base_ref_does_not_contain_refs_heads, on: [:create, :update]
  validate :head_ref_is_not_from_merge_queue, on: [:create, :update], unless: :importing?
  validate :valid_cross_repo_collab, on: [:create, :update]
  validates :fork_collab_state, presence: true

  # fetch pull requests issues by a Label id or Label name
  scope :labeled, lambda { |label_or_collection|
    joins(:issue).merge(Issue.labeled_by_any(label_or_collection))
  }

  scope :for_repository, lambda { |repository|
    where(repository_id: repository)
  }

  scope :from_repository, lambda { |head_repository|
    where(head_repository_id: head_repository)
  }

  scope :to_repository, lambda { |base_repository|
    where(base_repository_id: base_repository)
  }

  scope :for_user, lambda { |user|
    where(user_id: user)
  }

  scope :open_based_on_ref, -> (repository, ref) {
    ids = find_open_ids_based_on_ref(repository, ref)
    includes(:issue).where(id: ids)
  }

  #
  # Basic Attributes
  #

  # In MySQL 8 `tinyint(1) unsigned` columns will not be detected as booleans
  # by rails. Until we can migrate this column to `tinyint(1) signed` override
  # explicitly here to support MySQL 8
  attribute :mergeable, ActiveRecord::Type::Boolean.new

  # DCO sign-off settings should delegate to base_repository (rather than head_repository) to work properly for fork cases
  delegate :dco_signoff_enabled?, to: :base_repository

  delegate :number, :title, :close, :closed_at, :closed_by, :safe_closed_by,
    :events, :subscribers, :body, :body_html, :body_text, :prelude_body_html,
    :body_version, :mentioned_users, :mentioned_teams,
    :subscribe, :unsubscribe, :subscribed?, :ignore, :task_list, :task_list?, :has_task_list?, :has_too_many_tasks?,
    :task_list_summary, :async_lightweight_task_list_summary, :notifications_list, :notifications_thread,
    :notifications_author, :entity, :issue_comments_count, :subscriptions,
    :get_event_participants, :organization, :owner, :assignees, :assigned_to?, :labels,
    :milestone, :sparkles,
    to: :issue

  HTMLTextPromise = T.type_alias { T.any(Promise[String], Promise[ActiveSupport::SafeBuffer], Promise[NilClass]) }

  def async_notifications_list
    async_issue.then(&:async_notifications_list)
  end

  sig { params(max: Numeric).returns(Promise[HTMLTextPromise]) }
  def async_truncated_body_html(max)
    async_issue.then { |issue| issue.async_truncated_body_html(max) }
  end

  sig { params(context: T.untyped).returns(Promise[HTMLTextPromise]) }
  def async_body_html(context: {})
    async_issue.then { |issue| issue.async_body_html(context:) }
  end

  sig { params(viewer: T.nilable(User), cap_filter: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
  def body_html_context(viewer:, cap_filter:)
    { viewer:, cap_filter:, unfurl_references: true }
  end

  sig { params(context: Hash).returns(Promise[HTMLTextPromise]) }
  def async_body_text(context: {})
    async_issue.then { |issue| issue.async_body_text(context:) }
  end

  # If there is an associated issue, it needs to have the same timestamp.
  #
  # The issue may have already been updated, so verify that the timestamp
  # is out of date before updating to avoid a redundant query (see #57779).
  #
  # Execute after commit - outside the model's lifecycle transaction to avoid locking
  # pull requests.
  sig { void }
  def sync_issue_updated_at
    return unless issue = self.issue
    return if issue.frozen? || issue.new_record?

    if issue.updated_at.to_i < updated_at.to_i
      # update_column doesn't invoke callbacks.
      issue.update_column(:updated_at, updated_at)
    end
  end

  sig { returns(T::Boolean) }
  def pull_request?
    true
  end

  sig { returns(String) }
  def to_param
    T.must(issue).number.to_s
  end

  sig { returns(T.nilable(String)) }
  def base
    return if base_user.nil?
    "#{owner_display_login(base_user)}:#{base_ref}"
  end

  sig { returns(String) }
  def head
    "#{owner_display_login(safe_head_user)}:#{head_ref}"
  end

  sig { params(username_qualified: T::Boolean).returns(T.nilable(String)) }
  def base_label(username_qualified: cross_repo?)
    if username_qualified
      return if base_user.nil?
      "#{owner_display_login(base_user)}:#{display_base_ref_name}"
    else
      display_base_ref_name
    end
  end

  sig { params(username_qualified: T::Boolean).returns(T.nilable(String)) }
  def head_label(username_qualified: cross_repo?)
    if username_qualified
      return if head_user.nil?
      "#{owner_display_login(safe_head_user)}:#{display_head_ref_name}"
    else
      display_head_ref_name
    end
  end

  sig { returns(String) }
  def base_ref_name
    safe_ref_name(base_ref)
  end

  sig { returns(String) }
  def head_ref_name
    safe_ref_name(head_ref)
  end

  sig { returns(String) }
  def display_base_ref_name
    PullRequest.display_ref_name(base_ref_name)
  end

  sig { returns(String) }
  def display_head_ref_name
    PullRequest.display_ref_name(head_ref_name)
  end

  sig { returns(String) }
  def qualified_base_ref_name
    "refs/heads/#{base_ref_name}"
  end

  sig { returns(String) }
  def qualified_head_ref_name
    "refs/heads/#{head_ref_name}"
  end

  sig { params(ref_name: String).returns(String) }
  def self.display_ref_name(ref_name)
    ref_name.force_encoding("utf-8").scrub!
  end

  sig { returns(T::Boolean) }
  def head_ref_contains_non_printing_chars?
    contains_non_printing_chars = display_head_ref_name.dump != "\"#{display_head_ref_name}\""
    GitHub.dogstats.increment("pull_request.head_ref_contains_non_printing_chars") if contains_non_printing_chars
    contains_non_printing_chars
  end

  sig { returns(String) }
  def raw_head_ref_name
    head_ref_name.b
  end

  sig { returns(User) }
  def safe_head_user
    head_user || User.ghost
  end

  sig { returns(User) }
  def safe_user
    user || User.ghost
  end

  sig { params(opener: T.untyped).void }
  def open(opener)
    issue = T.must(self.issue)
    issue.pull_request = self
    issue.open(opener)
  end

  sig { returns(T::Boolean) }
  def open?
    issue.nil? || T.must(issue).open?
  end

  sig { params(actor: T.untyped).void }
  def after_close(actor)
    unless merged?
      GlobalInstrumenter.instrument("pull_request.close", {
        actor: actor,
        pull_request: self,
      })
      instrument(:close, actor: actor)

      auto_merge_request&.disable(:closed)
      dequeue_after_close
    end

    async_destroy_merge_refs
    destroy_conflict_metadata
    clear_rebase_conflicts
    Actions::PostPullRequestCloseMergeJob.perform_later(self)
  end

  sig { void }
  def dequeue_after_close
    # The Merge Queue cleans up queue entries after merge but we need to do it here
    # when a PR is closed without being merged.
    return if merged?
    return unless queue = merge_queue.presence
    return unless entry = merge_queue_entry.presence

    MergeQueues.remove!(queue:, entry:, actor: GitHub.merge_queue_bot)
  end

  sig { returns(T::Boolean) }
  def closed?
    !open?
  end

  sig { returns(T.nilable(Symbol)) }
  def state
    return :open     if open?
    return :merged   if merged?
    :closed   if closed?
  end

  sig { returns(String) }
  def issue_state
    return @issue_state if defined? @issue_state
    @issue_state = async_issue_state.sync
  end

  sig { returns(Promise[String]) }
  def async_issue_state
    if merged_at
      Promise.resolve("merged")
    else
      async_issue.then { |issue| issue.state }
    end
  end

  sig { params(user: T.untyped).returns(Promise[T.nilable(Newsies::Subscription)]) }
  def async_subscription_status(user)
    async_issue.then do |issue|
      issue.async_subscription_status(user)
    end
  end

  # Called when a closed but unmerged pull request is reopened. Updates
  # the base and head SHA1s based on the current branch state. This method
  # is called by Issue#open to ensure any new commits fill into the newly
  # reopened pull request but only when the #reopenable? method returns true.
  sig { params(opener: T.untyped).returns(T::Boolean) }
  def reopened(opener)
    synchronize!(user: opener, repo: T.must(head_repository), reopened: true)
    if repository&.feature_enabled?(:clear_mergeable_on_reopen)
      update(merge_commit_sha: nil)
      enqueue_mergeable_update
    end
    GlobalInstrumenter.instrument("pull_request.reopen", {
      pull_request: self,
      actor: opener,
    })
    instrument(:reopen, actor: opener)
    true
  rescue DetermineCodeownersError
    false
  end

  # Determine if this pull request is reopenable. Pull Requests that have
  # already been merged cannot be reopened because merging causes a pull request
  # to automatically close. You also cannot reopen pull requests whose base or
  # head branches no longer exist. You also cannot reopen a pull request whose
  # head repository is private but base repository is public. They're
  # automatically closed when a repository goes private.
  #
  # Returns true when the pull request can be reopened.
  sig { returns(T::Boolean) }
  def reopenable?
    GitHub.dogstats.time("pull_request", tags: ["action:reopenable"]) do
      async_reopenable?.sync
    end
  end

  sig { returns(Promises::Boolean) }
  def async_reopenable?
    return Promise.resolve(false) if merged?

    Promise.all([
      async_base_repository,
      async_head_repository,
      async_repository,
      async_base_user,
      async_head_user,
    ]).then do |base_repo, head_repo|
      cross_repo_violation_promise = base_repo&.feature_enabled?(:check_cross_repo_in_reopenable) ? async_cross_repo_violation? : Promise.resolve(false)

      Promise.all([
        base_repo&.async_network,
        head_repo&.async_network,
        async_is_head_merged_into_base?,
        async_common_ancestor?,
        cross_repo_violation_promise
      ]).then do |_, _, is_head_merged_into_base, has_common_ancestor, cross_repo_violation|
        !find_existing && refs_exist? &&
          !(T.must(head_repository).private? && T.must(repository).public?) &&
            !is_head_merged_into_base &&
            old_head_connected_to_new? &&
            has_common_ancestor &&
            head_repository && T.must(head_repository).active? &&
            !cross_repo_violation
      end
    end.rescue do |error|
      if [GitRPC::ObjectMissing, Repository::CommandFailed].include?(error.class)
        false
      else
        raise error
      end
    end
  end

  # Give a reason why this PR is not reopenable
  # Returns a String reason, or nil if this state doesn't deserve a reason
  sig { returns(T.nilable(String)) }
  def not_reopenable_reason
    return if reopenable?  # reopenable, so no reason

    # no special messages for these cases
    return if merged?
    return if head_repository.try(:private?) && T.must(repository).public?

    if !head_repository? || T.must(head_repository).deleted?
      "The repository that submitted this pull request has been deleted."
    elsif find_existing
      "There is already an open pull request from #{head_label} to #{base_label}."
    elsif bad_refs = missing_refs
      if bad_refs.length == 1
        "The #{bad_refs.first} branch has been deleted."
      else
        "The #{bad_refs.join(" and ")} branches have been deleted."
      end
    elsif historical_comparison.zero_commits?
      "There are no new commits on the #{head_label} branch."
    elsif is_head_merged_into_base?
      "These commits are already merged."
    elsif !old_head_connected_to_new?
      "The #{display_head_ref_name} branch was force-pushed or recreated."
    elsif !common_ancestor?
      "The #{head_label} branch has no history in common with #{base_label}."
    end
  rescue GitRPC::ObjectMissing, Repository::CommandFailed
    "The repository may be missing relevant data. Please contact support for more information."
  end

  # Internal: set the error message for this PR not being reopenable
  # Currently called only from Issue#open

  # Adds an error to the :state field
  sig { void }
  def set_not_reopenable_error
    message  = "cannot be changed. "
    message += not_reopenable_reason || "The pull request cannot be reopened."
    errors.add(:state, message)
  end

  # Absolute permalink URL for this pull request.
  #
  # include_host - Turn off the `GitHub.url` host in the url. (default true)
  #                pull_request.permalink(include_host: false) => `/github/github/pull/4`
  #
  sig { params(include_host: T::Boolean).returns(T.nilable(String)) }
  def permalink(include_host: true)
    return nil unless repository = self.repository
    "#{repository.permalink(include_host: include_host)}/pull/#{number}"
  end
  alias url permalink

  sig { returns(T.nilable(Addressable::URI)) }
  def path_uri
    return @path_uri if defined?(@path_uri)
    @path_uri = async_path_uri.sync
  end

  sig { returns(Promise[T.nilable(Addressable::URI)]) }
  def async_path_uri
    return @async_path_uri if defined?(@async_path_uri)
    @async_path_uri = async_issue.then(&:async_path_uri)
  end

  sig { returns(Promise[[T.untyped, T.nilable(Repository), T.nilable(Issue)]]) }
  def async_uri_dependencies
    return @async_uri_dependencies if defined?(@async_uri_dependencies)

    @async_uri_dependencies = Promise.all([
      async_issue,
      async_repository.then(&:async_owner),
    ]).then do |issue, owner|
      [owner, repository, issue]
    end

    T.unsafe(@async_uri_dependencies)
  end

  sig { returns(Promise[T.nilable(Addressable::URI)]) }
  def async_revert_path_uri
    return @async_revert_path_uri if defined?(@async_revert_path_uri)

    @async_revert_path_uri = begin
      async_uri_dependencies.then do |owner, _repo, issue|
        REVERT_URI_TEMPLATE.expand(owner: owner_display_login(owner), name: T.must(repository).name, number: T.must(issue).number)
      end
    end
  end

  sig { returns(Promise[T.nilable(Addressable::URI)]) }
  def async_restore_head_ref_path_uri
    async_uri_dependencies.then do |owner, _repo, issue|
      RESTORE_HEAD_REF_URI_TEMPLATE.expand(owner: owner_display_login(owner), name: T.must(repository).name, number: T.must(issue).number)
    end
  end

  sig { returns(Promise[T.nilable(Addressable::URI)]) }
  def async_dismiss_merge_tip_path_uri
    async_uri_dependencies.then do |owner, _repo, issue|
      DISMISS_MERGE_TIP_URI_TEMPLATE.expand(owner: owner_display_login(owner), name: T.must(repository).name, number: T.must(issue).number)
    end
  end

  sig { returns(T.any(Time, ActiveSupport::TimeWithZone)) }
  def last_modified_at
    @last_modified_at ||= T.unsafe(self).last_modified_with :user
  end

  # Unique identifier for this pull request used in email notifications.
  sig { returns(T.nilable(String)) }
  def message_id
    return nil unless repository = self.repository
    "<#{repository.name_with_display_owner}/pull/#{number}@#{GitHub.urls.host_name}>"
  end

  # The title of the pull request, ran though the title markdown filter to make it safe HTML.
  sig { returns(String) }
  def title_html
    GitHub::Goomba::TitleMarkdownFilter.call(title)
  end

  # Generate a default title based on the head ref branch name.
  #
  #   "less_debris" => "Less debris"
  #   "rails-2.2.3" => "Rails 2.2.3"
  #   "various_fixes_and_stuff" => "Various fixes and stuff"
  #
  # Returns nil when the comparison head is "master", "gh-pages", or
  # a commit SHA1.
  sig { returns(T.nilable(String)) }
  def default_title
    return if comparison.head.blank? || comparison.head_ref =~ /^[0-9a-f]{7,40}(?:[~^@{].*)?$/

    if comparison.total_commits == 1
      commit = comparison.commits.first
      if commit.empty_message?
        ""
      else
        Commits::CommitMessage.new(commit.message).subject
      end
    else
      return if head_ref == "gh-pages"
      return if head_ref == comparison.head_repo.default_branch
      comparison.display_head_ref.underscore.humanize
    end
  end

  # A file under .github/PULL_REQUEST_TEMPLATES to read body content from
  sig { returns(T.nilable(String)) }
  attr_accessor :body_template_name

  # Public: Find the user supplied template to use in the body
  # of new pull requests if one exists.
  #
  # Read from a file under .github/PULL_REQUEST_TEMPLATES or
  # PULL_REQUEST_TEMPLATE.md.
  #
  # Returns a String from the template if one is found.
  # Returns nil if no template is found.
  sig { returns(T.nilable(String)) }
  def body_template
    return unless repository = self.repository
    return @body_template if defined?(@body_template)
    return @body_template = repository.preferred_pull_request_template&.data unless body_template_name.present?

    local_file = PreferredFile.find(
      directory: repository.root_directory,
      type: :pull_request_template,
      nested_filename: body_template_name,
    )&.data

    if !local_file.present? && !repository.global_health_files_repository?
      global_repo = repository.global_health_files_repo
      return @body_template = nil unless global_repo.present?

      @body_template = PreferredFile.find(
        directory: global_repo.root_directory,
        type: :pull_request_template,
        nested_filename: body_template_name,
      )&.data
    else
      @body_template = local_file
    end
  end

  sig { returns(T::Boolean) }
  def has_body_template?
    !!body_template
  end

  sig { returns(T.nilable(IssueTemplate)) }
  def template
    @template ||= T.must(repository).preferred_issue_templates[body_template_name]
  end

  sig { returns(String) }
  def default_body
    body_parts = []

    if comparison.total_commits == 1
      commit = comparison.commits.first
      if !commit.empty_message?
        message = Commits::CommitMessage.new(commit.message_without_authored_by_or_signed_off_trailers)
        if message.body.present?
          body_parts << CommitMessageUnwrapper.call(message.body)
        end
      end
    end

    if has_body_template?
      body_parts << body_template
    end

    body_parts.join("\n\n")
  end

  # Makes this class compatible with IssueComments for rendering the body.
  # See GitHub::UserContent#body_pipeline for more info.
  sig { returns(Symbol) }
  def formatter
    :markdown
  end

  sig { returns(T::Boolean) }
  def created_via_email
    false
  end

  alias_attribute :draft, :work_in_progress

  sig { params(user: T.untyped).returns(T::Boolean) }
  def can_change_draft_state?(user)
    return false unless user.present?
    self.user == user || !!T.must(repository).pushable_by?(user)
  end

  sig { returns(T::Boolean) }
  def draft_or_in_progress?
    draft? || draft_state? || in_progress_state?
  end

  sig { params(user: T.untyped).returns(T::Boolean) }
  def can_mark_ready_for_review?(user)
    return false unless open?
    return false unless draft_or_in_progress?
    can_change_draft_state?(user)
  end

  sig { params(user: T.untyped).returns(T::Boolean) }
  def can_convert_to_draft?(user)
    return false unless T.must(repository).plan_supports?(:draft_prs)
    return false unless open?
    return false if draft?
    can_change_draft_state?(user)
  end

  sig { params(user: T.untyped).returns(T.nilable(T::Boolean)) }
  def author_or_committer?(user)
    self.user == user || changed_commits.map(&:author).include?(user)
  end

  # Public: Mark this pull request as ready for review
  #
  # `user`   — The user who marked it ready for review, so review requests come
  #            from the correct person
  # `update` - The PullRequestUpdate that marked the PR ready via `push -o pull.ready`.
  #            (Optional, default nil.) -- Deprecated, unused in method body.
  # `force`  - Mark the PR ready for review even if it's already ready.
  #            (Optional, default false.)
  #
  # Returns nothing.
  sig { params(user: T.untyped, update: T.untyped, force: T::Boolean).void }
  def ready_for_review!(user:, update: nil, force: false)
    unreviewable = T.let(false, T::Boolean)
    unreviewable = true unless force || draft? || draft_state? || in_progress_state?
    return if unreviewable

    with_lock do
      self.draft = false
      self.reviewable_state = :ready
      self.save!

      events.create!(event: "ready_for_review", actor: user, subject_type: nil, subject_id: nil)
    end

    channel = GitHub::WebSocket::Channels.pull_request_review_state(self)
    GitHub::WebSocket.notify_pull_request_channel(
      self,
      channel,
      {
        wait: default_live_updates_wait,
        pull_request_id: id,
      },
    )

    reviewable_state_was = self.reviewable_state_before_last_save

    RequestPullRequestReviewersJob.perform_later(self, user, should_re_request_reviews: reviewable_state_was == "draft")

    GlobalInstrumenter.instrument("pull_request.ready_for_review", {
      pull_request: self,
      actor: user,
      reviewable_state_was: reviewable_state_was,
    })

    instrument(:ready_for_review, actor: user)
  end

  # Public: Is this pull request ready for review?
  sig { returns(T::Boolean) }
  def ready_for_review?
    !draft?
  end

  sig { params(user: T.untyped).void }
  def convert_to_draft(user:)
    return if draft?
    return unless open?

    transaction do
      self.draft = true
      self.reviewable_state = :draft
      self.save!

      events.create!(event: "convert_to_draft", actor: user)
    end

    channel = GitHub::WebSocket::Channels.pull_request_review_state(self)
    GitHub::WebSocket.notify_pull_request_channel(
      self,
      channel,
      {
        wait: default_live_updates_wait,
        pull_request_id: id,
      },
    )

    instrument(:converted_to_draft, actor: user)

    params = {
      actor: user,
      pull_request: self,
      reviewable_state_was: self.reviewable_state_before_last_save,
    }
    GlobalInstrumenter.instrument("pull_request.converted_to_draft", params)

    auto_merge_request&.disable(:converted_to_draft)
  end

  # Overwrite the automatically created enum methods so we can keep the `draft`
  # column in sync until we remove it
  sig { void }
  def draft_state!
    update!({ reviewable_state: :draft, draft: true })
  end

  sig { void }
  def ready_state!
    update!({ reviewable_state: :ready, draft: false })
  end

  sig { void }
  def in_progress_state!
    update!({ reviewable_state: :in_progress, draft: false })

    GlobalInstrumenter.instrument("pull_request.in_progress", {
      pull_request: self,
      actor: user,
      reviewable_state_was: self.reviewable_state_before_last_save,
    })
    instrument(:in_progress, actor: user)
  end

  # Internal: Notify subscribers that this Pull Request has been updated.
  # @param associated_updates: A Hash of updates at the associated objects (ex: review requests, etc..)
  # @returns Set of channel id Strings that were notified.
  sig { params(associated_updates: T.nilable(Hash)).void }
  def notify_socket_subscribers(associated_updates: {})
    associated_updates ||= {}
    # there is currently no reason to notify for new Pull Requests
    return if previous_changes.include?("id")

    # it seems that `after_commit ... :on => :update` doesn't work correctly
    return if self.destroyed? || !repository || self.importing?

    if @reviewers_updated || previous_changes.include?("work_in_progress")
      associated_updates = { "#{ReviewRequest::LIVE_UPDATE_EVENT_NAME}": true }
      remove_instance_variable(:@reviewers_updated) if defined?(@reviewers_updated)
    end

    timestamp = Time.now.to_i

    data = {
      timestamp: timestamp,
      wait: default_live_updates_wait,
      reason: "pull request ##{id} updated",
      gid: global_relay_id,
    }

    issue = T.must(self.issue)
    status_changed = issue.previous_changes.include?("state") || previous_changes.include?("reviewable_state")
    if status_changed
      actor = User.find_by(id: GitHub.context[:actor_id])
      if GitHub.flipper[:pull_request_sub_triggers].enabled?(actor)
        if GitHub.flipper[:pull_request_single_subscription].enabled?(actor)
          Platform::Schema.subscriptions.trigger(:pull_request_info_for_list_view_updated, { id: global_relay_id }, object: { status_updated: true })
        end
        Platform::Schema.subscriptions.trigger(:pull_request_status_updated, { id: global_relay_id })
      end
    end

    if issue.previous_changes.include?("title")
      actor = User.find_by(id: GitHub.context[:actor_id])
      if GitHub.flipper[:pull_request_sub_triggers].enabled?(actor)
        if GitHub.flipper[:pull_request_single_subscription].enabled?(actor)
          Platform::Schema.subscriptions.trigger(:pull_request_info_for_list_view_updated, { id: global_relay_id }, object: { title_updated: true })
        end
        Platform::Schema.subscriptions.trigger(:pull_request_title_updated, { id: global_relay_id })
      end
    end

    if issue.previous_changes.include?("issue_comments_count")
      actor = User.find_by(id: GitHub.context[:actor_id])
      if GitHub.flipper[:pull_request_sub_triggers].enabled?(actor)
        if GitHub.flipper[:pull_request_single_subscription].enabled?(actor)
          Platform::Schema.subscriptions.trigger(:pull_request_info_for_list_view_updated, { id: global_relay_id }, object: { comments_updated: true })
        end
        Platform::Schema.subscriptions.trigger(:pull_request_comments_updated, { id: global_relay_id })
      end
    end

    event_payload = GitHub.use_channel_event_builder? ? ChannelEventBuilder.new(self, associated_updates).build_payload : {}

    channel = GitHub::WebSocket::Channels.pull_request(self)
    GitHub::WebSocket.notify_pull_request_channel(self, channel, data.merge(event_payload))
  end

  #
  # Merging
  #

  # Determine if the head has been merged into the base.
  sig { returns(T::Boolean) }
  def merged?
    !merged_at.nil?
  end

  sig { returns(T.nilable(T::Boolean)) }
  def common_ancestor?
    async_common_ancestor?.sync
  end

  sig { returns(Promise[T.nilable(T::Boolean)]) }
  def async_common_ancestor?
    async_historical_comparison.then(&:common_ancestor?)
  end

  # Determine whether the base ref exists.
  sig { params(refresh_refs: T::Boolean).returns(T.nilable(T::Boolean)) }
  def base_ref_exist?(refresh_refs: false)
    return false unless base_repository = self.base_repository
    base_repository.clear_ref_cache if refresh_refs
    base_repository.heads.exist?(base_ref)
  end

  # For failbot-tracking creation of PRs with non-branch heads
  # https://github.com/github/github/pull/33519
  class NonBranchHeadError < StandardError
    sig { params(head: T.untyped).void }
    def initialize(head)
      @head = head
    end

    sig { returns(String) }
    def message
      "#{@head} is not a valid branch"
    end
  end

  # Determine whether the head ref exists.
  sig { params(refresh_refs: T::Boolean).returns(T.nilable(T::Boolean)) }
  def head_ref_exist?(refresh_refs: false)
    return false unless head_repository = self.head_repository
    return false unless head_ref = self.head_ref

    head_repository.clear_ref_cache if refresh_refs
    head_repository.heads.exist?(head_ref)
  end

  # Get missing ref names
  # Returns Array (1 or 2 elements), or nil if no refs are missing
  sig { returns(T.nilable(T::Array[String])) }
  def missing_refs
    result = []
    result.push display_base_ref_name if !base_ref_exist?
    result.push display_head_ref_name if !head_ref_exist?
    result.presence
  end

  # Determine if the head_ref can be safely deleted after a pull request is
  # merged. The head_ref must be deleteable by the user, and must not have
  # any commits ahead of the base.
  #
  # Returns true if we can safely delete the lingering branch, false otherwise
  sig { params(user: T.untyped).returns(T::Boolean) }
  def head_ref_safely_deleteable_by?(user)
    head_ref_deleteable_by?(user) && (merged? || is_head_merged_into_base?)
  end

  # Determine if the head_ref can be deleted in a way that could cause
  # commits to be lost. The pull request must be closed, the head_ref
  # must be deleteable by the user and contain commits that were not
  # merged into the base.
  #
  # Returns true if the head_ref can be deleted but the branch contains
  # unmerged commits, false otherwise
  sig { params(user: T.untyped).returns(T::Boolean) }
  def head_ref_unsafely_deleteable_by?(user)
    head_ref_deleteable_by?(user) && !(merged? || is_head_merged_into_base?)
  end

  # Determine if the head_ref can be deleted at all. The PR
  # must be closed, the head_repository pushable by the user,
  # the branch must exist and not be the repo's default branch,
  # and must point at the same commit that it did when the PR
  # was merged or closed. There cannot be any other open PRs
  # using the branch as its head or base.
  #
  # Returns true if the head_ref is deleteable, false otherwise.
  sig { params(user: T.untyped).returns(T::Boolean) }
  def head_ref_deleteable_by?(user)
    !!async_head_ref_deleteable_by?(user).sync
  end

  sig { params(user: T.untyped).returns(Promises::Boolean) }
  def async_head_ref_deleteable_by?(user)
    async_head_ref_deleteable_by_user_cache(user).then do |deleteable|
      deleteable && !other_open_pulls_using_head_ref?
    end
  end

  # Internal: Determine if deletion would be allowed so long
  #           as other pull requests in this repository that
  #           reference the head ref as their base ref will be
  #           first updated to use this pull's base instead.
  #
  sig { params(user: T.untyped).returns(T::Boolean) }
  def head_ref_deleteable_after_updating_dependents?(user)
    async_head_ref_deleteable_after_updating_dependents?(user).sync
  end

  sig { params(user: T.untyped).returns(Promises::Boolean) }
  def async_head_ref_deleteable_after_updating_dependents?(user)
    async_head_ref_deleteable_by_user_cache(user).then do |deleteable|
      deleteable &&
        same_repo? &&
        merged? &&
        !other_open_pulls_using_head_ref_as_head?
    end
  end

  sig { params(user: T.untyped).returns(Promises::Boolean) }
  private def async_head_ref_deleteable_by_user_cache(user)
    @async_head_ref_deleteable_by_user_cache ||= { nil => Promise.resolve(false) }

    if @async_head_ref_deleteable_by_user_cache.key?(user&.id)
      return @async_head_ref_deleteable_by_user_cache[user&.id]
    end

    @async_head_ref_deleteable_by_user_cache[user.id] =
      Promise.all([
        async_head_repository,
        async_issue,
        async_head_repository_pushable_by?(user)
      ]).then do |head_repo, _issue, pushable_by_user|
        next false unless head_repo && closed?

        async_head_repository.then do |head_repo|
          head_repo.async_network.then do
            head_reference = head_repo.heads.find(head_ref.b)
            next false unless head_reference

            head_reference.deleteable?(deleter: user) &&
              head_reference.target_oid == head_sha &&
              pushable_by_user
          end
        end
      end
  end

  sig { void }
  private def falsify_head_ref_deleteable_by_user_cache
    promise = Promise.resolve(false)
    @async_head_ref_deleteable_by_user_cache&.transform_values! { |_| promise }
  end

  sig { returns(T::Boolean) }
  def other_open_pulls_using_head_ref_as_head?
    !!other_open_pulls_using_head_ref_as[:head]
  end

  sig { returns(T::Boolean) }
  def other_open_pulls_using_head_ref_as_base?
    !!other_open_pulls_using_head_ref_as[:base]
  end

  sig { returns(T::Boolean) }
  def other_open_pulls_using_head_ref?
    other_open_pulls_using_head_ref_as_base? || other_open_pulls_using_head_ref_as_head?
  end

  sig { returns(T::Hash[Symbol, T::Boolean]) }
  private def other_open_pulls_using_head_ref_as
    return @other_open_pulls_using_head_ref_as if defined?(@other_open_pulls_using_head_ref_as)

    values = self.class.connection.select_rows(Arel.sql(<<-SQL, repository_id: T.must(head_repository).id, ref: GitHub::SQL::ArelLiterals.binary(head_ref)))
      SELECT EXISTS (
        SELECT pr.id
        FROM pull_requests pr
        JOIN issues ON pr.id = issues.pull_request_id AND issues.repository_id = pr.repository_id
        WHERE
          pr.base_repository_id = :repository_id
          AND pr.base_ref = :ref
          AND issues.state = 'open'
      ) AS as_base,
      EXISTS (
        SELECT pr.id
        FROM pull_requests pr
        JOIN issues ON pr.id = issues.pull_request_id AND issues.repository_id = pr.repository_id
        WHERE
          pr.head_repository_id = :repository_id
          AND pr.head_ref = :ref
          AND issues.state = 'open'
      ) AS as_head
    SQL
    values.flatten!
    @other_open_pulls_using_head_ref_as = {
      base: values.first == 1,
      head: values.second == 1,
    }
  end

  # Public: Determine if this pull request or its repository are hidden from the given user.
  #
  # user - a User
  sig { params(user: T.untyped).returns(Promises::Boolean) }
  def async_hidden_from_or_repo_hidden_from?(user)
    promise = async_repository.then do |repo|
      next true unless repo
      Promise.all([repo.async_hide_from_user?(user),
                  T.unsafe(self).async_hide_from_user?(user)]).then do |repo_hidden, pr_hidden|
        repo_hidden || pr_hidden
      end
    end

    T.unsafe(promise)
  end

  # Delete the head_ref for a pull request if the head_ref can be safely
  # deleted.
  #
  # Returns true if we deleted the branch, false otherwise
  sig { params(user: T.untyped, reflog_data: Hash).returns(T::Boolean) }
  def cleanup_head_ref(user, reflog_data: {})
    unless head_ref_safely_deleteable_by?(user) ||
          head_ref_unsafely_deleteable_by?(user) ||
          head_ref_deleteable_after_updating_dependents?(user)
      return false
    end

    head_repository = T.must(self.head_repository)

    if user.using_auth_via_granular_actor?
      grant = ProgrammaticActor::Grant.with(user).with_target(head_repository.owner)
      return false unless head_repository.resources.contents.writable_by?(grant)
    end

    if head_ref_deleteable_after_updating_dependents?(user)
      return false unless update_base_of_dependent_prs(actor: user)
    end

    ref = head_repository.heads.build(head_ref, head_sha)
    reflog = pr_reflog_data("cleanup head ref").merge(reflog_data)
    ref.delete(user, reflog_data: reflog)
    create_head_ref_event(:deleted, user)
    falsify_head_ref_deleteable_by_user_cache
    true
  rescue Git::Ref::ComparisonMismatch
    false
  end

  # Restores the head_ref for a pull request if it doesn't exist.
  #
  # Returns true if we restored the branch, or false.
  sig { params(user: T.untyped, reflog_data: Hash).returns(T::Boolean) }
  def restore_head_ref(user, reflog_data = {})
    return false unless head_ref_restorable_by?(user)

    ref = T.must(head_repository).heads.build(head_ref)
    reflog = pr_reflog_data("restore head ref").merge(reflog_data)

    ref.create(head_sha, user, reflog_data: reflog)
    create_head_ref_event(:restored, user)

    true
  rescue Git::Ref::ComparisonMismatch
    false
  end

  sig { returns(T::Boolean) }
  def has_required_objects?
    return true unless cross_repo?

    repository = T.must(self.repository)

    if in_advisory_workspace?
      !!repository.rpc.object_exists?(mergeable_base_sha, "commit")
    else
      !!repository.rpc.object_exists?(head_sha, "commit")
    end
  end

  # Can this pull request be merged? If the mergeable state is unknown,
  # fire off a background job to update mergeable state.
  #
  # enqueue - Boolean that determines if the background job should be fired.
  #           Default: true.
  #
  # Returns true/false, or nil if unknown.
  sig { params(enqueue: T::Boolean).returns(T.nilable(T::Boolean)) }
  def git_merges_cleanly?(enqueue: true)
    enqueue_mergeable_update if enqueue
    currently_mergeable?
  end

  # Public: Enqueues a background job to create a new merge commit if
  #         the current mergeability status is out of date.

  sig { params(priority: Symbol).void }
  def enqueue_mergeable_update(priority: :low)
    PullRequests::MergeCommit.enqueue_create(pull_request: self, priority:)
  end

  # Public: Is this pull request mergeable?
  #
  # Returns true if so, false if not, or nil if outdated or uncomputed
  sig { returns(T.nilable(T::Boolean)) }
  def currently_mergeable?
    return false if !base_ref_exist?

    GitHub.dogstats.increment("pull_request", tags: ["action:git_merges_cleanly"])

    if mergeable?
      merge_commit_up_to_date? ? true : nil
    else
      mergeable
    end
  end

  # Public: Get a merge state, dependant on the viewer. This will cache
  # intelligently on the viewer argument, so this method is preferable to merge_state.
  #
  # viewer: the viewing user for context
  # merge_method: the merge method being used (squash, merge, rebase)
  sig { params(viewer: T.untyped, merge_method: T.nilable(Symbol)).returns(MergeState) }
  def cached_merge_state(viewer: nil, merge_method: nil)
    @merge_states ||= Hash.new

    result = @merge_states.fetch(viewer, nil)

    # PullRequest::MergeState#status is calculated based on the value of merge_method.
    # If the specified merge_method is nil or matches the cached value, we can safely return the cached status.
    # However, if it differs, we need to re-compute the status.
    return result if result && (merge_method.nil? || merge_method == result.merge_method)

    @merge_states[viewer] = merge_state(viewer: viewer, merge_method: merge_method)
  end

  # Public: Is this pull request currently in an unknown merge state for the specified viewer?
  #
  # viewer - the currently authenticated User or nil
  #
  # Returns a Boolean.
  sig { params(viewer: T.untyped).returns(T::Boolean) }
  def unknown_merge_state?(viewer: nil)
    cached_merge_state(viewer: viewer).status == :unknown
  end

  # Get merge state for view.
  #
  # enqueue: a Boolean of whether or not a background job should be enqueued to find the mergeable state.
  #          Default: true.
  # viewer: the viewing user for context
  sig { params(viewer: T.untyped, merge_method: T.nilable(Symbol)).returns(MergeState) }
  def merge_state(viewer: nil, merge_method: nil)
    MergeState.new(self, viewer: viewer, merge_method: merge_method)
  end

  # Public: The user that merged the pull request.
  #
  # Returns User
  def merged_by
    return nil unless merged?

    T.must(issue).merge_events.last.try(:actor)
  end

  # Public: Test whether the merge_commit_sha is unset or is set but references a
  # missing git object.
  #
  # Used to determine whether the merge commit should be rebuilt in PR#merge.
  #
  sig { returns(T::Boolean) }
  def merge_commit_missing?
    merge_commit_sha.blank? ||
      !T.must(repository).commits.exist?(merge_commit_sha)
  end

  # Public: Test whether the merge_commit_sha is set and up to date.
  #
  # Up to date means it's pointing to the current mergeable head
  # and base commits.
  sig { returns(T::Boolean) }
  def merge_commit_up_to_date?
    return false if merge_commit_sha.blank? ||
                    mergeable_base_sha.blank? ||
                    mergeable_head_sha.blank?

    merge_commit = T.must(repository).commits.find(merge_commit_sha)
    merge_commit.parent_oids == [mergeable_base_sha, mergeable_head_sha]
  rescue GitRPC::ObjectMissing => e
    # see github/github#54955 - merge commit may have been GC'd
    false
  end

  # Sets the mergeable attribute like update_attribute :mergeable but does not
  # change the updated_at timestamp. Otherwise, the pull request is displayed as
  # updated every time the base ref changes and the mergeable flag is reset.
  sig { params(value: T.untyped).void }
  def update_mergeable_attribute(value)
    write_attribute(:mergeable, value)
    PullRequest.where(id: id, merged_at: nil).update_all(mergeable: value) if id
    value
  end

  # Run RPC#create_merge_commit to generate a merge commit for this
  # pull request. Sets #mergeable to true/false based on the result
  #
  # Returns the merge commit sha on success,
  # false when there were merge conflicts,
  # or nil on other errors.
  sig { params(priority: Symbol, skip_rebase: T::Boolean).returns(T.nilable(T.any(T::Boolean, String))) }
  def create_merge_commit(priority: :high, skip_rebase: false)
    if merged_at? || closed?
      skip_tags = []
      skip_tags << "reason:merged_at" if merged_at?
      skip_tags << "reason:closed" if closed?

      GitHub.dogstats.increment("pull_request.create_merge_commit.skipped", tags: skip_tags)
      return nil
    end

    unless base_ref_exist?
      GitHub.dogstats.increment("pull_request.create_merge_commit.skipped", tags: ["reason:base_ref_missing"])
      return false
    end

    if in_advisory_workspace? && !has_required_objects?
      T.must(repository).fetch_workspace_base_ref!(base_sha: current_base_sha, origin_for_stats: "create_merge_commit")
    end

    unless has_required_objects?
      GitHub.dogstats.increment("pull_request.create_merge_commit.skipped", tags: ["reason:missing_required_objects"])
      return false
    end

    # #mergeable is nullified any time the pull is synchronized so
    # #conflict must be used to determine the prior mergeable state
    previous_mergeable = conflict.nil?
    previously_unknown = mergeable_unknown?

    # A rebase commit can be required even if the rebase merge strategy is
    # disabled for a repository because the user can still perform a rebase
    # on the PR UI.  However, if the merge commit strategy _and_ rebase
    # merge strategy is disabled, then it does not matter how a PR is updated
    # as the end result is always the same (a single squash commit).
    # Therefore we disable the rebase update strategy and don't need the
    # rebase commit.
    skip_rebase ||= repository&.feature_enabled?(:cprmc_skip_rebase_via_api) &&
      !merge_commit_allowed? &&
      !rebase_merge_allowed?

    mergeable, merge_commit_sha = Prepare.new(pull: self, priority: priority, skip_rebase: skip_rebase).perform

    update_mergability(mergeable, merge_commit_sha, previous_mergeable, previously_unknown)
  end

  def update_mergability(mergeable, merge_commit_sha, previous_mergeable, previously_unknown)
    update_count = 0

    if mergeable
      update_count = PullRequest.where(id: id, repository_id: repository_id, head_sha: head_sha, merged_at: nil).update_all({
        mergeable: mergeable,
        merge_commit_sha: merge_commit_sha,
      })

      if update_count > 0
        write_attribute(:mergeable, mergeable)
        write_attribute(:merge_commit_sha, merge_commit_sha)
        clear_attribute_changes([:mergeable, :merge_commit_sha])

        destroy_conflict_metadata
      else
        write_attribute(:mergeable, nil)
        clear_attribute_changes([:mergeable])
      end
    else
      update_count = PullRequest.where(id: id, repository_id: repository_id, head_sha: head_sha).update_all(mergeable: mergeable)

      if update_count > 0
        write_attribute(:mergeable, mergeable)
        clear_attribute_changes([:mergeable])
      else
        write_attribute(:mergeable, nil)
        clear_attribute_changes([:mergeable])
      end
    end

    if update_count > 0
      synchronize_search_index

      if previously_unknown || mergeable != previous_mergeable
        instrument_mergeability
      end

      if GitHub.flipper[:notify_on_merge_state_change].enabled?(repository)
        channel = GitHub::WebSocket::Channels.pull_request_git_merge_state(self)
        GitHub::WebSocket.notify_pull_request_channel(
          self,
          channel,
          {
            wait: default_live_updates_wait,
            pull_request_id: id,
          },
        )
      end
    end

    mergeable && merge_commit_sha
  end

  sig { void }
  def notify_git_merge_state_channel
    if repository&.feature_enabled?(:notify_on_merge_state_change)
      GitHub::WebSocket.notify_pull_request_channel(
        self,
        GitHub::WebSocket::Channels.pull_request_git_merge_state(self),
        {
          wait: default_live_updates_wait,
          pull_request_id: id,
        },
      )
    end
  end

  # Returns true when we haven't successfully calculated git mergeability
  sig { returns(T::Boolean) }
  def mergeable_unknown?
    !!(!mergeable && conflict.nil?)
  end

  sig { void }
  def instrument_mergeability
    return if mergeable_unknown?

    instrument(
      :mergeability,
      pull_request_id: id,
      mergeable: mergeable,
    )
  end

  sig { returns(RebaseState) }
  def rebase_state
    return @rebase_state if defined? @rebase_state

    @rebase_state = RebaseState.new(self)
  end

  # Public: Was a rebase prepared successfully?
  sig { returns(T.nilable(T::Boolean)) }
  def rebase_prepared?
    rebase_state.prepared?
  end

  # Public: Was a rebase prepared and is it "safe"?
  sig { returns(T.nilable(T::Boolean)) }
  def rebase_safe?
    rebase_state.safe?
  end

  # Builds the full ref for Pull Request merge commits.
  #
  # Returns a ref name.
  sig { returns(String) }
  def merge_ref
    @merge_ref ||= "refs/pull/#{number}/merge"
  end

  # Builds the full ref for Pull Request rebase commits.
  #
  # Returns a ref name.
  sig { returns(String) }
  def rebase_ref
    @rebase_ref ||= "refs/__gh__/pull/#{number}/rebase"
  end

  # Perform the merge described by this pull request.
  # Requires a #git_merges_cleanly? pull prepared via #create_merge_commit.
  #
  # actor   - User object of the GitHub user initiating the merge
  #           (optional, defaults to PR creator)
  # author_email - Custom email the user has chosen for this merge commit
  #                 (optional, if user doesn't make a selection will default to git email)
  # message_title - String commit message title to prefix the merge message
  #                 (optional, defaults to the default
  #                 "Merge pull request #N from repo/branch" text)
  # message - String commit message to append to the merge message
  #           (optional, defaults to PR title)
  # reflog_data   - Hash of reflog data to go with the ref update.
  #                 (optional)
  # expected_head - String commit OID where PR head ref is expected to be
  #                 (optional)
  # method - Symbol that sets the merge method to perform. Can be one of
  #          :merge, :squash or :rebase. (optional, defaults to :merge)
  # merge_action - Symbol that we use to log which type of action was taken that resulted in the merge.
  #                One of :indirect_merge, :direct_merge, :admin_override_merge, :auto_merge, or :merge_queue_merge
  #                This is only for instrumentation purposes.
  # merge_state_status: - Symbol that we use to log the merge state status when the merge is triggered.
  #                       One of :behind, :blocked, :clean, :dirty, :draft, :has_hooks, :unknown, or :unstable
  #                       This is only for instrumentation purposes.
  #
  # Returns two-or-three-element array
  #   on success: [true,  the merge commit SHA]
  #   on failure: [false, explanatory failure message, Symbol failure code]
  def merge(actor = user, author_email: nil, message_title: nil, message: nil, reflog_data: {}, expected_head: nil, method: :merge, merge_action: nil, merge_state_status: nil)
    merge_state_status = T.let(merge_state_status, T.nilable(Symbol))
    message_title = T.let(message_title, T.nilable(String))
    message = T.let(message, T.nilable(String))

    GitHub.dogstats.time("pullrequest.merge") do
      merger = Merge.new(self, method, actor, author_email: author_email, message_title: message_title, message: message)
      validate_result = GitHub.tracer.in_span("#{T.unsafe(self.class.name).underscore}.merge.prepare_and_validate", kind: :internal, attributes: {
        "gh.actor.id" => actor.id,
        "gh.pull_request.id" => self.id,
        "gh.pull_request.merge_method" => method.to_s,
      }) do
        merger.prepare_and_validate(expected_head)
      end
      return [validate_result.success, validate_result.fail_message, validate_result.fail_code] unless validate_result.success
      merge_commit = validate_result.merge_commit
      merge_base_ref = validate_result.merge_base_ref

      perform_result = GitHub.tracer.in_span("#{T.unsafe(self.class.name).underscore}.merge.perform", kind: :internal, attributes: {
        "gh.actor.id" => actor.id,
        "gh.pull_request.id" => self.id,
        "gh.pull_request.merge_method" => method.to_s,
      }) do
        merger.perform
      end
      return [perform_result.success, perform_result.fail_message, perform_result.fail_code] unless perform_result.success
      new_sha = perform_result.new_sha

      if new_sha
        # now that the new commit object is there, update the pull request and branches
        merge_base_ref.update(new_sha, actor, rule_commit: merge_commit,
                              reflog_data: pr_reflog_data("merge").merge(reflog_data),
                              post_receive: false,
                              pull_request: self,
                              server_merge: true,
                              merge_method: method)
        # via the api, if nothing is passed in for the message and message_title, then the defaults are used
        message_title, message, uses_defaults = determine_merging_message(method, message_title, message)

        GitHub.tracer.in_span("#{T.unsafe(self.class.name).underscore}.merge.post_merge", kind: :internal, attributes: {
          "gh.actor.id" => actor.id,
          "gh.pull_request.id" => self.id,
          "gh.pull_request.merge_method" => method.to_s,
        }) do
          merger.post_merge(
          merge_commit,
          merge_base_ref,
          new_sha,
          merge_base_ref.written_at,
          merge_action,
          merge_state_status: merge_state_status,
          merge_commit_title: message_title,
          merge_commit_message: message,
          default_merge_commit_message_and_title: uses_defaults)
        end

        if head_repository&.delete_branch_on_merge?
          cleanup_head_ref(actor)
        end

        [true, new_sha]
      else
        [false, "Could not re-write the merge commit for some reason", :rewrite]
      end
    rescue Git::Ref::ProtectedBranchUpdateError => e
      [false, e.result.message, :protected_branch]
    rescue Git::Ref::WorkflowUpdatePolicyError => e
      [false, e.message, :workflow_policy_update_error]
    rescue Git::Ref::RepositoryRuleViolationError => e
      [false, e.detailed_message, :repository_rule_violation]
    rescue Git::Ref::ComparisonMismatch
      [false, "Base branch was modified. Review and try the merge again.", :parent_mismatch]
    end
  end

  def post_merge(
    actor,
    merge_commit,
    merge_base_ref,
    new_sha,
    merged_at,
    method,
    merge_action,
    merge_state_status: nil,
    enqueue_push_job: true,
    merge_commit_title: nil,
    merge_commit_message: nil,
    merge_base_sha: nil,
    default_merge_commit_message_and_title: true)

    if merge_base_sha.nil?
      merge_base_sha, _ = merge_commit.parent_oids
    end

    # Ensure that we don't leave merges in a half finished state (e.g. closing referenced
    # issues when the pull fails to be marked as merged). Also makes sure side effects tied to
    # after_commit hooks are not fired until all relevant records are committed to database.
    PullRequest.transaction do
      T.must(repository).update_pushed_at Time.now
      reload

      unless T.must(repository).feature_enabled?(:skip_merge_commit_referenced_issue_event)
        T.must(issue).reference_from_commit(actor, new_sha, repository)
      end

      mark_as_merged(actor, new_sha, merge_base_sha, merge_action)
      save!
    end

    PullRequestCloseReferencedIssuesJob.perform_later(pull_request: self, actor: actor)

    merge_base_ref.enqueue_push_job(merge_base_sha, new_sha, actor, merged_at, merge_method: method, merge_action: merge_action) if enqueue_push_job

    # There have been a handful of cases of PRs being merged and not closed.
    # Sometimes it's due to a timeout and sometimes the request returns a 200
    # and there is no corresponding timeout needle. This will report to Failbot
    # if the bad state is not due to a timeout. See Issue::State#close for
    # additional reporting for the same bug.
    #
    # TODO: remove once we've determined the cause of the bug.
    #
    if reload && merged? && open?
      boom = PRMergedAndNotClosed.new("PR not closed in post-merge")
      boom.set_backtrace(caller)
      Failbot.report(boom, "gh.pull_request.id": id, app: "github-pull-requests")
    end

    GlobalInstrumenter.instrument("pull_request.merge", {
      pull_request: self,
      actor: actor,
      author: user,
      protected_branch: self.base_branch_rule_evaluator&.original_protected_branch,
      merge_method: method,
      merge_action: merge_action,
      merge_state_status: merge_state_status,
      merge_commit_title: merge_commit_title,
      merge_commit_message: merge_commit_message,
      default_merge_commit_message_and_title: default_merge_commit_message_and_title,
      merge_commit_sha: new_sha
    })
    instrument(:merge, actor: actor)

    GitHub.dogstats.increment("pull_request", tags: ["action:merged", "result:#{method}"])

    if !combined_status.any?
      GitHub.dogstats.increment("status", tags: ["action:merged", "result:none"])
    else
      GitHub.dogstats.increment("pull_request", tags: ["action:merged", "result:failure"]) if combined_status.state == "failure"
      GitHub.dogstats.increment("pull_request", tags: ["action:merged", "result:pending"]) if combined_status.state == "pending"
      GitHub.dogstats.increment("pull_request", tags: ["action:merged", "result:success"]) if combined_status.state == "success"
      if combined_status.count == 1
        GitHub.dogstats.increment("status", tags: ["action:merged", "result:single"])
      else
        GitHub.dogstats.histogram("status", combined_status.count, tags: ["action:merged", "result:more", "type:combined_count"])
      end
    end
  end

  # raised in order to report to Failbot when a PR is merged and not
  # subsequently closed.
  class PRMergedAndNotClosed < StandardError
  end

  # Public: Return an object to check how a pull can be updated.
  sig { returns(Updateability) }
  def updateability
    return @updateability if defined?(@updateability)
    @updateability = Updateability.new(self)
  end

  # Public: Attempt to merge latest base ref into head ref.
  #
  # user - A User performing the sync
  # expected_head_oid - String OID of expected head ref (default: head db value)
  #
  # @raise [PullRequest::PermissionError] if user has insufficient permissions.
  # @raise [PullRequest::RefMismatch] if expected head oid doesn't match current ref value.
  # @raise [PullRequest::MergeConflictError] if there was a merge conflict between the base and head.
  sig do
    params(
      user: User,
      author_email: T.nilable(String),
      expected_head_oid: T.nilable(String),
      base_oid: T.nilable(String),
      resolve_conflicts: T.nilable(T::Hash[Symbol, T.untyped])
    ).void
  end
  def merge_base_into_head(user:, author_email: nil, expected_head_oid: self.head_sha, base_oid: nil, resolve_conflicts: nil)
    GitHub.dogstats.time("pull_request.merge_base_into_head") do
      update = Update.new(pull: self, actor: user, author_email: author_email, expected_head_oid: expected_head_oid)
      update.merge(base_oid: base_oid, conflict_resolutions: resolve_conflicts)
      reload
    end
  end

  # Public: Attempt to rebase head ref on top of latest base ref.
  #
  # user - A User performing the sync
  # expected_head_oid - String OID of expected head ref (default: head db value)
  #
  # @raise [PullRequest::PermissionError] if user has insufficient permissions.
  # @raise [PullRequest::RefMismatch] if expected head oid doesn't match current ref value.
  # @raise [PullRequest::MergeConflictError] if there was a merge conflict between the base and head.
  sig do
    params(
      user: T.untyped,
      author_email: T.untyped,
      expected_head_oid: T.nilable(String),
    ).returns(PullRequest)
  end
  def rebase_head_on_base(user:, author_email: nil, expected_head_oid: self.head_sha)
    GitHub.dogstats.time("pull_request.rebase_head_on_base") do
      update = Rebase.new(pull: self, actor: user, author_email: author_email, expected_head_oid: expected_head_oid)
      update.rebase
      instrument(:rebase, actor: user)

      reload
    end
  end

  # Create a new branch with this pull request reverted.
  #
  # user        - the User that is responsible for the revert
  # reflog_data - optional metadata to be written to the reflog
  #
  # Returns a tuple of [Ref, error], only one of which will be present.
  #
  # error can be :not_revertable if #revertable_by? is not fulfilled
  #
  # See CommitsCollection#create_revert_commit for additional possible errors.
  sig { params(user: T.untyped, reflog_data: Hash, timeout: T.nilable(Numeric)).returns(T.any([Git::Ref, NilClass], [NilClass, Symbol])) }
  def revert(user, reflog_data = {}, timeout: nil)
    return [nil, :not_revertable] unless revertable_by?(user)

    revert_repository = T.must(async_pushable_repo_for(user).sync)

    if existing = revert_repository.heads.find(revert_branch_name)
      return [existing, nil]
    end

    base_repository = T.must(self.base_repository)
    base_commit = base_repository.heads.find(base_ref).target

    if revert_repository != base_repository
      revert_repository.rpc.fetch_commits(base_repository.shard_path, base_commit.oid)
    end

    backfill_base_sha_on_merge if base_sha_on_merge.nil?

    # Regardless of its name `squashed_commit` is actually present in both squash and rebase scenarios.
    # If the second parent of the commit does not exist (checked inside of squashed_commit)
    # and the first parent of the commit is the base commit of the PR,
    # then there is only one commit to revert, and not a range.
    #
    # We are interested in reverting with a GPG signature when possible.
    # So if there is only one commit - avoid using revert for range, and simply revert a single commit.
    single_commit_to_revert = squashed_commit&.parent_oids&.first == base_sha_on_merge

    # If `base_sha_on_merge` was set or could be backfilled,
    # and we're not reverting a merge commit or single squash/rebase commit,
    # but rather reverting a range of commits, then revert all commits
    # (only following the first parent) in the range between `base_sha_on_merge`
    # and `merge_commit_sha`.
    if base_sha_on_merge && merged_commit.nil? && !single_commit_to_revert
      revert_commit, error = revert_repository.commits.create_revert_commits_for_range(
        user,
        base_commit.oid,
        base_sha_on_merge,
        merge_commit_sha,
        timeout: timeout,
      )
    else
      revert_commit, error = revert_repository.commits.create_revert_commit(
        user,
        base_commit.oid,
        merged_commit ? T.must(merged_commit).oid : T.must(squashed_commit).oid,
        commit_message: merged_commit ? "Revert \"#{title}\"" : build_revert_commit_message(squashed_commit),
        mainline: merged_commit ? mainline_number_for_revert : 0,
      )
    end

    if !revert_commit && !error
      GitHub.logger.info("Pull Request revert commit nil",
        "gh.repo.id": repository_id,
        "gh.pull_request.id": id,
        "gh.pull_request.merge_commit_sha": merged_commit&.oid,
        "gh.pull_request.base_sha_on_merge": base_sha_on_merge,
        "gh.pull_request.single_commit": single_commit_to_revert,
      )
    end

    return [nil, error] if error

    revert_branch = revert_repository.heads.create(
      revert_branch_name,
      revert_commit,
      user,
      reflog_data: pr_reflog_data("revert").merge(reflog_data),
    )

    [revert_branch, nil]
  rescue Git::Ref::ExistsError
    [T.must(revert_repository).reload.heads.find(revert_branch_name), nil]
  end

  # This method mimics the behavior of gitrpc/backend/create_revert_commit.rb #build_revert_commit_message method.
  # It takes the commit summary and combines it with the commit oid.
  sig { params(commit: T.untyped).returns(String) }
  def build_revert_commit_message(commit)
    <<-EOS
Revert "#{Commits::CommitMessage.new(commit.message).subject}"

This reverts commit #{commit.oid}.
    EOS
  end

  sig { returns(String) }
  def revert_branch_name
    @revert_branch_name ||= "revert-#{number}-#{head_ref_name}"
  end

  # Since  https://github.com/github/github/pull/135509 we can revert pull
  # requests merged with commits we didn't make, so we need to examine the
  # merge commit relative to the PR head to determine the correct mainline
  # number (i.e. the 1-based index of the parent that is *not* the PR's
  # head_sha.
  #
  # @raise [RevertError]
  sig { returns(Numeric) }
  def mainline_number_for_revert
    fail(RevertError, "missing merged_commit (#{id})") unless merged_commit = self.merged_commit
    parent_oids = merged_commit.parent_oids
    fail(RevertError, "cannot handle octopus merges (#{id})") unless parent_oids.size == 2
    case head_sha
    when parent_oids.first then 2
    when parent_oids.last  then 1
    else
      fail RevertError, "invariant violated (#{id}): head #{head_sha} is not among merge's (#{merged_commit.oid}) parents"
    end
  end

  # Internal: Determine and store the value for `base_sha_on_merge`.
  #
  # The `base_sha_on_merge` column was added to Pull Requests in November 2016.
  # It is used to determine the range of commits to revert in the case of a
  # "rebase-merged" pull request. It is also used when indexing pull requests
  # to build backlinks from commits to pull requests.
  #
  # This method tries to determine the correct value for `base_sha_on_merge`
  # for pull requests that were merged before this column was added.
  sig { void }
  def backfill_base_sha_on_merge
    value = determine_base_sha_on_merge
    return unless value

    write_attribute :base_sha_on_merge, value
    PullRequest.where(id: id).update_all base_sha_on_merge: value
  end

  # Internal: Determine and return the value for `base_sha_on_merge`.
  #
  # This determines the correct value for `base_sha_on_merge` for
  # all different merge methods we support.
  #
  # This will try to link the commit id stored in the merge event to the
  # earliest entry in the `pushes` table via the
  # `pushes.after` column. If we find such an entry, the `before` column
  # will contain the `base_sha_on_merge` value we're looking for.
  sig { returns(T.nilable(String)) }
  def determine_base_sha_on_merge
    merge_event = events.merges.last
    return unless merge_event && merge_event.actor_id && merge_event.commit_id

    GitHub.dogstats.time("pull_request.determine_base_sha_on_merge") do
      # We fetch the value for base_sha_on_merge
      # by finding the entry in the `pushes` table that correlates to the
      # merge recorded in the "merged" issue event.
      #
      # We assume the earliest push event that matches is the one that
      # corresponds to the merge.
      repositories_domain.pushes.first_before_sha_for(
        repository_id: T.must(base_repository_id),
        ref: "refs/heads/#{base_ref}",
        pusher_id: merge_event.actor_id,
        after: merge_event.commit_id)
    end
  end

  # Is the user able to revert this pull request?
  #
  # If yes, returns the Repository from which they can revert it.
  # If no, returns false.
  sig { params(user: T.untyped).returns(T.nilable(T::Boolean)) }
  def revertable_by?(user)
    return false unless user

    GitHub.dogstats.time("pull_request", tags: ["action:revertable_by"]) do
      merged_event = events.merges.last
      return false unless merged_event

      merged_event.async_revertable_by?(user).sync
    end
  end

  # Find a repository that the user could potentially
  # submit a pull request from. Chooses a repo in this
  # order, provided they have push access:
  #
  # 1. The base repository
  # 2. The head repository
  # 3. A fork that the user owns
  # 4. A fork that the user has push access to
  sig { params(user: T.untyped).returns(Promise[T.nilable(Repository)]) }
  def async_pushable_repo_for(user)
    @pushable_repo_by_user ||= {}
    return @pushable_repo_by_user[user] if @pushable_repo_by_user.has_key?(user)

    @pushable_repo_by_user[user] = async_pushable_repo_for!(user)
  end

  sig { params(user: T.untyped).returns(Promise[T.nilable(Repository)]) }
  def async_pushable_repo_for!(user)
    return T.unsafe(Promise).resolve(nil) if user.nil?

    async_base_repository_pushable_by?(user).then do |writable|
      next base_repository if writable

      async_head_repository_pushable_by?(user).then do |writable|
        next head_repository if writable
        next nil unless base_repository

        # TODO: This could use a dedicated AssociatedRepositories loader
        T.must(base_repository).find_pushable_forks_in_network_for_user(user).sort_by do |fork|
          user == fork.owner ? 0 : 1
        end.first
      end
    end
  end

  # The merge commit that was used to merge the PR
  # into the base branch. This may not be present
  # if the merge was a fast-forward, as it could
  # be if done on the command line.
  sig { returns(T.nilable(Commit)) }
  def merged_commit
    return nil unless merged?
    return @merged_commit if defined?(@merged_commit)

    @merged_commit = begin
      commit = events.merges.last.try(:commit)
      commit if commit.merged_from?(head_sha)
    end
  end

  # The commit that was created on the base branch that contains
  # all the changes of the PR squashed together.
  sig { returns(T.nilable(Commit)) }
  def squashed_commit
    return nil unless merged?
    return @squashed_commit if defined?(@squashed_commit)

    @squashed_commit = begin
      commit = events.merges.last.try(:commit)
      commit if commit && commit.parent_oids.length == 1 && commit.oid != head_sha
    end
  end

  sig { params(actor: T.untyped).returns(String) }
  def squash_commit_author_email(actor)
    author = user || actor
    author.default_author_email(repository, head_sha) || author.git_author_email
  end

  sig { params(actor: T.untyped).returns(String) }
  def merge_commit_author_email(actor)
    actor.default_author_email(repository, head_sha) || actor.git_author_email
  end

  #
  # Creation Helpers and Finders
  #

  # Creates a PullRequest with dependent Issue for the given repo.
  #
  # repo    - Repository that is receiving the Pull Request.
  # options - Hash with these keys:
  #           user  - The User that is creating the Pull Request.
  #           base  - String SHA marking the starting point on the root
  #                   repository.
  #                   ex: "user:branch-ref"
  #           head  - String SHA marking the latest commit.
  #                   ex: "user:branch-ref"
  #           head_repo  - Repo for the head.
  #           comparison - Optional `GitHub::Comparison` object to reuse for
  #                        building the pull request.
  #           issue - Optional Issue for the PullRequest.  If empty, a title
  #                   and body must be passed to create one.
  #           title - String title for the created Issue.
  #           body  - String body for the created Issue.
  #           draft  - Boolean indicating if this PullRequest is still a draft/work in progress
  #           reviewer_user_ids - Array of user.ids that are to be requested review
  #           reviewer_team_ids - Array of team.ids that are to be requested review
  #
  # Returns a PullRequest that is either saved or invalid.
  sig { params(repo: Repository, options: Hash).returns(PullRequest) }
  def self.create_for(repo, options)
    unless options[:base].present? && options[:head].present?
      pull_request = repo.pull_requests.build
      pull_request.errors.add(:base, "can't be blank") unless options[:base].present?
      pull_request.errors.add(:head, "can't be blank") unless options[:head].present?
      return pull_request
    end

    existing_issue = pull_request = issue = nil

    # strip away "refs/heads/" prefix from head and base if they are passed in and a ref exists for the branchname
    head = format_to_safe_ref_name(options[:head])
    base = format_to_safe_ref_name(options[:base])

    comparison = options[:comparison] || repo.comparison(base, head, head_repo: options[:head_repo])
    pull_request = comparison.build_pull_request(
      user: options[:user],
      user_hidden: !!options[:user_hidden],
      draft: (options[:draft] && repo.plan_supports?(:draft_prs)) || false,
    )

    if pull_request.draft?
      pull_request.reviewable_state = :draft
    end

    return pull_request if !pull_request.valid?

    issue = options[:issue] ||
      repo.issues.build(
        title: options[:title],
        body: options[:body],
        user: options[:user],
        user_hidden: !!options[:user_hidden],
      )

    issue.repository = repo
    issue.pull_request = pull_request

    if !issue.valid?
      raise ActiveRecord::RecordInvalid, issue
    end

    existing_issue = !issue.new_record?
    pull_request.issue = issue

    if options[:collab_privs] || (options[:maintainer_can_modify] && pull_request.cross_repo?)
      pull_request.fork_collab_state = :allowed
    end

    reviewers  = User.where(id: options[:reviewer_user_ids] || [])
    reviewers += Team.where(id: options[:reviewer_team_ids] || [])
    pull_request.request_review_from(reviewers: reviewers, actor: options[:user], should_save: false)

    if issue.created_by_dependabot? && options[:dependabot_update_id].present?
      dependency_update = repo.dependency_updates.preload(:pull_request).find_by(id: options[:dependabot_update_id])

      if dependency_update.present?
        dependency_update.state = "complete"
        pull_request.dependency_updates = [dependency_update]
      else
        pull_request.errors.add(:dependency_updates)
        raise ActiveRecord::RecordInvalid, pull_request
      end
    end

    begin
      PullRequest.transaction do
        pull_request.save!
      end
    rescue # rubocop:disable Lint/GenericRescue
      # ProjectCards that got created are in an invalid state if the PR fails to save,
      # so we want to clean them up.
      if pull_request.issue
        card_ids = pull_request.issue.cards.map(&:id)
        if card_ids.any?
          ProjectCard.where(id: card_ids).delete_all
        end
      end
      raise
    end

    pull_request.instrument(:create, actor: options[:user], user_id: options[:user].id)
    GlobalInstrumenter.instrument("pull_request.create", { pull_request: pull_request })

    pull_request
  rescue DetermineCodeownersError
    # It's very unlikely this will happen, but there was an error
    # checking the new pull's diff to determine codeowner rules to apply.
    pull_request.errors.add(:base, :determine_codeowners, message: "Could not determine codeowners for the diff")
    pull_request
  ensure
    # this needs to be outside the transaction
    if pull_request && !pull_request.new_record? && existing_issue
      issue.instrument_transform_to_pull
      RemoveFromSearchIndexJob.perform_later("issue", issue.id, issue.repository_id)
      MemexProjectItemIssueToPullJob.perform_later(
        repository_id: issue.repository_id,
        issue_id: issue.id,
        pull_request_id: pull_request.id)
    end
  end

  # Like PullRequest.create_for but raises an ActiveRecord::RecordInvalid
  # exception when validation fails.
  def self.create_for!(repo, options)
    res = create_for(repo, options)
    raise ActiveRecord::RecordInvalid, res if res.new_record?
    res
  end

  # Public: Find pull requests for the given branch name
  #
  # head - A String or Array of Strings with ref names.
  #
  # Returns an ActiveRecord scope.
  def self.for_branch(head, repository: nil)
    where(head_ref: Git::Ref.safe_ref_name(ref_names: head)).order("id")
  end

  # Public: Find pull requests for the given ref object
  #
  # ref - A Ref object
  #
  # Returns an ActiveRecord scope.
  def self.for_ref(ref)
    T.unsafe(self).where(head_repository_id: ref.repository.id).for_branch(ref.name, repository: ref.repository)
  end

  # expects ref to look like "user:branch" or "user:repo:branch"
  # strips away the prefix of the branch name
  # used in the .create_for method internally
  sig { params(ref: String).returns(String) }
  private_class_method def self.format_to_safe_ref_name(ref)
    ref.b.sub(%r{refs/heads/}, "")
  end

  # Finds an existing pull request with the same head and base refs as this pull
  # request. Useful in validations and deciding whether a PR is reopenable, to check for duplicates.
  sig { returns(T::Boolean) }
  def find_existing
    T.must(repository).pull_requests.
      joins(:issue).
      where("`issues`.`repository_id` = `pull_requests`.`repository_id`").
      where(
        base_ref: base_ref,
        head_ref: head_ref,
        base_repository_id: base_repository_id,
        head_repository_id: head_repository_id,
        issues: { state: "open" },
      ).exists?
  end

  # Public: Checks whether this is PR is across repos
  # (head and base repositories are not the same)
  sig { returns(T::Boolean) }
  def cross_repo?
    head_repository_id != base_repository_id
  end

  # Public: Checks whether this is PR is within a single repo
  # (head and base repositories are the same)
  sig { returns(T::Boolean) }
  def same_repo?
    !cross_repo?
  end

  # Public: Return commit ids that are linked to this pull request.
  #
  # limit - maximum number of commit ids to return.
  #
  # This includes:
  #   * commits between the `base_sha` and `head_sha`
  #   * merge commit for "normal" and squash merges
  #   * rebased commits for rebase merges
  def linked_commit_ids(limit: COMMIT_LIMIT)
    include_oids = [head_sha]
    exclude_oids = [base_sha]

    if merged? && base_sha_on_merge
      include_oids << merge_commit_sha
      exclude_oids << base_sha_on_merge
    end

    commit_ids = T.must(repository).rpc.rev_list(include_oids, exclude_oids: exclude_oids, limit: limit)

    # include the merge commit sha for pull requests that got merged before
    # `base_sha_on_merge` was introduced.
    #
    # TODO: Remove once `base_sha_on_merge` was backfilled.
    if merged? && !base_sha_on_merge
      commit_ids << merge_commit_sha
    end

    commit_ids.freeze
  end

  #
  # Active Comparison
  #

  # Determine whether the head repository exists. Falsey when the head
  # repository is deleted.
  sig { returns(T::Boolean) }
  def head_repository?
    !head_repository.nil?
  end

  # Determine whether the base and head refs still exist.
  sig { returns(T.nilable(T::Boolean)) }
  def refs_exist?
    head_repository? && base_ref_exist? && head_ref_exist?
  end

  # Determine if commits exist in the head branch that are not in the base branch.
  sig { returns(T.nilable(T::Boolean)) }
  def commits_pending?
    refs_exist? && comparison.ahead?
  end

  # Public: Check if head branch is behind base branch.
  #
  # PR may need to be sync'd with the base if not.
  sig { returns(T.nilable(T::Boolean)) }
  def behind_base?
    refs_exist? && comparison.behind?
  end

  # WARNING: Are you sure you don't want historical_comparison?
  # This is the live / active Comparison object used to determine the current state of
  # the pull request branch. THIS OBJECT IS ONLY VALID WHILE THE BASE AND THE HEAD EXIST.
  # Once either the base or -- more likely -- the head is deleted, the comparison ceases to be valid.
  # THIS WILL NOT BE VALID FOR MERGED PRS WITH DELETED BRANCHES. Use historical_comparison instead.
  sig { returns(GitHub::Comparison) }
  def comparison
    @comparison ||= T.must(repository).comparison(base, head, COMMIT_LIMIT, self)
  end

  #
  # Historical Comparison
  #

  # The historical comparison object provides a view of changes between the base
  # and head even after the head has been merged or deleted. This is necessary
  # because the active comparison ceases to provide useful information once the
  # head is merged or deleted.
  #
  # This is accomplished by storing and updating the SHA1s for the base and head
  # commits while the comparison is active and then using them once the pull
  # request is closed, or the branch is merged / deleted.
  sig { returns(GitHub::Comparison) }
  def historical_comparison
    async_historical_comparison.sync
  end

  sig { returns(Promise[GitHub::Comparison]) }
  def async_historical_comparison
    async_build_comparison(head_commit_oid: head_sha)
  end

  # Public: builds a PullRequest::Comparison for this pull request. By default
  #   the full range of the pull request is used.
  #
  # start_oid - the oid of the earliest commit for the comparison,
  #             defaulting to the merge base of the PR.
  # end_oid   - the oid of the latest commit for the comparison. Defaults to
  #             the head_sha of the pull request.
  # base_oid  - the oid of the merge base relevant to the range being viewed.
  #             defaults to the merge base of the PR.
  sig { params(start_oid: T.untyped, end_oid: T.untyped, base_oid: T.untyped).returns(Promise[PullRequest::Comparison]) }
  def async_pull_comparison(start_oid: merge_base, end_oid: head_sha, base_oid: merge_base)
    # kwargs can sometimes be passed as nil.
    # ex: `pull.async_pull_comparison(start_oid: @start_oid, end_oid: @end_oid)`
    # where @start_oid and @end_oid are nil.
    # These assignments are safeguarding against that case
    start_oid ||= merge_base
    end_oid ||= head_sha
    base_oid ||= merge_base

    @async_pull_comparison ||= {}
    @async_pull_comparison[[start_oid, end_oid, base_oid]] ||= PullRequest::Comparison.async_find(
      pull: self,
      start_commit_oid: start_oid,
      end_commit_oid: end_oid,
      base_commit_oid: base_oid
    )
  end

  sig { params(start_oid: T.untyped, end_oid: T.untyped, base_oid: T.untyped).returns(PullRequest::Comparison) }
  def pull_comparison(start_oid: merge_base, end_oid: head_sha, base_oid: merge_base)
    async_pull_comparison(start_oid: start_oid, end_oid: end_oid, base_oid: base_oid).sync
  end

  # Public: Use this method if you don't need the extra validation and methods of
  #   a full pull request comparison.
  sig { params(start_commit_oid: T.untyped, end_commit_oid: T.untyped, base_commit_oid: T.untyped, context_lines: T.untyped).returns(Promise[GitHub::Diff]) }
  def async_diff(start_commit_oid: merge_base, end_commit_oid: head_sha, base_commit_oid: merge_base, context_lines: nil)
    Promise.all([
      async_compare_repository,
      async_head_repository,
      async_base_repository,
    ]).then do |repo, head_repository, base_repository|
      options = {
        base_sha: base_commit_oid, context_lines: context_lines,
        base_repository: base_repository,
        head_repository: head_repository,
      }
      GitHub::Diff.new(repo, start_commit_oid, end_commit_oid, options)
    end
  end

  def compare_repository
    async_compare_repository.sync
  end

  def async_compare_repository
    return Promise.resolve(@compare_repository) if defined?(@compare_repository)

    async_repository_with_network = async_repository.then do |repository|
      repository.async_network.then { repository }
    end

    Promise.all([
      async_repository_with_network,
      async_head_repository,
      async_base_repository,
    ]).then do |repository, head_repository, base_repository|
      Platform::Loaders::CompareRepository.load(
        repository,
        head_repository: head_repository,
        base_repository: base_repository,
      ).then do |repo|
        @compare_repository = repo
      end
    end
  end

  sig { returns(T.nilable(String)) }
  def merge_base
    async_merge_base.sync
  end

  sig { returns(Promise[T.nilable(String)]) }
  def async_merge_base
    async_historical_comparison.then(&:async_merge_base)
  end

  sig { params(head_commit_oid: T.untyped, base_commit_oid: T.untyped).returns(GitHub::Comparison) }
  def build_comparison(head_commit_oid:, base_commit_oid: base_sha)
    async_build_comparison(base_commit_oid: base_commit_oid, head_commit_oid: head_commit_oid).sync
  end

  # A Comparison spanning the PR's base commit and given head commit.
  #
  # Optionally provide an alternative base commit. This is useful for inspecting
  # the state of the rollup diff at a previous point in the pull request's history.
  #
  # Returns Promise<GitHub::Comparison>
  sig { params(head_commit_oid: T.untyped, base_commit_oid: T.untyped).returns(Promise[GitHub::Comparison]) }
  def async_build_comparison(head_commit_oid:, base_commit_oid: base_sha)
    async_repository.then do |repo|
      if repo.feature_enabled?(:pull_request_async_build_comparison_memoize_result)
        async_build_comparison_with_memoized_result(head_commit_oid:, base_commit_oid:)
      else
        async_build_comparison_with_memoized_promise(head_commit_oid:, base_commit_oid:)
      end
    end
  end

  # This is similar to async_build_comparison, but does not use self.base_sha as the `before` of the diff. This is
  # important for branch protection and rule enforcement, to prevent commit-smuggling attacks.
  #
  # Specifically, if a malicious actor can move the merge-base after the PR is opened, they would be able to change
  # a file which requires specific reviewers. The file would not register as changed in a comparison built from the
  # (original base_sha)...head_sha diff, thus the reviewers requirement would not be enforced.
  sig { returns(Promise[GitHub::Comparison]) }
  def async_build_trusted_comparison
    find_commits_promise = case
    when closed?
      # OK to use historical comparison for a closed PR
      Promise.resolve([self.base_sha, self.head_sha])
    else
      # Use up-to-date merge base
      async_find_best_merge_base_sha(use_current_base_sha: true).then { [_1, self.head_sha] }
    end

    find_commits_promise.then do |(base_commit_oid, head_commit_oid)|
      async_build_comparison_with_memoized_result(head_commit_oid:, base_commit_oid:)
    end
  end

  sig { params(head_commit_oid: T.untyped, base_commit_oid: T.untyped).returns(Promise[GitHub::Comparison]) }
  private def async_build_comparison_with_memoized_result(head_commit_oid:, base_commit_oid: base_sha)
    @async_build_comparison_result ||= {}
    cache_key = [base_commit_oid, head_commit_oid]
    return Promise.resolve(@async_build_comparison_result[cache_key]) if @async_build_comparison_result.key?(cache_key)

    async_build_comparison_without_memoization(head_commit_oid:, base_commit_oid:).then do |comparison|
      @async_build_comparison_result[cache_key] ||= comparison
    end
  end

  sig { params(head_commit_oid: T.untyped, base_commit_oid: T.untyped).returns(Promise[GitHub::Comparison]) }
  private def async_build_comparison_with_memoized_promise(head_commit_oid:, base_commit_oid: base_sha)
    return @async_build_comparison[[base_commit_oid, head_commit_oid]] if defined?(@async_build_comparison)

    @async_build_comparison = Hash.new do |hash, (base_commit_oid, head_commit_oid)|
      async_comparison = async_build_comparison_without_memoization(base_commit_oid:, head_commit_oid:)
      hash[[base_commit_oid, head_commit_oid]] = async_comparison
    end

    @async_build_comparison[[base_commit_oid, head_commit_oid]]
  end

  sig { params(head_commit_oid: T.untyped, base_commit_oid: T.untyped).returns(Promise[GitHub::Comparison]) }
  private def async_build_comparison_without_memoization(head_commit_oid:, base_commit_oid: base_sha)
    async_advisory_parent_repository = async_in_advisory_workspace?.then do |is_in_advisory|
      next unless is_in_advisory
      async_repository.then(&:async_parent_advisory_repository)
    end

    Promise.all([
      async_base_repository,
      async_head_repository,
      async_repository,
      async_advisory_parent_repository,

      # TODO: The comparison accesses `pull.head_user` and `pull.base_user`
      #   Ideally this is passed to the `Comparison` or loaded when needed.
      async_base_user,
      async_head_user,
    ]).then do |base_repository, head_repository, repository|
      # If the users that created the PR are gone, we don't have anything
      # to compare with, so return an empty comparison.
      next repository.comparison(nil, nil) unless base_repository && head_commit_oid && base_commit_oid

      repositories = [base_repository, head_repository, repository].compact
      Promise.all(repositories.map(&:async_network)).then do
        GitHub::Comparison.build(
          base_repo: base_repository,
          head_repo: head_repository,
          base_revision: base_commit_oid,
          head_revision: head_commit_oid,
          limit: COMMIT_LIMIT,
          pull: self,
        ).tap do |comparison|
          comparison.set_context_lines(@additional_context_line_ranges) if @additional_context_line_ranges
        end
      end
    end
  end

  # Public: The historical diff for this pull request, with single entry limits maximized
  # for comment positioning.
  def historical_comments_diff
    return @historical_comments_diff if defined?(@historical_comments_diff)

    @historical_comments_diff = historical_comparison.diffs.only_params.tap do |diff|
      diff.maximize_single_entry_limits!
    end
  end

  # List of commits between the last known good head and base SHA1s. This does
  # not rely on the head repository or the head branch existing.
  #
  # Returns an Array of Commit objects.
  sig { returns(T::Array[Commit]) }
  def changed_commits
    async_changed_commits.sync
  end

  sig { returns(Promise[T::Array[Commit]]) }
  def async_changed_commits
    return @async_changed_commits if defined?(@async_changed_commits)

    @async_changed_commits =
      async_historical_comparison.then do |historical_comparison|
        historical_comparison.async_commits.then do |commits|
          commits = commits.compact.tap do |commits|
            fetching_changed_commits(commits)
          end

          StableSorter.new(commits).sort_by(&:timeline_sort_by)
        end
      end.catch do |error|
        case error
        when GitRPC::ObjectMissing, Repository::CommandFailed, GitHub::DGit::UnroutedError, GitRPC::CommandBusy
          @corrupt = true
          []
        else
          raise error
        end
      end
  end

  batch_method :prelude_changed_commits do |pulls|
    pulls = Array.wrap(pulls).compact
    results = Promise.all(pulls.map(&:async_changed_commits)).sync

    pulls.zip(results).to_h
  end

  def fetching_changed_commits(commits)
    Commit.prefill_users(commits)

    # preset these to avoid additional lookups
    commits.each do |commit|
      if head_repository&.deleted?
        commit.repository = base_repository || repository
      else
        commit.repository = head_repository || base_repository || repository
      end
    end

    short_keys = commits.map { |c| c.message_cache_key("short_message_html") }
    GitHub.cache.get_multi(short_keys) if short_keys.any?
  end

  sig { params(commit_oid: T.untyped).returns(Promise[T.nilable(Commit)]) }
  def async_load_pull_request_commit(commit_oid)
    Promise.all([
      async_repository,
      async_compare_repository,
    ]).then do |repository, compare_repository|
      async_load_commit = Platform::Loaders::GitObject.load(compare_repository, commit_oid).then do |commit|
        commit.repository = repository if commit

        commit
      end

      async_load_commit.then do |commit|
        next if commit.nil?
        Platform::Models::PullRequestCommit.new(self, commit)
      end
    end
  end

  # List of commits oids between the last known good head and base SHA1s.
  sig { returns(T::Array[String]) }
  def changed_commit_oids
    historical_comparison.rev_list
  end

  # Pull requests whose last known head or base SHA1s no longer resolve to valid
  # objects are considered corrupt. The first month or so of pull requests did
  # not have special "heads/pull/<id>/{head,base}" branches created for them and
  # so some of them commits were gc'd after the head branch was deleted.
  #
  # Use this method to check if the pull request is corrupt before accessing
  # commit information. Use the diff_available? method to check for corruptions
  # before accessing diff information.
  sig { returns(T::Boolean) }
  def corrupt?
    async_corrupt?.sync
  end

  def async_corrupt?
    return Promise.resolve(@corrupt) if defined?(@corrupt)

    async_changed_commits.then { !!@corrupt }
  end

  # Public: Total number of commits in the revision range, ignoring any limit
  # imposed on changed_commits.
  sig { returns(Numeric) }
  def total_commits
    async_total_commits.sync
  end

  sig { returns(Promise[Numeric]) }
  def async_total_commits
    async_corrupt?.then do |corrupt|
      next 0 if corrupt

      async_historical_comparison.then(&:async_total_commits)
    end
  end

  # Determine if the commit limit was exceeded (total_commits > changed_commits.size).
  sig { returns(T.nilable(T::Boolean)) }
  def commit_limit_exceeded?
    return false if corrupt?
    historical_comparison.commit_limit_exceeded?
  end

  # The GitHub::Diff object for the set of changes between the base and head
  # commits. No actual processing occurs when accessing this method. You must
  # access an attribute on the diff object to fire a real git operation.
  #
  # Use #set_diff_options to establish diff formatting options before accessing
  # this attribute.
  #
  # Returns a GitHub::Diff object.
  sig { returns(GitHub::Diff) }
  def diffs
    historical_comparison.diffs
  end

  # Set GitHub::Diff options and reset the memoized diffs object.
  #
  # options - :max_diff_size, :max_total_size, :max_files, :ignore_whitespace.
  #           See GitHub::Diff attribute docs for info on possible values.
  #
  sig { params(options: Hash).void }
  def set_diff_options(options = {})
    historical_comparison.set_diff_options(options)
  end

  # Pull requests whose last known head or base SHA1s no longer resolve to valid
  # objects are considered corrupt. The first month or so of pull requests did
  # not have special "heads/pull/<id>/{head,base}" branches created for them and
  # so some of them commits were gc'd after the head branch was deleted.
  #
  # Use this method to check if the pull request is corrupt before accessing
  # diff information.
  sig { returns(T.nilable(T::Boolean)) }
  def diff_available?
    diffs.available?
  end

  sig { params(current_user: T.untyped).returns(T.nilable(T::Boolean)) }
  def fork_collab_available_for_user?(current_user)
    current_user == user &&
    base_repository != head_repository &&
    head_repository &&
    T.must(head_repository).pushable_by?(current_user) &&
    !T.must(repository).advisory_workspace? &&
    !(T.must(head_repository).fork? && T.must(head_repository).owner.is_a?(Organization))
  end

  # The total number of changed files included in the diff.
  sig { returns(Numeric) }
  def changed_files
    historical_comparison.diffs.changed_files
  end

  FILES_CHANGED_INSTRUMENTATION_LIMIT = 200
  # When instrumenting this model, we have a shared contract with the Repositories team.
  sig { returns(Array) }
  def changed_files_for_instrumentation
    return [] unless GitHub.flipper[:instrument_pull_request_changed_files].enabled?(repository)

    historical_comparison.diffs.lazy.take(FILES_CHANGED_INSTRUMENTATION_LIMIT).map do |diff|
      Repositories::ChangedFile.new(
        repository: repository,
        ref: "refs/heads/#{head_ref}",
        previous_oid: diff.a_blob,
        oid: diff.b_blob,
        change_type: diff.status,
        path: diff.b_path,
        previous_path: diff.a_path,
        score: (diff.similarity || 0)
      )
    end.to_a
  end

  # Public: Number of lines added across all files.
  sig { returns(Numeric) }
  def additions
    historical_comparison.diffs.additions
  end

  # Public: Number of lines removed across all files.
  sig { returns(Numeric) }
  def deletions
    historical_comparison.diffs.deletions
  end

  sig { returns(Promise[Numeric]) }
  def async_changed_files
    async_historical_comparison.then do |comparison|
      comparison.async_diff(summary: true).then do |diff|
        diff.changed_files
      end
    end
  end

  sig { returns(Promise[Numeric]) }
  def async_additions
    async_historical_comparison.then do |comparison|
      comparison.async_diff(summary: true).then do |diff|
        diff.additions
      end
    end
  end

  sig { returns(Promise[Numeric]) }
  def async_deletions
    async_historical_comparison.then do |comparison|
      comparison.async_diff(summary: true).then do |diff|
        diff.deletions
      end
    end
  end

  # Update the base_sha and head_sha attributes to the best current values on
  # the active base and head branches, while accounting for merges from head
  # into base or from base into head. These values are used to build the changes
  # object.
  #
  # Returns true if either the base_sha or head_sha were changed, falsey if no
  # changes were made.
  sig { params(forced: T.untyped).returns(T.nilable(T::Boolean)) }
  def record_concrete_commit_points(forced = false)
    if !merged? && open?
      if refs_exist?
        previous_values = [base_sha, head_sha]
        write_attribute :base_sha, nil if forced
        write_attribute :base_sha, concrete_base_sha
        write_attribute :head_sha, comparison.head_sha
        if [base_sha, head_sha] != previous_values
          remove_instance_variable(:@async_build_comparison) if defined?(@async_build_comparison)
          remove_instance_variable(:@async_build_comparison_result) if defined?(@async_build_comparison_result)
          return true
        end
      else
        GitHub.dogstats.increment("pull_request.record_concrete_commit_points.skipped", tags: ["reason:refs_missing"])
      end
    end

    nil
  end

  # Maintains a special tracking ref in the repository for the head revision. This
  # ensures that the objects referenced by the pull request are not gc'd when
  # branches are deleted and old commits fall out of the reflog.
  #
  # actor - The User who triggered creation of the tracking ref.
  #         For use in the reflog.
  #
  # Returns true if the tracking ref was created or updated, nil otherwise.
  sig { params(actor: T.untyped, priority: Symbol).returns(T.nilable(T::Boolean)) }
  def maintain_tracking_ref(actor, priority: :high)
    # If this pull's issue or repository was destroyed, there is no need
    # to maintain the tracking ref anymore. This can happen if the
    # `maintain-tracking-ref` job is racing with repository deletion.
    return if issue.nil? && reload_issue.nil?
    return if repository.nil? && reload_repository.nil?

    issue = T.must(self.issue)
    repository = T.must(self.repository)
    user = safe_user

    # do a quick check to see if maybe the ref is already in place and current
    current_head = repository.refs.read("refs/pull/#{number}/head")
    return if current_head.target_oid == head_sha

    # Fetch any commits from the head repository that are not already
    # present in the base repository. This is necessary even in
    # repository networks because someone might try to submit a pull
    # request from a fork before the objects involved have been synced
    # to the network repository.
    if head_repository && head_repository != repository
      GitHub.dogstats.time("pull_request", tags: ["action:fetch_commits"]) do
        return unless repository.fetch_commits_from_network(head_repository, head_sha)
      end
    end

    backup = repository.feature_enabled?(:skip_update_pushed_at_on_ref_update) ? false : true

    # create the tracking ref
    ActiveRecord::Base.connected_to(role: :writing) do
      current_head.update(head_sha,
                          actor || user,
                          priority: priority,
                          post_receive: false,
                          backup: backup,
                          clear_ref_cache: true,
                          no_custom_hooks: false)
    end

    # Clean up possible unshipped PR tracking ref
    if history_chain_ref = repository.refs.find("refs/__gh__/pull/#{number}/heads")
      history_chain_ref.delete(actor || user)
    end

    true
  end

  # Same as #maintain_tracking_ref, but handles race conditions
  # around multiple processes trying to update the tracking ref.
  sig { params(actor: T.untyped, max_retries: Numeric, priority: Symbol).void }
  def maintain_tracking_ref_with_retries(actor, max_retries: 10, priority: :high)
    attempts = 0

    1.upto(max_retries.to_i) do
      begin
        attempts += 1

        if maintain_tracking_ref(actor, priority: priority)
          GitHub.dogstats.increment("pull_request", tags: ["action:maintain_tracking_ref", "result:success"])
        else
          GitHub.dogstats.increment("pull_request", tags: ["action:maintain_tracking_ref", "result:noop"])
        end

        break
      rescue Git::Ref::ComparisonMismatch => e
        if attempts == max_retries
          GitHub.dogstats.increment("pull_request", tags: ["action:maintain_tracking_ref", "result:failure"])
          raise e
        else
          reload
        end
      end
    end

    GitHub.dogstats.histogram("pull_request", attempts, tags: ["action:maintain_tracking_ref_attempts"])
  end

  sig { void }
  def record_tracking_ref_maintenance_required
    @tracking_ref_maintenance_required = true if saved_change_to_head_sha?
  end

  sig { void }
  def maintain_tracking_ref_later
    return if Rails.env.test? && disable_disk_access?
    return unless @tracking_ref_maintenance_required

    if repository&.feature_enabled?(:maintain_tracking_ref_importing_queue)
      MaintainTrackingRefJob.perform_later(id, user.try(:id), importing: importing?)
    else
      MaintainTrackingRefJob.perform_later(id, user.try(:id))
    end
    remove_instance_variable :@tracking_ref_maintenance_required
  end

  # Queues deletion of internal merge and rebase ref.
  sig { void }
  private def async_destroy_merge_refs
    DestroyMergeRefsJob.perform_later(self.id)
  end

  sig { void }
  def destroy_merge_refs
    T.must(repository).batch_write_refs(safe_user, [
      [merge_ref, nil, GitHub::NULL_OID],
      [rebase_ref, nil, GitHub::NULL_OID]
    ], clear_ref_cache: false, no_custom_hooks: true)
  end

  sig { void }
  def destroy_conflict_metadata
    conflict&.destroy
  end

  # Purge our tracking refs from disk.
  #
  # This code is intended for use by support when a user wants to remove a pull
  # request that has sensitive info.
  sig { void }
  def destroy_tracking_refs
    T.must(repository).batch_write_refs(safe_user, [
      ["refs/pull/#{number}/head", nil, GitHub::NULL_OID],
      ["refs/__gh__/pull/#{number}/heads", nil, GitHub::NULL_OID],
      [merge_ref, nil, GitHub::NULL_OID],
      [rebase_ref, nil, GitHub::NULL_OID]
    ], clear_ref_cache: false, no_custom_hooks: true)
  end

  # Detect if the head line has been merged into the base line
  sig { returns(T::Boolean) }
  def is_head_merged_into_base?
    async_is_head_merged_into_base?.sync
  end

  # Detect if the head line has been merged into the base line
  sig { returns(Promises::Boolean) }
  def async_is_head_merged_into_base?
    async_merge_comparison.then do |merge_comp|
      Promise.resolve(merge_comp.valid? && merge_comp.merged?)
    end
  end

  sig { returns(T.nilable(T::Boolean)) }
  def head_is_commit?
    return false unless head_repository = self.head_repository
    head_repository.commits.exist?(head_ref.b)
  rescue RepositoryObjectsCollection::InvalidObjectId
    false
  end

  # Detect if the saved head_sha can be reached from the new branch tip
  sig { returns(T.nilable(T::Boolean)) }
  def old_head_connected_to_new?
    return true if head_is_commit?
    return false unless head_ref_exist?

    head_repository = T.must(self.head_repository)
    old_sha = head_sha
    new_sha = head_repository.heads.find(head_ref.b).target_oid

    return true if new_sha == old_sha

    head_repository.rpc.descendant_of?(new_sha, old_sha)
  end

  # Mark the pull request as merged and close the issue.
  # Also close any issues fixed by this PR.
  #
  # actor           - The user who pushed to the base ref or performed some other
  #                   operation that changed the base lineage. This user is attributed
  #                   with the merge.
  # merge_sha       - The merge commit sha to use for IssueEvent#commit_id.
  # base_sha_on_merge - (Optional) The latest commit on the `base_ref` before
  #                   the merge was performed.
  sig { params(actor: T.untyped, merge_sha: T.untyped, base_sha_on_merge: T.untyped, merge_action: T.untyped).void }
  def mark_as_merged(actor = nil, merge_sha = nil, base_sha_on_merge = nil, merge_action = nil)
    write_attribute :merged_at, Time.now

    sha = merge_sha || merge_comparison.head_sha
    write_attribute(:merge_commit_sha, sha)
    write_attribute(:base_sha_on_merge, base_sha_on_merge)
    write_attribute(:mergeable, nil)

    if actor
      begin
        message = merge_action if MERGE_ACTION_MESSAGES.include?(merge_action)
        event = (merge_action == :merged_indirectly) ? :closed : :merged
        create_issue_event(event, actor, commit_id: sha, message: message)
      rescue ActiveRecord::RecordNotUnique
        GitHub.dogstats.increment("pull_request.mark_as_merged.record_not_unique")
        GitHub.logger.info("Pull Request attempted to persist 'merged' issue event when one already exists for the same sha",
          "gh.repo.id": repository_id,
          "gh.pull_request.id": id,
          "gh.pull_request.merge_commit_sha": sha,
          "gh.pull_request.base_sha_on_merge": base_sha_on_merge,
        )
        # no-op in the event that a merged event already exists for the pull request,
        # likely due to an overlap in synchronization
      end
    end

    close(actor, create_event: event != :closed) # Don't create a second close event if we already created one
  end

  # Public: Create a new IssueEvent for this PullRequest.
  #
  # event      - The String event name.  See IssueEvent::VALID_EVENTS.
  # actor      - The User performing the event.
  # attributes - Optional Hash of more IssueEvent properties to set.
  #
  # @raise [ActiveRecord::Error] ActiveRecord validation errors
  sig { params(event: T.untyped, actor: T.untyped, attributes: Hash).returns(IssueEvent) }
  def create_issue_event(event, actor, attributes = {})
    T.must(issue).events.create!(attributes.merge(event: event.to_s, actor: actor))
  end

  # Internal: Comparison object used for merge detection.
  #
  # This handles the cases where the head ref (or repository) are gone, but
  # the commit still exists or has been merged into the base.
  sig { returns(GitHub::Comparison) }
  def merge_comparison
    async_merge_comparison.sync
  end

  # Internal: Comparison object used for merge detection.
  #
  # This handles the cases where the head ref (or repository) are gone, but
  # the commit still exists or has been merged into the base.
  sig { returns(Promise[GitHub::Comparison]) }
  def async_merge_comparison
    return @merge_comparison if @merge_comparison

    # If the PR was closed because it contained 0 commits, check to see if
    # the head ref still exists. If so, use that for the comparison.
    # This lets the PR be reopenable if the ref exists and has had new commits added to it.
    async_closed_with_zero_commits?.then do |has_closed_with_zero_commits|
      comparison_head = head_sha

      if has_closed_with_zero_commits
        head_reference  = head_repository&.heads&.find(head_ref.b)
        comparison_head = head_reference&.target_oid
      end

      @merge_comparison = if current_base_sha && comparison_head
        Promise.resolve(GitHub::Comparison.build(
          base_repo: base_repository,
          head_repo: base_repository,
          base_revision: current_base_sha,
          head_revision: comparison_head,
          limit: COMMIT_LIMIT,
        ))
      else
        Promise.resolve(historical_comparison)
      end
    end
  end

  sig { returns(T.nilable(T::Boolean)) }
  def closed_with_zero_commits?
    async_closed_with_zero_commits?.sync
  end

  sig { returns(Promises::Boolean) }
  def async_closed_with_zero_commits?
    Promise.all([async_corrupt?, async_historical_comparison]).then do |is_corrupt, historical_comp|
      if is_corrupt
        Promise.resolve(false)
      else
        Promise.resolve(closed? && !merged? && historical_comp.zero_commits?)
      end
    end
  end

  # Public: Retrieve the timeline for the given viewer
  #
  # viewer         - A User that is viewing the timeline
  # filter_options - Hash of options passed to the timeline instance
  #
  # Returns Timeline::PullRequestTimeline
  sig { params(viewer: T.untyped, filter_options: Hash).returns(Timeline::PullRequestTimeline) }
  def timeline_model_for(viewer, filter_options = {})
    return @timeline_model_for[[viewer, filter_options]] if defined?(@timeline_model_for)

    @timeline_model_for = Hash.new do |hash, (v, f)|
      hash[[v, f]] = Timeline::PullRequestTimeline.new(self, viewer: v, filter_options: f)
    end
    @timeline_model_for[[viewer, filter_options]]
  end

  # Internal: For suggestions_params helper
  sig { returns(T.nilable(Numeric)) }
  def suggestion_id
    id
  end

  # Public: Find all Users that have commented or committed to this pull request,
  # or performed a participatory action.
  # Exclude Bots and users who no longer have access to this repo
  # (unless parent org has so many members that query may timeout).
  #
  # Note that the returned users are not filtered for spam.
  #
  # optimize_repo_access_checks - by default, #participants will check to make
  #                               sure that each user returned still has access
  #                               to the repo. If optimize_repo_access_checks is
  #                               set to true, that check will not happen if the
  #                               parent org has too many members (which may
  #                               cause the access checks to time out)
  #
  # remove_dependabot           - by default #participants will remove dependabot
  #                               alongside all bots from the list of participants. If remove_dependabot
  #                               is set to false, dependabot will not be removed
  # Returns an Array of Users.
  sig { params(viewer: T.untyped, optimize_repo_access_checks: T::Boolean, remove_dependabot: T::Boolean).returns(Array) }
  def participants(viewer: nil, optimize_repo_access_checks: false, remove_dependabot: true)
    # If the ID is nil, it means the PR hasn't been created yet (this can get called for instance
    # if the PR is on the 'compare' stage, and still being written.
    return [user] if self.id.nil?

    @participants ||= begin
      review_user_ids = PullRequestReviewComment.connection.select_values(Arel.sql(<<-SQL, pull_request_id: self.id, state: PullRequestReviewComment.states[:pending]))
        SELECT DISTINCT(user_id)
          FROM pull_request_review_comments
        WHERE pull_request_id = :pull_request_id
        AND state != :state
      SQL
      review_user_ids += reviews.submitted.distinct.pluck(:user_id)

      commit_commenter_user_ids = (corrupt? ? [] : historical_comparison.comments.unscope(:includes).distinct.pluck(:user_id))

      users = [
        user,
        commenters,
        User.where(id: review_user_ids + commit_commenter_user_ids),

        # This is delegated to Issue
        get_event_participants,
        changed_commits.map(&:author).select { |user| T.must(base_repository).pullable_by?(user) },
      ].flatten.compact.uniq
      user_ids_to_hide = T.must(repository).user_ids_to_hide_from_mentions(users, viewer: viewer, optimize_repo_access_checks: optimize_repo_access_checks)
      users.reject! do |user|
        if user.is_a?(Bot)
          remove_dependabot || !GitHub.dependabot_enabled? || !user.is_dependabot?
        else
          user_ids_to_hide.include?(user.id)
        end
      end
      GitHub::PrefillAssociations.prefill_associations(users, :profile)
      users
    end
  end

  sig { returns(Array) }
  def commenters
    async_commenters.sync
  end

  sig { returns(Promise[Array]) }
  def async_commenters
    async_issue.then do |issue|
      issue.async_commenters.then do |commenters|
        commenters
      end
    end
  end

  # Users who should be considered participants in the pull request.
  #
  # viewer - the User who is viewing the participants (current_user)
  # optimize_repo_access_checks - if optimize_repo_access_checks is set
  #                               to true, do not perform access checks
  #                               on repos that are owned by org's with
  #                               a lot of members
  #
  # remove_dependabot           - by default #participants_for will remove dependabot
  #                               alongside all bots from the list of participants. If remove_dependabot
  #                               is set to false, dependabot will not be removed
  #
  # Returns an Array of Users.
  sig { params(viewer: T.untyped, optimize_repo_access_checks: T::Boolean, remove_dependabot: T::Boolean).returns(Array) }
  def participants_for(viewer, optimize_repo_access_checks: false, remove_dependabot: true)
    participants(viewer: viewer, optimize_repo_access_checks: optimize_repo_access_checks, remove_dependabot: remove_dependabot).reject { |u| u.hide_from_user?(viewer) }
  end

  # Total number of issue + review comments on this pull request. Commit
  # comments are not included for performance reasons.
  sig { returns(Numeric) }
  def total_comments
    issue_comments_count + (review_comments_with_body_count || 0) + (reviews_with_body_count || 0)
  end

  # Public: All review comments for this pull request visible to the viewer
  #
  # Returns an array of PullRequestReviewComment sorted by created_at, ascending.
  def review_comments_for(viewer)
    review_comments.filter_spam_for(viewer)
                  .in_viewable_state_for(viewer)
                  .includes(:user)
                  .order(:pull_request_id, :created_at, :id)
  end

  # All review comments for this pull request grouped by "thread". A thread
  # consists of one or more comments on the same path and line number.
  #
  # viewer - the User who is viewing the review comments (current_user)
  #
  # Returns an array of PullRequestReviewThread sorted by comment creation date.
  # Older threads come first.
  sig { params(viewer: T.untyped).returns(T::Array[PullRequestReviewThread]) }
  def review_comment_threads_for(viewer)
    async_review_threads_for(viewer).sync
  end

  # All review comments for this pull request grouped by "thread". A thread
  # consists of one or more comments on the same path and line number.
  #
  # viewer - the User who is viewing the review comments (current_user)
  #
  # Returns an Promise<Array<PullRequestReviewThread>> sorted by comment creation date.
  # Older threads come first.
  sig { params(viewer: T.untyped).returns(Promise[T::Array[PullRequestReviewThread]]) }
  def async_review_threads_for(viewer)
    promise = async_review_threads.then do |review_threads|
      Promise.all(review_threads.map do |review_thread|
        review_thread.async_visible_to?(viewer).then do |visible|
          review_thread if visible
        end
      end).then do |visible_threads|
        visible_threads.compact
      end
    end

    T.unsafe(promise)
  end

  # All file-level review comments for this pull request grouped by "thread". A thread
  # consists of one or more comments on the same file.
  #
  # viewer - the User who is viewing the review comments (current_user)
  #
  # Returns an array of PullRequestReviewThread sorted by comment creation date.
  # Older threads come first.
  sig { params(viewer: T.untyped).returns(T::Array[PullRequestReviewThread]) }
  def file_review_comment_threads_for(viewer)
    async_file_review_threads_for(viewer).sync
  end

  # All file-level review comments for this pull request grouped by "thread". A thread
  # consists of one or more comments on the same file.
  #
  # viewer - the User who is viewing the review comments (current_user)
  #
  # Returns an Promise<Array<PullRequestReviewThread>> sorted by comment creation date.
  # Older threads come first.
  sig { params(viewer: T.untyped).returns(Promise[T::Array[PullRequestReviewThread]]) }
  def async_file_review_threads_for(viewer)
    promise = async_file_review_threads.then do |review_threads|
      Promise.all(review_threads.map do |review_thread|
        review_thread.async_visible_to?(viewer).then do |visible|
          if visible
            review_thread
          else
            nil
          end
        end
      end).then do |visible_threads|
        visible_threads.compact
      end
    end

    T.unsafe(promise)
  end

  # @raise [PullRequest::BaseNotChangeableError]
  # @raise [PullRequest::RefBeingRenamedError]
  # @raise [PullRequest::BaseRefNotFoundError]
  # @raise [PullRequest::InvalidBaseRefNameError]
  # @raise [PullRequest::ClosedError]
  # @raise [PullRequest::LockedForMergeQueueError]
  sig { params(user: T.untyped, new_base_ref: T.untyped, automatic: T::Boolean).void }
  def can_change_base_branch!(user, new_base_ref, automatic: false)
    raise BaseNotChangeableError.new(self, new_base_ref.try(:to_s) || "invalid") unless new_base_ref.is_a?(String)

    base_repository = T.must(self.base_repository)
    if base_repository.branch_being_renamed?(new_base_ref)
      raise PullRequest::RefBeingRenamedError.new(self, new_base_ref)
    end
    ref = base_repository.heads.read(new_base_ref)
    raise PullRequest::BaseRefNotFoundError.new(self, new_base_ref) unless ref.exist?
    raise PullRequest::InvalidBaseRefNameError.new(self, new_base_ref) unless ref.name == new_base_ref
    raise PullRequest::ClosedError.new(self, new_base_ref) unless open?
    if merge_queue_entry.present? && base_repository.merge_queue_enabled_for_branch?(base_ref)
      raise PullRequest::LockedForMergeQueueError.new(self, new_base_ref)
    end
  end

  # @raise [PullRequest::BaseNotChangeableError]
  # @raise [PullRequest::RefBeingRenamedError]
  # @raise [PullRequest::BaseRefNotFoundError]
  # @raise [PullRequest::InvalidBaseRefNameError]
  # @raise [PullRequest::ClosedError]
  # @raise [PullRequest::LockedForMergeQueueError]
  sig { params(user: T.untyped, new_base_ref: T.untyped, automatic: T::Boolean).void }
  def change_base_branch(user, new_base_ref, automatic: false)
    can_change_base_branch!(user, new_base_ref, automatic: automatic)

    ref = T.must(base_repository).heads.read(new_base_ref)
    synchronize!(user: user,
                  repo: T.must(base_repository),
                  ref: new_base_ref,
                  before: nil,
                  after: ref.target_oid,
                  changing_base: true,
                  automatic_base_retarget: automatic)
  rescue DetermineCodeownersError
    raise BaseNotChangeableError.new(self, new_base_ref)
  end

  # Public: Update the name of the base ref for the PullRequest.
  #         This should only be used when the old ref and new ref are
  #         identical, e.g., with a branch rename operation.
  #
  # new_name - The String name of the new ref.
  #
  # Note that no Git operations or synchronization is performed, and no
  # validation of the underlying refs is done.
  sig { params(new_name: String).void }
  def rename_base_branch(new_name)
    update!(base_ref: new_name)
  end

  # Public: Is the base branch for this pull request able to be changed?
  sig { returns(T::Boolean) }
  def can_change_base_branch?
    return false unless open?

    merge_queue_entry.blank? || !base_repository&.merge_queue_enabled_for_branch?(base_ref)
  end

  # A Repository::Codeowners object for the current changed paths.
  #
  # If there's an error determining the changed paths on this pull, the
  # Repository::Codeowners instance will effectively act as a NullObject.
  #
  # Returns a Repository::Codeowners object.
  sig { returns(T.nilable(Repository::Codeowners)) }
  def codeowners
    @codeowners ||= async_codeowners.sync
  end

  sig { returns(Promise[T.nilable(Repository::Codeowners)]) }
  def async_codeowners
    promise = async_base_repository.then do |base_repository|
      Promise.all([base_repository.async_organization, base_repository.async_network]).then do
        codeowners = Repository::Codeowners.new(base_repository, ref: base_ref_name)
        if codeowners.file
          async_changed_paths_for_codeowners.then do |changed_paths|
            codeowners.tap do |codeowners|
              codeowners.paths = changed_paths
            end
          end
        else
          codeowners
        end
      end
    end

    T.unsafe(promise)
  end

  # A Repository::Codeowners object for the current changed paths.
  #
  # @raise [DetermineCodeownersError]
  sig { returns(Repository::Codeowners) }
  def codeowners!
    codeowners.tap do
      raise DetermineCodeownersError.new(@codeowners_paths_load_error) if codeowners_paths_load_error?
    end
  end

  # Find the paths changed by this pull request which may be owned by code owners.
  #
  # Will return an empty Array if the diff can't be loaded.
  #
  # codeowners_paths_load_error? can be used to check whether or not
  # the diff was loaded.
  #
  # Returns an array of String paths.
  sig { returns(Array) }
  def changed_paths_for_codeowners
    async_changed_paths_for_codeowners.sync
  end

  # Asynchronously finds the paths changed by this pull request which may be owned by code owners.
  sig { returns(Promise[Array]) }
  def async_changed_paths_for_codeowners
    async_historical_comparison.then do |historical_comparison|
      historical_comparison.async_build_diff.then do |diff|
        diff.deltas.flat_map(&:paths).uniq
      end
    end.catch do |error|
      case error
      when GitRPC::ObjectMissing
        @codeowners_paths_load_error = error
        []
      else
        raise error
      end
    end
  end

  # Internal: Can we trust the Repository::Codeowners object for this pull?
  #
  # True if we were able to load the historical diff for codeowners, false
  # if that encountered an error.
  #
  sig { returns(T::Boolean) }
  def codeowners_paths_load_error?
    !!@codeowners_paths_load_error
  end

  # Internal: May be raised when there was an error determining the changed
  # paths for this pull request.
  class DetermineCodeownersError < StandardError
    attr_reader :cause

    # Public: Initialize a new PullRequest::DetermineCodeownersError.
    #
    # cause - The root error encountered when finding the changed paths
    #         for the pull request.
    #
    # Returns the error object.)
    sig { params(cause: T.untyped).void }
    def initialize(cause)
      @cause = cause
      super(cause&.message)
    end
  end

  sig { void }
  def reset_current_threads_diff!
    remove_instance_variable(:@current_threads_diff)
    remove_instance_variable(:@async_build_comparison) if defined?(@async_build_comparison)
    remove_instance_variable(:@async_build_comparison_result) if defined?(@async_build_comparison_result)
  end

  sig { returns(Promise[T.nilable(GitHub::Diff)]) }
  def async_current_threads_diff
    Promise.resolve(current_threads_diff)
  end

  sig { returns(T.nilable(GitHub::Diff)) }
  def current_threads_diff
    return @current_threads_diff if defined?(@current_threads_diff)

    review_thread_paths = line_review_threads.distinct.pluck(:path)
    @current_threads_diff = begin
      diff = historical_comparison.init_diffs.only_params
      diff.maximize_single_entry_limits!
      diff.add_paths(review_thread_paths)
      diff
    rescue GitRPC::ObjectMissing
      # This can happen when commits are manually removed from a repo, such
      # as when Support scrubs the pull request, deletes the refs, and runs gc.
      nil
    end
  end

  # Retrieve all open pull requests for the given repository and ref. Any pull
  # request whose head or base ref matches is returned.
  #
  sig { params(repository: T.untyped, ref: T.untyped).returns(T::Array[PullRequest]) }
  def self.find_open_based_on_ref(repository, ref)
    open_based_on_ref(repository, ref).to_a
  end

  # Retrieve all open pull request ids for the given repository and ref. Any
  # pull request whose head or base ref matches is returned.
  #
  # Returns an array of integer ids.
  sig { params(repository: T.untyped, ref: T.untyped).returns(T::Array[Integer]) }
  def self.find_open_ids_based_on_ref(repository, ref)
    self.find_open_with_refs_based_on_ref(repository, ref).map(&:pull_request_id)
  end

  class FindOpenPrsResult < T::Struct
    const :pull_request_id, Integer
    const :base_ref, String
    const :head_ref, String
    const :base_repo_id, Integer
    const :head_repo_id, T.nilable(Integer)

    # These can be updated by the caller
    prop :base_oid, T.nilable(String)
    prop :head_oid, T.nilable(String)
  end

  # Retrieve all open pull request IDs and associated SHAs/refs for the given
  # repository and ref. Any pull request whose head or base ref matches is returned.
  sig { params(repository: Repository, ref: String).returns(T::Array[FindOpenPrsResult]) }
  def self.find_open_with_refs_based_on_ref(repository, ref)
    ref = Git::Ref.safe_ref_name(ref_names: ref)
    refs = ref.map { |ref| GitHub::SQL::ArelLiterals.binary(ref) }

    # If the repository is not part of an advisory workspace we can assume that
    # pr.base_repository_id = pr.repository_id and since we join on issues.repository_id = pr.repository_id
    # then we can filter the issues by repository_id as well, potentially using much more efficient indexes
    # in the issues table. See https://github.com/github/github/pull/110041
    #
    # Ordering pull ids from newest to oldest speeds up marking PRs as merged
    # in large repos, see https://github.com/github/github/issues/99241 and
    # https://github.com/github/github/pull/99449.
    issues_filter = "AND issues.repository_id = :repository_id" unless repository.advisory_workspace? || importing?

    Scientist.run "pulls-find-open-with-refs-ar" do |e|
      e.use do
        first_results = self.connection.select_all(Arel.sql(<<-SQL, repository_id: repository.id, refs: refs)).to_a
          SELECT pr.id, pr.base_sha, pr.head_sha, pr.base_ref, pr.head_ref, pr.base_repository_id, pr.head_repository_id
          FROM pull_requests pr
          JOIN issues ON pr.id = issues.pull_request_id AND issues.repository_id = pr.repository_id
          WHERE pr.base_repository_id = :repository_id AND pr.base_ref IN (:refs)
          AND issues.state = 'open'
          #{issues_filter}
          ORDER BY id DESC
        SQL

        second_results = self.connection.select_all(Arel.sql(<<-SQL, repository_id: repository.id, refs: refs)).to_a
            SELECT pr.id, pr.base_sha, pr.head_sha, pr.base_ref, pr.head_ref, pr.base_repository_id, pr.head_repository_id
            FROM pull_requests pr
            JOIN issues ON pr.id = issues.pull_request_id AND issues.repository_id = pr.repository_id
            WHERE pr.head_repository_id = :repository_id AND pr.head_ref IN (:refs)
            AND issues.state = 'open'
            ORDER BY id DESC
        SQL

        first_results.union(second_results)
          .sort_by { |pr_row| pr_row["id"] }
          .reverse
          .map do |pr_row|
            FindOpenPrsResult.new(pull_request_id: pr_row["id"],
              base_ref: pr_row["base_ref"], head_ref: pr_row["head_ref"],
              base_oid: pr_row["base_sha"], head_oid: pr_row["head_sha"],
              base_repo_id: pr_row["base_repository_id"], head_repo_id: pr_row["head_repository_id"])
          end
      end
      e.try do
        base_results = self.connection.select_all(Arel.sql(<<-SQL, repository_id: repository.id, refs: refs)).to_a
          SELECT pr.id, pr.base_sha, pr.head_sha, pr.base_ref, pr.head_ref, pr.base_repository_id, pr.head_repository_id
          FROM pull_requests pr
          JOIN issues ON pr.id = issues.pull_request_id AND issues.repository_id = pr.repository_id
          WHERE pr.base_repository_id = :repository_id AND pr.base_ref IN (:refs)
          AND issues.state = 'open'
          #{issues_filter}
        SQL

        head_results = self.connection.select_all(Arel.sql(<<-SQL, repository_id: repository.id, refs: refs)).to_a
          SELECT pr.id, pr.base_sha, pr.head_sha, pr.base_ref, pr.head_ref, pr.base_repository_id, pr.head_repository_id
          FROM pull_requests pr
          JOIN issues ON pr.id = issues.pull_request_id AND issues.repository_id = pr.repository_id
          WHERE pr.head_repository_id = :repository_id AND pr.head_ref IN (:refs)
          AND issues.state = 'open'
        SQL

        base_results.union(head_results)
          .sort_by { |pr_row| pr_row["id"] }
          .reverse
          .map do |pr_row|
            FindOpenPrsResult.new(pull_request_id: pr_row["id"],
              base_ref: pr_row["base_ref"], head_ref: pr_row["head_ref"],
              base_oid: pr_row["base_sha"], head_oid: pr_row["head_sha"],
              base_repo_id: pr_row["base_repository_id"], head_repo_id: pr_row["head_repository_id"])
          end
      end
      e.compare do |a, b|
        if a.nil? || b.nil?
          a == b
        else
          a.map(&:pull_request_id) == b.map(&:pull_request_id)
        end
      end
    end
  end

  # Retrieve all open pull requests for the given head repository id and head ref
  #
  # Returns an array of PullRequest objects.
  def self.find_open_based_on_head_ref(repository_id, ref)
    if (ids = find_open_ids_based_on_head_ref(repository_id, ref)).any?
      includes(:issue).find(ids)
    else
      []
    end
  end

  # Retrieve all open pull request ids for the given head repository id and head ref.
  sig { params(repository_id: T.untyped, ref: T.untyped).returns(T::Array[Numeric]) }
  def self.find_open_ids_based_on_head_ref(repository_id, ref)
    repository = Repository.find_by(id: repository_id)
    refs = Git::Ref.safe_ref_name(ref_names: ref).map { |ref| GitHub::SQL::ArelLiterals.binary(ref) }
    return [] if refs.empty?
    self.connection.select_values(Arel.sql(<<-SQL, repository_id: repository_id, refs: refs))
      SELECT pr.id
      FROM pull_requests pr
      JOIN issues ON pr.id = issues.pull_request_id AND issues.repository_id = pr.repository_id
      WHERE (
        ( pr.head_repository_id = :repository_id AND pr.head_ref IN (:refs) )
      ) AND issues.state = 'open'
    SQL
  end

  # Called when a branch is deleted. Closes any open pull requests that have the
  # branch as either the base or head.
  sig { params(repository: Repository, ref: T.untyped, pusher: T.untyped, before_sha: T.untyped).void }
  def self.after_branch_delete(repository, ref, pusher, before_sha)
    safe_ref = Git::Ref.safe_ref_name(ref_names: ref)
    find_open_based_on_ref(repository, ref).each do |pull|
      if safe_ref.include?(pull.base_ref)
        pull.create_issue_event(:base_ref_deleted, pusher)
      end

      pull.close(pusher)
    end

    mark_head_ref_as(:deleted, repository, ref, before_sha, pusher)
  end

  # Updates any PR records that match the given repository, ref,
  # and head_sha, to indicate that the head branch was either deleted
  # or restored.
  #
  # action     - :deleted or :restored
  # repository - The Repository that the ref was deleted or restored in
  # ref        - The ref name that was deleted or restored
  # sha        - The SHA of the ref at the time of deletion or restoration
  # user       - The User who deleted or restored the head_ref
  sig { params(action: T.untyped, repository: Repository, ref: T.untyped, sha: T.untyped, user: T.untyped).void }
  def self.mark_head_ref_as(action, repository, ref, sha, user)
    where(
      head_repository_id: repository.id,
      head_ref: Git::Ref.safe_ref_name(ref_names: ref),
      head_sha: sha,
    ).each do |pull|
      pull.create_head_ref_event(action, user)
    end
  end

  # Creates a head_ref_deleted or head_ref_restored
  # event in a way that protects against duplicate
  # events that could arise from a race condition.
  #
  # head_ref_deleted and head_ref_restored should only
  # ever alternate, e.g. it should not be possible
  # to have two head_ref_deleted events in a row.
  #
  # It should also not be possible to have a head_ref_restored
  # event without having a head_ref_deleted event.
  #
  # This method keeps that from happening.
  #
  # action - :deleted or :restored
  # user   - The User that deleted or restored the branch
  #
  # Returns the new IssueEvent, or nil if one was not
  #         created due to the existence of a duplicate
  sig { params(action: T.untyped, user: T.untyped).returns(T.nilable(IssueEvent)) }
  def create_head_ref_event(action, user)
    event = {
      deleted: :head_ref_deleted,
      restored: :head_ref_restored,
    }[action]

    raise "Unknown action" if event.nil?

    transaction do
      reload(lock: true)

      last_head_ref_event = events.head_ref.last

      valid_event = if last_head_ref_event.nil?
        # It must have been deleted to be restored
        event != :head_ref_restored
      else
        # It cannot be deleted or restored twice in a row
        last_head_ref_event.event != event.to_s
      end

      if valid_event
        head_ref_event = create_issue_event(event, user)
        touch
        head_ref_event
      end
    end
  end

  sig { params(repository: Repository).void }
  def self.handle_deleted_repo(repository)
    sync_outstanding_commits(repository)
    close_open_cross_repo_prs(repository)
  end

  # Before a Repository is deleted, make sure to sync any commits involved in cross-repo pulls
  # to the base repo. This could be necessary if the head repo is deleted immediately after
  # opening a PR, causing it to race with the MaintainTrackingRef job, or if a MaintainTrackingRef
  # job failed for some reason previously.
  sig { params(repository: Repository).void }
  def self.sync_outstanding_commits(repository)
    where("head_repository_id = ? AND head_repository_id <> base_repository_id", repository.id).each do |pull|
      begin
        pull.maintain_tracking_ref_with_retries(pull.safe_user)
      rescue => boom # rubocop:todo Lint/GenericRescue
        Failbot.report(boom, "gh.pull_request.id": pull.id)
      end
    end
  end

  # When a repo is deleted we need to close any PRs that have it as a head_repository.
  sig { params(repository: T.nilable(Repository)).void }
  def self.close_open_cross_repo_prs(repository)
    return unless repository
    PullRequest.open_pulls.where(head_repository: repository).where.not(base_repository: repository).find_each do |pull|
      next if pull.base_repository.nil?
      # Bypass permission-checking lifecycle method since we don't necessarily
      # have a user with permissions to do this but the PR needs to be closed
      # anyway since the UI can't support an open PR with a deleted repo.
      if T.must(pull.issue).update(state: "closed")
        pull.create_issue_event(:closed, pull.safe_head_user, message: :head_repository_deleted)
      end
    end
  end

  sig { returns(Promise[T.untyped]) }
  def async_performed_via_integration
    async_issue.then(&:async_performed_via_integration)
  end

  sig { returns(T.nilable(T::Boolean)) }
  def locked?
    T.must(issue).locked?
  end

  sig { returns(T.nilable(ActiveSupport::TimeWithZone)) }
  def locked_at
    T.must(issue).locked_at
  end

  sig { params(user: T.untyped).returns(T.nilable(T::Boolean)) }
  def locked_for?(user)
    T.must(issue).locked_for?(user)
  end

  sig { returns(String) }
  def locked_reason
    T.must(issue).locked_reason
  end

  sig { returns(T.nilable(String)) }
  def active_lock_reason
    T.must(issue).active_lock_reason
  end

  sig { returns(Promise[T.untyped]) }
  def async_in_advisory_workspace?
    async_repository.then do |repository|
      repository&.async_advisory_workspace?
    end
  end

  sig { returns(T.nilable(T::Boolean)) }
  def in_advisory_workspace?
    async_in_advisory_workspace?.sync
  end

  sig { returns(T.nilable(RepositoryBranchRename)) }
  def errored_base_branch_rename
    return @errored_base_branch_rename if defined?(@errored_base_branch_rename)

    @errored_base_branch_rename = T.must(repository).branch_renames.
      where(old_name: base_ref).
      errored.
      since(created_at).
      latest.
      first
  end

  #
  # Validations
  #

  sig { void }
  def repository_and_base_repository_must_match
    return unless repository = self.repository
    return if base_repository_id == repository_id

    errors.add(:base_ref, "#{base.inspect} should be in the root repo #{repository.name_with_display_owner}")
  end

  sig { void }
  def head_repository_must_be_advisory_workspace
    return unless repository = self.repository
    return unless in_advisory_workspace?

    return if head_repository_id == repository_id
    errors.add(:head_ref, "#{base.inspect} should be in the advisory workspace repo #{repository.name_with_display_owner}")
  end

  sig { void }
  def base_repository_must_be_advisory_workspace_origin_repository
    return unless repository = self.repository
    return unless in_advisory_workspace?

    return if base_repository_id == repository.parent_advisory_repository&.id
    errors.add(:base_ref, "#{base.inspect} should target the advisory workspace repo #{repository.name_with_display_owner}")
  end

  # Validate that commits exist between the base and head.
  sig { void }
  def must_have_commits
    return if Rails.env.test? && disable_disk_access?

    if !commits_pending?
      errors.add(:base, "No commits between #{base_label} and #{head_label}")
    end
  end

  sig { void }
  def must_have_common_ancestor
    return if Rails.env.test? && disable_disk_access?
    return if repository.nil? || base_user.nil?
    return if !historical_comparison.valid?

    if !common_ancestor?
      errors.add(:base, "The #{head_label} branch has no history in common with #{base_label}")
    end
  end

  # Validate that base_ref is a real branch
  sig { void }
  def base_ref_is_real_branch
    return if Rails.env.test? && disable_disk_access?

    errors.add(:base_ref, "must be a branch") unless base_ref_exist? || base_ref_exist?(refresh_refs: true)
  end

  # Validate that the base_ref is not a branch in the middle of the branch rename process
  sig { void }
  def base_ref_is_not_being_renamed
    return unless base_repository = self.base_repository

    if base_repository.branch_being_renamed?(base_ref)
      errors.add(:base_ref, "is being renamed")
    end
  end

  # Validate that head_ref is a real branch
  sig { void }
  def head_ref_is_real_branch
    return if Rails.env.test? && disable_disk_access?

    errors.add(:head_ref, "must be a branch") unless head_ref_exist? || head_ref_exist?(refresh_refs: true)
  end

  # Validate that head_ref isn't a heads-namespaced branch
  sig { void }
  def head_ref_is_not_namespaced
    return if Rails.env.test? && disable_disk_access?

    if head_ref&.starts_with?("heads/")
      errors.add(:head, "must not include 'heads/' namespace") unless head_ref_exist?
    end
  end

  sig { void }
  def head_ref_does_not_contain_refs_heads
    return if Rails.env.test? && disable_disk_access?
    return unless GitHub.flipper[:disallow_refs_heads_via_validation].enabled?(repository)

    if head_ref&.starts_with?("refs/heads/")
      errors.add(:head_ref, "must not include 'refs/heads/'")

      GitHub.logger.info("Pull Request attempted to be saved with 'refs/heads/'",
        "gh.pull_request.id": id,
        "gh.pull_request.head_or_base_ref": "head_ref"
      )
    end
  end

  sig { void }
  def base_ref_does_not_contain_refs_heads
    return if Rails.env.test? && disable_disk_access?
    return unless GitHub.flipper[:disallow_refs_heads_via_validation].enabled?(repository)

    if base_ref&.starts_with?("refs/heads/")
      errors.add(:base_ref, "must not include 'refs/heads/'")

      GitHub.logger.info("Pull Request attempted to be saved with 'refs/heads/'",
        "gh.pull_request.id": id,
        "gh.pull_request.head_or_base_ref": "base_ref"
      )
    end
  end

  sig { void }
  def clean_refs_heads
    return if Rails.env.test? && disable_disk_access?
    return unless GitHub.flipper[:clean_refs_heads_before_validation].enabled?(repository)

    if head_ref&.starts_with?("refs/heads/")
      self.head_ref = head_ref.sub("refs/heads/", "")

      GitHub.logger.info("Pull Request with 'refs/heads/' was cleaned",
        "gh.pull_request.id": id,
        "gh.pull_request.head_or_base_ref": "head_ref"
      )
    end

    if base_ref&.starts_with?("refs/heads/")
      self.base_ref = base_ref.sub("refs/heads/", "")

      GitHub.logger.info("Pull Request with 'refs/heads/' was cleaned",
        "gh.pull_request.id": id,
        "gh.pull_request.head_or_base_ref": "base_ref"
      )
    end
  end

  sig { void }
  def head_ref_is_not_from_merge_queue
    return if Rails.env.test? && disable_disk_access?
    return unless head_ref

    if head_ref.starts_with?(MergeQueue::READ_ONLY_BRANCH_SHORT_PREFIX)
      errors.add(:head, "must not be a merge queue branch")
    end
  end

  # Boolean flag used to disable the must_have_commits, ref creation, cached
  # diffstat, and network repository sync on create behavior. Used in tests when
  # only the record data need be present. All commit, comparison, diff or other
  # file access features will fail when this is set true.
  sig { returns(T.nilable(T::Boolean)) }
  attr_accessor :disable_disk_access
  alias disable_disk_access? disable_disk_access

  # Validate that a new pull request isn't a duplicate.
  sig { void }
  def duplicate_check
    if repository.present? && find_existing
      errors.add(:base, "A pull request already exists for #{head}.")
    end
  end

  #
  # Misc Internal Logic
  #

  # The sha currently associated with base_ref. As opposed to #base_sha,
  # which is cached when the pull request is created, or #concrete_base_sha,
  # which is the most ideal base for comparison.
  #
  # Returns a sha, or nil if the base branch has been deleted.
  sig { returns(T.nilable(String)) }
  def current_base_sha
    comparison.base_sha
  end
  alias current_base_oid current_base_sha

  sig { returns(T.nilable(String)) }
  def current_head_oid
    comparison.head_sha
  end

  # Use the stored base commit SHA1 to find the most recent valid base commit on
  # the base branch. This uses a custom git-branch-base program to find the best
  # base commit SHA1 for the comparison. See the lib/git-core/bin/git-branch-base
  # file for more information on how it works.
  sig { returns(T.nilable(String)) }
  def concrete_base_sha
    if base_sha
      calculate_branch_base
    else
      current_base_sha
    end
  end

  # Run git-branch-base.
  sig { returns(String) }
  def calculate_branch_base
    comparison.compare_repository.rpc.branch_base(comparison.head_sha, comparison.base_sha, base_sha)
  end

  alias mergeable_base_sha current_base_sha

  sig { returns(T.nilable(String)) }
  def mergeable_head_sha
    head_sha
  end

  sig { void }
  def set_contributed_at
    T.unsafe(self).contributed_at ||= Time.zone.now
  end

  # after_create callback to ensure the pull request author is subscribed
  sig { void }
  def subscribe_author
    return if user.nil? || issue.try(:user_id) == user_id
    T.must(issue).subscribe user, :author
  end

  sig { returns(T.any(Time, ActiveSupport::TimeWithZone)) }
  def contribution_time
    @contribution_time ||= if contributed_at_timezone_aware?
      T.unsafe(self).contributed_at
    else
      T.must(created_at).localtime
    end
  end

  sig { returns(Date) }
  def contributed_on
    contribution_time.to_date
  end

  sig { returns(T::Boolean) }
  def is_searchable?
    # Data quality issue where the issue is nil
    return false if issue.nil?

    # If the repository is not searchable, its PRs shouldn't be either
    return false unless repository = self.repository

    return false unless repo_is_searchable?

    # Do not index spam content
    return false if user_hidden?
    # The read_attribute here is used for speed to bypass the potentially slow #spammy? method.
    return false if safe_user.read_attribute(:spammy)

    # If we got this far, then add to the search index
    true
  end

  sig { returns(T::Boolean) }
  def repo_is_searchable?
    # If the repository is missing, then we have a rogue pull request
    return false unless repository = self.repository
    # Repo must be active to find pull requests
    return false unless repository.active?
    # When the repo user is spammy
    return false if T.unsafe(repository).spammy?
    # When the parent repo has been disabled for any reason
    return false if repository.disabled?
    # When the parent repo has been disabled for DMCA and similar reasons
    return false if repository.access.disabled?

    # Repo is safe to index
    true
  end

  # Synchronize this pull request with its representation in the search
  # index. If the pull request is newly created or modified in some fashion,
  # then it will be updated in the search index. If the pull request has been
  # destroyed, then it will be removed from the search index. This method
  # handles both cases.
  sig { returns(PullRequest) }
  def synchronize_search_index
    if self.destroyed? || !self.is_searchable?
      RemoveFromSearchIndexJob.perform_later("pull_request", self.id, self.repository_id)
    else
      Search.add_to_search_index("pull_request", self.id)
    end
    self
  end

  class OutOfSyncPullRequestIndex < Error; end

  # Called when a pull request gets out of sync with the search index via some
  # error or timeout. This method is called in exceptional situations, so we log
  # to Datadog and Failbot.
  sig { void }
  def resynchronize_search_index
    GitHub.dogstats.increment("pull_request.reindexed")

    boom = OutOfSyncPullRequestIndex.new("Pull request search index is out of sync and is being reindexed")
    boom.set_backtrace(caller)
    Failbot.report(
      boom,
      "gh.repo.id": T.must(repository).id,
      "gh.pull_request.id": id,
      "gh.issue.id": T.must(issue).id,
      app: "github-pull-requests",
    )

    synchronize_search_index
  end

  include Instrumentation::Model

  sig { returns(Symbol) }
  def event_prefix = :pull_request

  sig { returns(Hash) }
  def event_payload
    payload = event_context.dup

    payload[:primary_resource] = self.attributes
    payload[:user] = user if user

    if repository = self.repository
      payload[:repo] = repository if repository

      if business = repository.business
        payload[:business] = business
      end

      if organization = repository.organization
        payload[:org] = organization

        if business = organization.business
          payload[:business_id] = business.id
        end
      end
    end

    payload
  end

  sig { params(prefix: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
  def event_context(prefix: event_prefix)
    {
      "#{prefix}_id".to_sym => id,
      "#{prefix}_url".to_sym => permalink,
      "#{prefix}_title".to_sym => title,
    }
  end

  sig { void }
  def reset_memoized_attributes
    @merge_ref             = nil
    @rebase_ref            = nil
    @comparison            = nil
    @merge_comparison      = nil
    remove_instance_variable(:@async_build_comparison) if defined?(@async_build_comparison)
    remove_instance_variable(:@async_build_comparison_result) if defined?(@async_build_comparison_result)
    remove_instance_variable(:@compare_repository) if defined?(@compare_repository)
    remove_instance_variable(:@async_changed_commits) if defined?(@async_changed_commits)
    @participants          = nil
    @total_comments        = nil
    @branch                = nil
    @closable_issues = nil
    @filter_result         = nil
    @filter_content        = nil
    @pushable_repo_by_user = nil
    @merge_states          = nil
    @blocked_from_reviewing = nil
    remove_instance_variable(:@current_threads_diff) if defined?(@current_threads_diff)
    remove_instance_variable(:@rebase_state) if defined?(@rebase_state)
    remove_instance_variable(:@status) if defined?(@status)
    remove_instance_variable(:@corrupt) if defined?(@corrupt)
    reset_latest_enforced_reviews_cache
    remove_instance_variable(:@latest_reviews_not_requested) if defined?(@latest_reviews_not_requested)
    remove_instance_variable(:@pending_review_requests_by_reviewer) if defined?(@pending_review_requests_by_reviewer)
    remove_instance_variable(:@required_reviewer_summary) if defined?(@required_reviewer_summary)
  end

  sig { void }
  def reset_latest_enforced_reviews_cache
    remove_instance_variable(:@latest_enforced_reviews) if defined?(@latest_enforced_reviews)
  end

  sig { returns(MergeStatus) }
  def combined_status
    return @combined_status if defined?(@combined_status)
    @combined_status = build_combined_status_for_sha(head_sha)
  end

  # @raise [TypeError] when something other than nil or PullRequest::MergeStatus is given
  sig { params(status: T.untyped).void }
  def combined_status=(status)
    if status && !status.is_a?(PullRequest::MergeStatus)
      raise TypeError, "PullRequest#combined_status must be of type PullRequest::MergeStatus, but was #{status.class}"
    end
    @combined_status = status
  end

  sig { params(sha: T.untyped).returns(MergeStatus) }
  def build_combined_status_for_sha(sha)
    PullRequest::MergeStatus.new(base_repository, sha, target_branch: base_ref_name)
  end

  sig { returns(String) }
  def pr_title_with_number
    "#{title} (##{number})"
  end

  sig { returns(String) }
  def pr_title_with_ref_name
    "Merge pull request ##{number} from #{owner_display_login(safe_head_user)}/#{display_head_ref_name}"
  end

  sig do
    params(
      method: Symbol,
      message_title: T.nilable(String),
      message: T.nilable(String),
    ).returns([T.nilable(String), T.nilable(String), T::Boolean])
  end
  def determine_merging_message(method, message_title, message)
    case method
    when :rebase
      return [message_title, message, true]
    when :merge
      message_title ||= default_merge_commit_title
      message ||= default_merge_commit_message
    when :squash
      message_title ||= default_squash_commit_title
      message ||= default_squash_commit_message
    end

    [message_title, message, uses_defaults?(method, message_title, message)]
  end

  sig do
    params(
      method: Symbol,
      message_title: T.nilable(String),
      message: T.nilable(String),
    ).returns(T::Boolean)
  end
  def uses_defaults?(method, message_title, message)
    uses_default_commit_title?(method, message_title) && uses_default_commit_message?(method, message)
  end

  sig do
    params(
      method: Symbol,
      message_title: T.nilable(String),
    ).returns(T::Boolean)
  end
  def uses_default_commit_title?(method, message_title)
    if method == :merge
      default_merge_commit_title == message_title
    elsif method == :squash
      default_squash_commit_title == message_title
    else
      false
    end
  end

  sig do
    params(
      method: Symbol,
      message: T.nilable(String),
    ).returns(T::Boolean)
  end
  def uses_default_commit_message?(method, message)
    if method == :merge
      default_merge_commit_message == message
    elsif method == :squash
      default_squash_commit_message(author: user).delete(" \t\r\n") == message&.delete(" \t\r\n")
    else
      false
    end
  end

  sig { returns(T.nilable(String)) }
  def default_merge_commit_title
    repository = T.must(self.repository)

    if repository.merge_commit_title_pr_title_enabled?
      pr_title_with_number
    elsif repository.merge_commit_title_merge_message_enabled?
      pr_title_with_ref_name
    else
      pr_title_with_ref_name
    end
  end

  sig { returns(T.nilable(String)) }
  def default_merge_commit_message
    repository = T.must(self.repository)

    if repository.merge_commit_message_pr_title_enabled?
      title
    elsif repository.merge_commit_message_pr_body_enabled?
      body ? CommitMessageWrapper.new(exclude_text_from_message(body)).wrap : ""
    elsif repository.merge_commit_message_blank_enabled?
      ""
    else
      title
    end
  end

  sig { returns([T::Boolean, T.nilable(Commit)]) }
  def merging_one_commit?
    first_real_commit = T.let(nil, T.nilable(Commit))
    has_multiple_commits = T.let(false, T::Boolean)
    count = 0
    changed_commits.each do |commit|
      next if commit.merge_commit?
      count += 1
      if count > 1
        has_multiple_commits = true
        break
      end
      first_real_commit = commit
    end

    [!has_multiple_commits && first_real_commit.present?, first_real_commit]
  end

  sig { params(first_real_commit: Commit).returns(T::Array[String]) }
  def first_real_commit_lines(first_real_commit)
    first_real_commit.message_without_authored_by_or_signed_off_trailers.lines
  end

  sig { params(author: T.untyped).returns(String) }
  def default_squash_commit_message(author: user)
    return @squash_commit_message if @squash_commit_message
    return "" if corrupt?

    repository = T.must(self.repository)
    message = +""
    merging_one_commit, first_real_commit = merging_one_commit?

    unless repository.squash_commit_message_blank_enabled?
      if repository.squash_commit_message_pr_body_enabled?
        # then we're using the PR body as the default message; the other rules don't apply
        message << CommitMessageWrapper.new(exclude_text_from_message(body)).wrap if body
      elsif merging_one_commit
        if repository.squash_pr_title_enabled? || repository.squash_merge_commit_title_pr_title_enabled?
          # If there's only one commit, the squash commit "message" is populated
          # with that commit's message. If the first line is the same as the PR title,
          # dedupe them because #default_squash_commit_title will have the same result
          lines = first_real_commit_lines(T.unsafe(first_real_commit))
          lines = lines[1..-1] if lines.first && T.must(lines.first).strip == title
        elsif repository.squash_commit_message_commit_messages_enabled?
          # If there's only one commit, the squash commit "message" is populated
          # with that commit's messages _except_ for the first line. That's because
          # the first line of the commit message is returned by the
          # default_squash_commit_title method instead.
          lines = first_real_commit_lines(T.unsafe(first_real_commit))
          lines = lines[1..-1]
        end
        message << lines.join if lines
      else
        # If there are multiple commits, we include the commit message for each
        # one in a bulleted list.
        changed_commits.each do |commit|
          # Exclude messages for merge commits and blank commit "titles."
          next if commit.merge_commit? || commit.message.lines.first.nil?
          message << "* #{commit.message.strip}\n\n"
        end
      end
    end

    message.strip!

    sign_off_git_actors = squash_commit_sign_off_actors
    co_author_git_actors = squash_commit_co_author_actors(author: author)

    # Separate the trailers from the current message (if needed).
    if message.present? && (sign_off_git_actors.any? || co_author_git_actors.any?)
      message << "\n\n---------" if !merging_one_commit
      message << "\n\n"
    end

    sign_off_git_actors.each do |signer|
      message << "Signed-off-by: #{signer}\n"
    end

    co_author_git_actors.each do |author|
      message << "Co-authored-by: #{author.display_name} <#{author.display_email}>\n"
    end

    message.rstrip!

    @squash_commit_message = message
  end

  sig { params(body: T.untyped).returns(String) }
  def exclude_text_from_message(body)
    if GitHub.flipper[:omit_pr_body_commits].enabled?(repository)
      # We want to exclude text from the PR body that is between the starting and ending tags.
      # If there is no ending tag, then we want to exclude everything after the starting tag.
      # We support multiple starting + ending tags in the PR body.

      starting_tag = Configurable::MergeCommitMessage::PR_BODY_OMISSION_STARTING_TAG
      ending_tag = Configurable::MergeCommitMessage::PR_BODY_OMISSION_ENDING_TAG

      body.gsub(/#{starting_tag}.*?#{ending_tag}/m, "").gsub(/#{starting_tag}.*/m, "").strip
    elsif body.include?("<!-- Exclude from commit message -->")
      body.split("<!-- Exclude from commit message -->").first
    else
      body
    end
  end

  sig { returns(String) }
  def squash_commit_title_by_commit_quantity
    merging_one_commit, first_real_commit = merging_one_commit?

    squash_commit_title =
      if !merging_one_commit || !T.unsafe(first_real_commit).message.lines.first
        title
      else
        T.unsafe(first_real_commit).message.lines.first.rstrip
      end

    squash_commit_title += " (##{number})"
  end

  sig { returns(T.nilable(String)) }
  def default_squash_commit_title
    return @squash_commit_title if @squash_commit_title

    repository = T.must(self.repository)

    if repository.squash_pr_title_enabled? || repository.squash_merge_commit_title_pr_title_enabled?
      @squash_commit_title = pr_title_with_number
    elsif repository.squash_merge_commit_title_commit_pr_title_enabled?
      @squash_commit_title = squash_commit_title_by_commit_quantity
    else
      @squash_commit_title = squash_commit_title_by_commit_quantity
    end
  end

  sig { returns(T::Boolean) }
  def fork_collab_granted?
    open? && fork_collab_allowed?
  end

  sig { params(head_commit_id: T.untyped).returns(T.nilable(String)) }
  def compute_base_commit_id(head_commit_id)
    comparison = build_comparison(head_commit_oid: head_commit_id)
    return unless comparison.valid?
    comparison.merge_base
  end

  sig { returns(T.nilable(T::Array[String])) }
  def conflicted_files
    return nil unless conflict = self.conflict
    return nil if currently_mergeable?.nil?
    conflict.filenames
  end

  def conflicted_file_contents(filename, ancestor_oid, base_oid, head_oid)
    repository = T.must(self.repository)

    ancestor_blob, base_blob, head_blob =
      if ancestor_oid.nil?
        # handle the case where the file was added in both revisions, no ancestor
        bb, hb = repository.rpc.read_blobs([base_oid, head_oid])
        [{}, bb, hb]
      else
        repository.rpc.read_blobs([ancestor_oid, base_oid, head_oid])
      end

    conflicted_file = repository.rpc.merge_single_file(
      ancestor_oid ? { oid: ancestor_oid, path: filename, filemode: 0100644 } : nil,
      { oid: base_oid,     path: filename, filemode: 0100644 },
      { oid: head_oid,     path: filename, filemode: 0100644 },
      our_label: head_ref, their_label: base_ref,
    )[:data]

    base_blob["path"] = head_blob["path"] = ancestor_blob["path"] = filename

    head_entry = TreeEntry.new(repository, head_blob)
    base_entry = TreeEntry.new(repository, base_blob)
    ancestor_entry = TreeEntry.new(repository, ancestor_blob)

    conflicted_file_contents_entry = TreeEntry.new(repository, {
      "data" => conflicted_file,
      "oid" => "",
      "type" => "blob",
      "binary" => head_blob["binary"] || ancestor_blob["binary"] || base_blob["binary"],
      "encoding" => head_blob["encoding"] || ancestor_blob["encoding"] || base_blob["encoding"],
    })

    [conflicted_file_contents_entry, ancestor_entry, base_entry, head_entry]
  end

  sig { returns(T::Boolean) }
  def conflict_resolvable?
    # in some cases, the conflict is too weird for our ui to resolve right now
    # like if a file was deleted in one side of the merge, or if there are any
    # submodules.
    return false unless conflict = self.conflict
    !!(conflict.resolvable? && conflict.head_sha == mergeable_head_sha && conflict.base_sha == mergeable_base_sha)
  end

  sig { void }
  def store_rebase_conflicts
    GitHub.dogstats.increment("pull_request.rebase_conflict")

    ActiveRecord::Base.connected_to(role: :writing) do
      store_conflicts({ base: base_sha, head: head_sha, conflicted_files: {} }, conflict_type: :rebase_conflict)
    end
  end

  sig { void }
  def clear_rebase_conflicts
    ActiveRecord::Base.connected_to(role: :writing) do
      rebase_conflict&.destroy
    end
  end

  sig { returns(T::Boolean) }
  def rebase_conflicts?
    current_rebase_conflict = rebase_conflict
    return true if current_rebase_conflict.present? && !current_rebase_conflict.destroyed?

    # Temporary fallback. Can be removed after the GHES 3.14.0 release
    # See: https://github.com/github/pull-requests/issues/7910#issuecomment-2164867198
    (GitHub.kv.get("#{id}_rebase_conflict").value { nil } == "true") # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  sig { params(conflicts_hash: T.untyped, conflict_type: Symbol).void }
  def store_conflicts(conflicts_hash, conflict_type: :merge_conflict)
    base = conflicts_hash.delete(:base)
    head = conflicts_hash.delete(:head)

    # we don't want non-utf8 filenames to be truncated, so we just encode them going into the database
    conflicted_files = {}
    conflicts_hash[:conflicted_files].each_key { |k| conflicted_files[CGI.escape(k)] = conflicts_hash[:conflicted_files][k] }
    conflicts_hash[:conflicted_files] = conflicted_files

    retry_on_find_or_create_error do
      conflict_to_modify =
        if conflict_type == :merge_conflict
          reload_conflict || build_conflict(conflict_type:)
        elsif conflict_type == :rebase_conflict
          reload_rebase_conflict || build_rebase_conflict(conflict_type:)
        else
          reload_merge_queue_conflict || build_merge_queue_conflict(conflict_type:)
        end

      conflict_to_modify.update!(
        base_sha: base,
        head_sha: head,
        info: conflicts_hash.to_json,
      )
    end
  end

  # This allows a PullRequest to implement the Reactable GraphQL interface.
  #
  # Typically you would achieve that result by mixing in Reaction::Subject::RepositoryContext, but
  # a PullRequest is not currently a valid subject of a reaction.
  # FIXME: Make a PullRequest a valid subject of a reaction. This will require migrating existing
  #        reactions that are currently attached to the pull request's issue.
  sig { returns(Promise[T.untyped]) }
  def async_reaction_admin
    async_issue.then(&:async_reaction_admin)
  end

  sig { returns(T.nilable(String)) }
  def reaction_path
    return @reaction_path if defined?(@reaction_path)
    async_reaction_path.sync
  end

  sig { returns(Promise[T.nilable(String)]) }
  def async_reaction_path
    async_issue.then(&:async_reaction_path)
  end

  sig { returns(T::Boolean) }
  def head_is_default_branch?
    head_ref_name == T.must(head_repository).default_branch
  end

  sig { returns(T::Boolean) }
  def head_is_protected_branch?
    head_branch_rule_evaluator.present?
  end

  sig { returns(T::Boolean) }
  def head_is_default_or_protected_branch?
    head_is_default_branch? || head_is_protected_branch?
  end

  # Public: Returns the Issue associated with this PullRequest. This helps to
  # avoid `is_a?` calls when you have a variable that can be an issue or PR.
  #
  # Examples
  #
  #   issue_or_pr.to_issue.my_favorite_issue_method
  #
  sig { returns(Issue) }
  def to_issue
    T.must(issue)
  end

  # Internal: Search the history of the base ref for the most topologically
  # recent merge commit with this PR's head_sha as a parent, i.e. the ususal
  # value of merge_commit_sha after a PR is merged.
  #
  # This is useful in cases where a PR was merged implicitly as part of another
  # PR (which eventually was merged to the base branch), or some other scheme
  # that involves merge commits but does not involve pressing the merge button.
  # In these cases we'd like to know the appropriate merge commit so that the
  # revert button continues to work.
  #
  # This is intended to be called as part of PullRequest#synchronize.  In this
  # context it should be cheap since the distance between
  # current_base_oid and head_sha should be small (since the PR will have just
  # recently been merged).  It should also be accurate for older PRs, but it
  # may have to search through quite a bit of history to come up with an
  # answer (~12s for the oldest github/github PRs)
  def determine_merge_sha(page_size: 10_000, max_pages: 5)
    repository = T.must(self.repository)

    current_base_oid = repository.refs.read(base_ref).target_oid
    range_start = current_base_oid
    range_end = head_sha
    current_page = 1
    loop do
      candidate_merge_commits = repository.rpc.read_commits(
        # git rev-list --merges -n page_size range_start..range_end
        repository.rpc.rev_list([range_start, range_end], symmetric: true, merges: true, limit: page_size),
      )

      merge_commit = candidate_merge_commits.find { |commit| commit["parents"].include?(head_sha) }
      if merge_commit
        break merge_commit["oid"]
      elsif candidate_merge_commits.size == page_size
        # Didn't find the merge commit on this page.  Try the next one unless
        # we hit our limit.
        current_page += 1
        break nil if current_page > max_pages
        range_start = candidate_merge_commits.last["oid"]
      else
        # nothing found, give up
        break nil
      end
    end
  rescue GitRPC::ObjectMissing
    nil
  end

  sig { returns(T.nilable(T::Boolean)) }
  def requires_review_thread_resolution?
    base_branch_rule_evaluator&.required_review_thread_resolution_enabled?
  end

  sig { params(reviewer: T.untyped).returns(T.nilable(T::Boolean)) }
  def blocked_from_reviewing?(reviewer)
    return unless reviewer
    @blocked_from_reviewing ||= {}
    return @blocked_from_reviewing[reviewer.id] if @blocked_from_reviewing.key?(reviewer.id)

    repository = T.must(self.repository)

    blocked_by_author_and_lacks_push_access = reviewer.blocked_by?(user) && !repository.pushable_by?(reviewer)

    @blocked_from_reviewing[reviewer.id] = blocked_by_author_and_lacks_push_access || repository.owner_blocking?(reviewer)
  end

  sig { params(user: T.untyped).returns(T::Boolean) }
  def pushed_to_head_since_open?(user)
    GitHub.dogstats.time("pull_request.pushed_to_head_since_open") do
      repositories_domain.pushes.exists_for_ref(repository_id: T.must(head_repository_id), ref: head_ref, pusher_id: user.id, pushed_at: T.unsafe(created_at))
    end
  end

  sig { params(user: T.untyped).returns(T::Boolean) }
  def show_first_contribution_prompt?(user)
    T.must(issue).show_first_contribution_prompt?(user)
  end

  # Hardcoded to maintain a shared interface with other comment types, which assume compatability with the
  # GitHub::MinimizeComment interface.
  sig { returns(T::Boolean) }
  def minimized?
    false
  end

  sig { returns(T.nilable(Numeric)) }
  def reactable_id
    T.must(issue).id
  end

  # Public: Returns the diff-relative position for a given thread id and passed
  # viewer as determined against the pull request's current pull_comparison
  #
  # Examples
  #
  #   pull_comparison.diff_relative_position_for_thread_id_with_viewer(thread_id: thread_id, viewer: viewer)
  #
  sig { params(thread_id: T.untyped, viewer: T.untyped).returns(Promise[T.nilable(Numeric)]) }
  def async_diff_relative_position_for_thread_id_with_viewer(thread_id:, viewer:)
    async_pull_comparison.then do |pull_comparison|
      pull_comparison.review_threads_for(viewer: viewer).position_for_thread_id(thread_id)
    end
  end

  sig { returns(Array) }
  def squash_commit_sign_off_actors
    changed_commits.flat_map {  |commit| commit.sign_off_actor }.compact.uniq
  end

  # Returns whether the pull request is stale (there has been a push but the PR has not been synchronized yet)
  sig { returns(T::Boolean) }
  def stale?
    return false if closed?
    return false if current_head_oid.nil?

    head_sha != current_head_oid
  end

  # Get the latest push to a ref after the current head oid
  sig { returns(T.nilable(Repositories::Push)) }
  def latest_unsynced_push_to_head_ref
    repositories_domain.pushes.latest_by_after_and_ref(repository_id: T.must(head_repository_id), ref: "refs/heads/#{head_ref}", after: current_head_oid)
  end

  sig { returns(T::Array[GitHub::Goomba::AzureBoardsLink]) }
  def links
    context = {}
    context[:entity] = repository
    GitHub::Goomba::MarkdownPipeline.call(body, context).links.uniq { |link| [link.text, link.url] }
  end

  class MergeMethodSettings < T::Struct
    class Value < T::Enum
      enums do
        Allowed = new
        Disallowed = new
        LoadError = new
      end

      sig { params(value: T::Boolean).returns(Value) }
      def self.from_bool(value)
        value ? Allowed : Disallowed
      end

      sig { returns(T::Boolean) }
      def allowed?
        case self
        when Allowed
          true
        when Disallowed, LoadError
          false
        else
          T.absurd(self)
        end
      end

      sig { returns(T::Boolean) }
      def disallowed?
        !allowed?
      end

      sig { returns(T::Boolean) }
      def error?
        case self
        when Allowed, Disallowed
          false
        when LoadError
          true
        else
          T.absurd(self)
        end
      end
    end

    const :merge_commit, Value
    const :squash_merge, Value
    const :rebase_merge, Value

    sig { params(method: MergeQueues::IConfiguration::MergeMethod).returns(Value) }
    def get(method)
      case method
      when MergeQueues::IConfiguration::MergeMethod::Merge
        merge_commit
      when MergeQueues::IConfiguration::MergeMethod::Squash
        squash_merge
      when MergeQueues::IConfiguration::MergeMethod::Rebase
        rebase_merge
      else
        T.absurd(method)
      end
    end
  end

  sig { returns(Promise[MergeMethodSettings]) }
  def async_allowable_merge_methods
    async_base_repository.then do |base_repository|
      if base_repository.feature_enabled_for_source?(:pull_request_rule_merge_types)
        promises = [
          async_merge_commit_allowed?,
          async_squash_merge_allowed?,
          async_rebase_merge_allowed?,
        ].map do |promise|
          with_async_database_error_fallback(
            promise.then { MergeMethodSettings::Value.from_bool(_1) },
            fallback: MergeMethodSettings::Value::LoadError
          )
        end

        Promise.all(promises).then do |merge_commit, squash_merge, rebase_merge|
          MergeMethodSettings.new(
            merge_commit: T.must(merge_commit),
            squash_merge: T.must(squash_merge),
            rebase_merge: T.must(rebase_merge),
          )
        end
      else
        base_repository.async_allowable_merge_methods
      end
    end
  end

  private

  # If there exists a User or Bot responsible for opening the pull request, we
  # exclude that user from the list of co-authors on the squash commit because
  # that user will be the commit's primary author.
  #
  # A commit authored by _any_ of a user's email addresses (not just verified
  # or user-entered email addresses) will associate the commit with that user.
  # So we make sure to exclude _all_ of the pull request opener's email
  # addresses from the squash commit's co-author trailers.
  #
  # Returns an Array of GitActor objects.
  sig { params(author: T.untyped).returns(Array) }
  def squash_commit_co_author_actors(author: user)
    git_actors = []
    emails_to_skip = Set.new
    if author
      author.emails.each do |ue|
        address = ue.email.downcase
        emails_to_skip.add(address)
        emails_to_skip.add(author.remove_shortcode(address))
      end
    end
    changed_commits.each do |commit|
      commit.author_actors.each do |git_actor|
        email = git_actor.display_email.downcase
        next if emails_to_skip.member?(email)
        emails_to_skip.add(email)
        git_actors << git_actor
      end
    end
    git_actors
  end

  # Impose a limit on the number of pull requests that can be created with the same head_sha.
  # See https://github.com/github/github/issues/123630 for additional context.
  sig { void }
  def validate_under_duplicate_head_sha_limit
    unless repository && T.must(repository).pull_requests.where(head_sha: head_sha).count < GitHub.duplicate_head_sha_limit
      errors.add(:base, "cannot have more than #{GitHub.duplicate_head_sha_limit} pull requests with the same head_sha.")
    end
  end

  sig { void }
  def valid_cross_repo_collab
    return unless fork_collab_state_changed?

    if fork_collab_allowed?
      if !cross_repo?
        errors.add(:base, "Fork collab can only be enabled on cross-repo pull requests")
      elsif !head_repository
        errors.add(:base, "Fork collab can't be granted when the head repository is missing")
      elsif !T.must(head_repository).pushable_by?(T.must(issue).user)
        errors.add(:fork_collab, "Fork collab can't be granted by someone without permission")
      end
    end
  end

  sig { params(via: T.untyped).returns(Hash) }
  def pr_reflog_data(via = nil)
    reflog_data = {
      pull_request_id: id,
      pull_request_head: head.b,
      pull_request_base: T.must(base).b,
      frontend: Socket.gethostname,
    }
    reflog_data[:combined_status] = combined_status.state if combined_status.any?
    reflog_data[:via] = via if via.present?
    reflog_data
  end

  sig { params(ref: T.untyped).returns(String) }
  def safe_ref_name(ref)
    ref.to_s.b.sub(/\Arefs\/heads\//, "")
  end

  sig { returns(T::Boolean) }
  def contributed_at_timezone_aware?
    contributed_at = T.unsafe(self).contributed_at
    contributed_at.present? && contributed_at > Contribution::Calendar::TIMEZONE_AWARE_CUTOVER
  end

  # Internal: Ensure this PR counts towards the user's contributions.
  sig { void }
  def clear_contributions_cache
    return unless issue = self.issue
    Contribution.clear_caches_for_user(issue.user, context: "create_pull_request")
  end

  # Internal: Updates the base ref of any of this repo's other PRs
  #           whose base ref is this PR's head ref.
  #
  # Short-circuits unless this pull is same-repo, else the wrong base
  # branch would be used.
  #
  # Short-circuits unless this pull is merged, otherwise we don't have
  # enough confidence to infer what the user's desired behavior would be.
  #
  # Return a boolean indicating success or failure.
  sig { params(actor: T.untyped).returns(T::Boolean) }
  def update_base_of_dependent_prs(actor:)
    return false unless same_repo?
    return false unless merged?
    return false if head_is_default_branch?
    return false if head_branch_rule_evaluator&.blocks_deletes_for?(actor)

    dependent_prs = PullRequest.
      open_pulls.
      to_repository(head_repository).
      for_base_ref(head_ref).
      from_repository(head_repository)

    return false if dependent_prs.count > AUTO_CHANGE_BASE_MAX_PULL_REQUESTS

    succeeded = T.let(true, T::Boolean)

    dependent_prs.each do |pr|
      begin
        # If the head ref matches the new base_ref the PR will automatically
        # be closed when we change it, lets assume they don't intended for that to happen in this odd scenario.
        next if pr.head_ref == base_ref

        prior_base_display_name = pr.display_base_ref_name
        pr.change_base_branch(actor, base_ref, automatic: true)
      rescue ActiveRecord::ActiveRecordError => err
        succeeded = false
        Failbot.report(err, "gh.pull_request.id": pr.id)
      rescue PullRequest::BaseNotChangeableError => err
        succeeded = false
        begin
          pr.create_issue_event(:automatic_base_change_failed,
                              actor,
                              message: err.error_type_key,
                              title_was: prior_base_display_name,
                              title_is: base_ref)
        rescue ActiveRecord::ActiveRecordError => err
          Failbot.report(err, "gh.pull_request.id": pr.id)
        end
      end
    end

    succeeded
  end

  sig { params(owner: T.untyped).returns(T.nilable(String)) }
  def owner_display_login(owner)
    owner&.display_login
  end
end
