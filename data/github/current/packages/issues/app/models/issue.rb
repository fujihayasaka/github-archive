# typed: true
# frozen_string_literal: true

class Issue < ApplicationRecord::Domain::IssuesPullRequests
  include Issues::IIssue
  include GitHub::UTF8
  include Issue::State
  include GitHub::UserContent
  include GitHub::Validations
  include GitHub::RateLimitedCreation
  include GitHub::Memoizer
  include GitHub::BatchedScope
  include GitHub::ResilienceMixin
  include GitHub::Prioritizable::Context
  extend GitHub::CallbackInstrumenter

  include NotificationsContent::WithCallbacks
  include Issue::NotifydAdapter
  include IssueTimeline
  include Referenceable, Referrer
  include Reaction::Subject::RepositoryContext
  include Spam::Spammable
  include UserContentEditable
  include InteractionBanValidation
  include AuthorAssociable
  include ChecklistReconciliation
  include OrgBlockable
  include AbuseReportable
  include Reactable
  include TransferableIssue
  include LegacyImportable
  include PreloadableAttributes

  include Issue::AbilityDependency
  include Issue::PermissionsDependency
  include Issue::AssignmentDependency
  include Issue::ProjectsDependency
  include Issue::DirtyDependency
  include Issue::HovercardDependency
  include Issue::PinDependency
  include Issue::SummariesDependency
  include Issue::BranchIssueReferenceDependency
  include Issue::CloseIssueReferenceDependency
  include Issue::DiscussionsDependency
  include Issue::MemexesDependency
  include Issue::IssueLinksDependency
  include Issue::IssueFormsDependency
  include Issue::IssueTypeDependency
  include Issue::AlertLinksDependency
  include Issue::StateReasonDependency
  include Issue::IssuesGraphDependency
  include Issue::HierarchyDependency
  include Issue::SubIssuesDependency
  include Issue::ConvertToIssueDependency
  include Issue::IssueDependenciesDependency

  include Repositories::BelongsToRepository

  include Storage::UserAssetTransfer::SavedReplyCopyDependency

  include Permissions::Attributes::Wrapper

  self.permissions_wrapper_class = Permissions::Attributes::Issue

  # Use timezone aware handling for created_at / updated_at
  include Issues::TimezoneTimestamp
  T.unsafe(self).timezone_timestamp :contributed_at

  # Has this issue been read by the current user?
  # Gets prefilled by Issue::SearchResult
  attr_accessor :read_by_current_user

  # Set by remove_noncollab_assignees, which saves the record.
  # Prevents an infinite loop.
  attr_accessor :skip_noncollab_assignee_callback

  # Set by edit-based API endpoints when the request was initiated by an
  # Integration on behalf of the modifying_user.
  attr_accessor :modifying_integration

  # A file under .github/ISSUE_TEMPLATES to read body content from
  attr_accessor :body_template_name

  # params that help prefill an issue for issue forms
  # prefilled by PrefilledIssueFields
  attr_accessor :structured_template_inputs

  # Is this issue being created as part of a transfer?
  attr_accessor :transfer

  # Set this if the event destroying this issue is not due to a :deletion action
  attr_accessor :deletion_hook_action

  # How many participants does the issue have?
  attr_accessor :participant_count

  # Whether or not to skip the `instrument_hydro_update_event` after_commit hook.
  # When this is set to true, the caller must call `instrument_hydro_update_event` themselves.
  attr_accessor :skip_hydro_update_event_instrumentation

  # Whether `hydro_update_event_instrumentation` should occur in the UpdateIssueOrchestration rather than the after_commit hook.
  attr_accessor :orchestrate_hydro_update_event_instrumentation

  # Whether or not to create the CreateIssueOrchestration manually
  attr_accessor :skip_create_issue_orchestration
  # Whether or not to create the UpdateIssueOrchestration manually
  attr_accessor :skip_update_issue_orchestration

  attr_writer :skip_validation_for_pr_sync

  attr_preloadable  :can_comment, :viewer_can_update, :lightweight_task_list_item_count, :lightweight_complete_task_list_item_count, :body_html,
                    :viewer_can_react, :is_transfer_in_progress, :user_is_spammy, :close_issue_references, :author_association_symbol,
                    :report_count, :top_report_reason, :last_reported_at, :viewer_can_read_user_content_edits, :reaction_groups, :reaction_path

  # Use VARBINARY limit from the database
  TITLE_BYTESIZE_LIMIT = 1024
  LABEL_LIMIT = 100

  URI_TEMPLATE = Addressable::Template.new("/{+nwo}/{type}/{number}{#anchor*}").freeze

  HELP_WANTED_LABEL_NAMES = [
    Labelable::HELP_WANTED_NAME,
    Labelable::GOOD_FIRST_ISSUE_NAME,
  ].freeze

  LOCK_REASONS = ["off-topic", "too heated", "resolved", "spam"].freeze

  class InvalidLabelAddedError < StandardError; end

  validates_presence_of :user_id, on: :create
  validate :ensure_creator_is_not_blocked, on: :create, unless: :importing?
  validates_presence_of :repository_id, :title
  validates_presence_of :contributed_at, on: :create
  validates :body, bytesize: { maximum: MYSQL_UNICODE_BLOB_LIMIT, message: "is too long" },
    length: { maximum: MYSQL_UNICODE_BLOB_LIMIT / 4, if: :new_record?, unless: :importing? },
    unicode: true, allow_blank: true, allow_nil: true
  # add bytesize validation to #compressed_body when body column is fully deprecated
  validates :compressed_body, unicode: true, allow_blank: true, allow_nil: true
  validates :title, bytesize: { maximum: TITLE_BYTESIZE_LIMIT },
    unicode: true
  validate :user_can_interact, on: :create
  validate :editor_can_interact, on: :update, if: :body_changed?
  validate :ensure_user_can_create_pr, on: :create, if: :pull_request?, unless: :importing?
  validates :labels, length: { maximum: LABEL_LIMIT, message: "can have a maximum of %{count} labels" }, unless: :skip_validation_for_pr_sync?
  validate :pull_request_id_is_not_zero
  validate :state_transition_valid?, on: :update, if: :state_or_state_reason_changed?
  validate :ensure_valid_tasklist_blocks, on: [:create, :update]
  validate :under_tasklist_blocks_limits, on: [:create, :update]

  belongs_to_repository_via_domain return_type: T.nilable(::Repository)
  destroy_in_background_with :repository
  belongs_to :user

  # rubocop:todo Rails/InverseOf
  belongs_to :performed_via_integration, foreign_key: :performed_by_integration_id,
                                         class_name: "Integration"
  # rubocop:enable Rails/InverseOf

  setup_spammable(:user)

  def entity = repository
  def async_entity = async_repository

  alias_attribute :body, :compressed_body

  has_one :pinned_issue, dependent: :destroy

  has_many :assignments, inverse_of: :issue do
    def excluding_ids(these_assignments)
      T.bind(self, T.untyped)
      these_assignments.any? ? where("id NOT IN (?)", these_assignments) : scoped
    end
  end
  destroy_dependents_in_background :assignments, sharding_key: :repository_id, sharding_value_key: :repository_id
  has_many :assignees, through: :assignments, disable_joins: true, source: :assignee, after_add: :update_assignees_changed_status, after_remove: :update_assignees_changed_status
  has_many :comments, -> { order("issue_comments.id ASC").limit(COMMENT_LIMIT) }, class_name: "IssueComment"
  destroy_dependents_in_background :comments, sharding_key: :repository_id, sharding_value_key: :repository_id
  has_many :commenters, through: :comments, source: :user, disable_joins: true
  has_many :events, -> { order("issue_events.id ASC") }, class_name: "IssueEvent", inverse_of: false
  has_many :timeline_events, -> { T.bind(self, T.untyped); visible }, class_name: "IssueEvent"
  # the default scope for `IssueEvents` includes `IssueEventDetails`, which are not always needed
  has_many :merge_events, -> { unscoped.merges.order("issue_events.id ASC") }, class_name: "IssueEvent"

  destroy_dependents_in_background :events, sharding_key: :repository_id, sharding_value_key: :repository_id
  has_many :issue_priorities
  destroy_dependents_in_background :issue_priorities, sharding_key: :repository_id, sharding_value_key: :repository_id
  has_many :issues_labels, class_name: "IssuesLabels"
  has_many :labels, through: :issues_labels, before_add: :label_in_the_same_repository, dependent: :destroy, after_add: :update_labels_changed_status, after_remove: :update_labels_changed_status

  # rubocop:todo Rails/InverseOf
  has_many :marked_duplicate_issues, dependent: :delete_all,
    class_name: "DuplicateIssue", foreign_key: "canonical_issue_id"
  # rubocop:enable Rails/InverseOf
  has_many :marked_canonical_issues, dependent: :delete_all,
    class_name: "DuplicateIssue"

  has_many :reactions, class_name: "IssueReaction"
  destroy_dependents_in_background :reactions, sharding_key: :repository_id, sharding_value_key: :repository_id

  # remove this once double-writing reactions gets removed. This is only here for destroy_dependents_in_background.
  has_many :legacy_reactions, class_name: "Reaction", as: :subject
  destroy_dependents_in_background :legacy_reactions

  belongs_to :assignee, foreign_key: :assignee_id, class_name: "User" # rubocop:todo Rails/InverseOf

  validate :ensure_assignee_is_a_collaborator, on: :create
  validate :ensure_valid_milestone
  validate :ensure_authorized_to_create_content, if: :title_or_body_changed?, unless: :importing?
  validate :ensure_not_converting_to_discussion

  belongs_to :pull_request, dependent: :destroy, inverse_of: :issue

  belongs_to :milestone, inverse_of: :issues

  # rubocop:todo Rails/InverseOf
  has_many :memex_project_items,
    ->(issue) { where(content_type: "Issue", repository_id: issue.repository_id) },
    class_name: "MemexProjectItem",
    foreign_key: :content_id
  # rubocop:enable Rails/InverseOf
  destroy_dependents_in_background(
    :memex_project_items,
    sharding_key: :repository_id,
    sharding_value_key: :repository_id,
  )
  after_touch :initialize_update_issue_orchestration # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  has_many :memex_projects, through: :memex_project_items

  has_many :issue_summaries, dependent: :destroy

  belongs_to :issue_type, inverse_of: :issues

  has_one :parent_issue_relation, foreign_key: :target_issue_id, inverse_of: :target, dependent: :destroy, class_name: "SubIssue"
  has_many :sub_issue_relations, ->(issue) { order(priority: :desc).where(source_repository_id: issue.repository_id) }, foreign_key: :source_issue_id, inverse_of: :source, class_name: "SubIssue"
  destroy_dependents_in_background :sub_issue_relations, sharding_key: :source_repository_id, sharding_value_key: :repository_id
  has_one :sub_issue_list, inverse_of: :issue

  has_one :parent, through: :parent_issue_relation, source: :source, class_name: "Issue"
  has_many :sub_issues, through: :sub_issue_relations, source: :target, class_name: "Issue"
  prioritizes :sub_issues,
    with: :sub_issue_relations,
    source: :target

  before_validation :set_state
  before_validation :set_contributed_at, on: :create
  before_validation :clean_title_and_body, on: [:create, :update]
  after_create :set_number # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_create :ensure_valid_number # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_create :create_initial_events, unless: :importing? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_create :initialize_create_issue_orchestration # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_create :set_first_contribution_flag, if: :pull_request? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_update :initialize_update_issue_orchestration # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_save :prioritize_in_milestone, if: :saved_change_to_milestone_id? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_save :trigger_milestone_change_events, if: :saved_change_to_milestone_id?, unless: -> { T.bind(self, Issue); importing? || issue_transfer? } # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_save :create_renamed_event,      if: :saved_change_to_title?, unless: :importing? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_save :update_milestone_counts!,  if: :milestone_or_state_changed? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_save :reconcile_tracking_blocks_after_save, if: :tracking_blocks_should_reconcile_after_save? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_destroy :update_milestone_counts! # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_issue_form_creation, on: :create, if: :created_from_issue_form? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_hydro_update_event, on: :update, if: :should_instrument_hydro_update_event? # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_commit :notify_socket_subscribers, on: :update # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_commit( # rubocop:disable GitHub/AvoidActiveRecordCallbacks
    :notify_summary_socket_subscribers,
    on: :update,
    if: -> do
      T.bind(self, Issue)
      previous_changes.key?(:compressed_body) || previous_changes.key?(:issue_comments_count)
    end
  )

  after_commit :reconcile_checklist, on: [:create, :update], if: :has_checklist_items? # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  # Reconciling tracking blocks requires the issue to be persisted first
  after_commit :reconcile_tracking_blocks, on: [:create, :update], if: :tracking_blocks_should_reconcile_after_commit? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  # Instrumenting adding tasklist blocks requires comparing the previous vs current body result
  before_commit :track_tasklist_blocks, unless: :spammy? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_tasklist_block_add_on_create, on: [:create], if: :has_tasklist_blocks?, unless: :spammy? # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_commit :subscribe_and_notify,            on: :create, unless: :importing? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :update_subscriptions_and_notify, on: :update # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  before_destroy :generate_webhook_payload, unless: :spammy? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_destruction, on: :destroy, unless: :spammy? # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_commit :reconcile_alerts_from_body, on: [:create, :update], if: :security_alert_items_updated? # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  setup_attachments
  T.unsafe(self).setup_referrer

  # always let these be the after_commit callbacks that are declared last in the model, this way
  # they are executed first.
  after_commit :execute_create_issue_orchestration, on: :create # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :execute_update_issue_orchestration, on: :update # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_update :sync_issues_graph_data, if: :title_or_state_changed?, unless: :importing? # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  before_destroy :abort_if_converting_to_discussion # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  # NOTE: This callback is not a transaction style callback due to the
  # repository.owner property being nil in that case. The cause is most likely
  # related to the user destruction callback chain.
  after_destroy :instrument_destroy # rubocop:disable GitHub/AfterCommitCallbackInstrumentation, GitHub/AvoidActiveRecordCallbacks

  attribute :title, StringFromBinary.new
  attribute :compressed_body, CompressedString.new(self.name, "body")

  scope :grouped_by_repo,    -> { group("issues.repository_id") }
  scope :open_issues,        -> { where(state: "open").order("issues.id ASC") }
  scope :closed_issues,      -> { where(state: "closed").order("issues.created_at DESC") }
  scope :fresh,              -> (threshold: 1.month.ago) {
    where("issues.updated_at >= ?", threshold)
  }
  scope :stale,              -> (threshold: 1.month.ago) {
    where("issues.updated_at < ?", threshold)
  }
  scope :with_no_milestone,  -> { where(milestone_id: nil) }
  scope :with_any_milestone, -> { where("issues.milestone_id IS NOT NULL") }
  scope :assigned_to, lambda { |login|
    assignee = User.reify(login)
    raise AssigneeInvalid.new(login.to_s, "Could not find assignee: %p" % login.to_s) unless assignee
    joins(:assignments).where(assignments: { assignee_id: assignee.id })
  }

  scope :unassigned, -> {
    joins("LEFT OUTER JOIN `assignments` ON `assignments`.`issue_id` = `issues`.`id`").
      where("assignments.issue_id IS NULL")
  }

  scope :assigned, -> { where("assignee_id IS NOT NULL") }
  scope :created_by, lambda { |login|
    creator = (user = User.find_by_login(login) and user.id) or nil

    for_user(creator)
  }
  scope :mentioning, lambda { |user|
    where(id: IssueEvent.select(:issue_id).where(actor_id: user.id, event: "mentioned").group(:issue_id))
  }
  scope :from_ids, lambda { |ids| where(id: ids) }
  scope :participating, lambda { |user|
    where(id: IssueComment.select(:issue_id).where(user_id: user.id).group(:issue_id)).or(Issue.where(user_id: user.id))
  }

  # Scope issues by a Label id (or array of them), case-insensitive Label name (or array of them) or
  # a Label class instance.
  scope :labeled, ->(label_or_collection) do
    case label_or_collection
    when Integer
      joins(:labels).where("issues_labels.label_id = ?", label_or_collection)
    when Array
      scope = joins(:labels)

      scope = case label_or_collection.first
      when Integer, Label
        scope.where("issues_labels.label_id IN (?)", label_or_collection)
      when String
        scope.merge(Label.with_name(label_or_collection)).where("labels.repository_id = issues.repository_id")
      else
        scope
      end

      # we need to do this funky HAVING clause because we are approximating ANDing the labels together
      # and a simple `labels.name` IN (?) only handles an OR. This part of the query is heavy so we
      # avoid it if only single label is passed
      if label_or_collection.size > 1
        scope.group("issues.id").having("COUNT(issues.id) = #{label_or_collection.size}")
      else
        scope
      end
    when String
      joins(:labels).merge(Label.with_name(label_or_collection)).where("labels.repository_id = issues.repository_id")
    when Label
      joins(:labels).where("issues_labels.label_id = ?", label_or_collection.id)
    end
  end

  scope :labeled_by_any, -> (label_or_collection) do
    case label_or_collection
    when Integer
      joins(:labels).where("labels.id = ?", label_or_collection)
    when Array
      joins(:labels).merge(Label.with_name(label_or_collection)).where("labels.repository_id = issues.repository_id")
    end
  end

  scope :sorted_by, lambda { |order, direction = "desc"|
    order = sorted_by_field(order)
    dir = (direction.to_s == "asc" ? "ASC" : "DESC")
    order(Arel.sql("#{order} #{dir}"))
  }

  scope :excluding_states, lambda { |excluding|
    # By default, we show only open pull requests on non-ajax requests
    if excluding.to_s.split(",").any?
      exclude = excluding.to_s.split(",").compact
    else
      exclude = ["closed"]
    end

    scope = self.includes(:issue).references(:issue)
    scope = scope.where("issues.state <> 'open'") if exclude.include?("open")
    scope = scope.where("issues.state <> 'closed'") if exclude.include?("closed")
    scope
  }

  scope :for_milestone, lambda { |milestone|
    where(milestone_id: milestone)
  }

  scope :for_milestone_number, lambda { |milestone_number|
    joins(:milestone).where("milestones.number = ?", milestone_number)
  }

  scope :for_repository_ids, lambda { |ids|
    where("issues.repository_id IN (?)", ids)
  }

  scope :excluding_repository_ids, lambda { |ids|
    where("issues.repository_id NOT IN (?)", ids)
  }

  scope :for_repository, lambda { |repository|
    where("issues.repository_id = ?", repository)
  }

  scope :for_user, lambda { |user|
    where(user_id: user)
  }

  scope :for_organization, lambda { |organization|
    return none if organization.nil?
    repo_ids = Repository.where(organization_id: organization).pluck(:id)
    where(repository_id: repo_ids)
  }

  scope :since, lambda { |time|
    where("issues.updated_at >= ?", time)
  }

  scope :without_pull_requests, -> { where(pull_request_id: nil) }
  scope :with_pull_requests,    -> { where.not(pull_request_id: nil) }

  # hard limit on the number of comments that can be added to an issue
  # beyond this value IssueComments will fail validation when they are created
  COMMENT_LIMIT = 2500

  # maximum numbers of Users to load for display in the Participants section in the sidebar
  VIEW_PARTICIPANT_LOAD_LIMIT = 20

  SUGGESTION_LIMIT = 1000
  SORT_FIELDS      = %w[created updated comments].freeze
  SORT_DIRECTIONS  = %w[desc asc].freeze

  scope :suggestions, -> do
    columns = "id, number, title, pull_request_id, updated_at, closed_at, state_reason"
    select(columns).order("updated_at desc").limit(SUGGESTION_LIMIT)
  end

  def skip_validation_for_pr_sync?
    @skip_validation_for_pr_sync
  end

  def target_for_conditional_access
    T.must(repository).target_for_conditional_access
  end

  def self.sorted_by_field(order)
    case order.to_s
    when "created" then "issues.created_at"
    when "updated" then "issues.updated_at"
    when "comments" then "issues.issue_comments_count"
    else "issues.created_at"
    end
  end

  def self.filter_for_public_repos_ids(issue_ids)
    repo_id_by_issue_id = Issue.where(id: issue_ids).pluck(:id, :repository_id)
    repo_ids = repo_id_by_issue_id.map(&:second).uniq
    public_repo_ids = Repository.public_scope.where(id: repo_ids).pluck(:id)
    issue_ids = repo_id_by_issue_id.filter { |_issue_id, repo_id| public_repo_ids.include? repo_id }.map(&:first)
  end

  def self.filter_for_public_repos(issue_ids)
    where(id: filter_for_public_repos_ids(issue_ids))
  end

  # Determines the target for for conditional access for multiple pull requests
  #
  # issues - an enumerable of Issue
  #
  # returns Hash[Issue] => target for conditional access
  def self.multiple_target_for_conditional_access(issues)
    ConditionalAccess::Filter.ensure_with_class(issues, Issue)

    repositories = Repository.where(id: issues.map { |issue| issue.repository_id })
    repository_to_target = Repository.multiple_target_for_conditional_access(repositories)

    repository_id_to_target = repository_to_target.transform_keys { |k| k.id }
    issues.each_with_object({}) { |v, h| h[v] = repository_id_to_target[v.repository_id] }
  end

  def self.count_by_repo(issues)
    repo_counts = {}
    repo_count_issue_ids = issues.pluck(:id)
    issues.grouped_by_repo.count({
      group: "issues.repository_id",
      conditions: ["issues.id IN(?)", repo_count_issue_ids],
    }).each do |count|
      repo_counts[count[0].first] = count[1]
    end

    repo_counts
  end

  def title=(value)
    self[:title] = value.to_s if value
  end

  # If there is an associated pull request, it needs to have the same timestamp.
  #
  # The pull request may have already been updated, so verify that the timestamp
  # is out of date before updating to avoid a redundant query (see #57779).
  #
  # Execute in an orchestration step after both save and touch - outside the
  # model's lifecycle transaction to avoid locking issues.
  def sync_pull_request_updated_at
    pull_request = T.unsafe(self.pull_request)

    return if pull_request.nil? || pull_request.frozen? || pull_request.new_record?

    if pull_request.updated_at.to_i < updated_at.to_i
      # update_column doesn't invoke callbacks.
      pull_request.update_column(:updated_at, updated_at)
    end
  end

  memoize def template
    return nil unless body_template_name.present?
    @template = T.must(repository).preferred_issue_templates[body_template_name]
  end

  # Deprecated. Use Issue#template
  def raw_body_template
    return unless repository = self.repository
    return @body_template if defined?(@body_template)
    return @body_template = repository.preferred_issue_template&.data unless body_template_name.present?

    local_file = PreferredFile.find(
      directory: repository.root_directory,
      type: :issue_template,
      nested_filename: body_template_name,
    )&.data

    if !local_file.present? && !repository.global_health_files_repository?
      global_repo = repository.global_health_files_repo
      return @body_template = nil unless global_repo.present?

      @body_template = PreferredFile.find(
        directory: global_repo.root_directory,
        type: :issue_template,
        nested_filename: body_template_name,
      )&.data
    else
      @body_template = local_file
    end
  end

  def body
    compressed_body
  end

  def compressed_body=(value)
    value = value.presence
    super
  end
  alias_method :body=, :compressed_body=

  # Public: Find the user supplied template to use in the body of
  # new issues if one exists.
  #
  # Read from a file under .github/ISSUE_TEMPLATES or ISSUE_TEMPLATE.md.
  #
  # Returns a String from the template if one is found.
  # Returns nil if no template is found.
  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def body_template
    @body_template ||= begin
      body = template&.body&.to_s || raw_body_template
      body&.gsub(GitHub::Goomba::YamlFilter::FRONTMATTER_REGEX, "")
    end
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

  # Deprecated. Use Issue#template
  def has_body_template?
    !!body_template
  end

  # Fallback on the ghost user when the original author's been deleted.
  # See User.ghost for more.
  def safe_user
    user || User.ghost
  end

  # The user who performed the action as set in the GitHub request context. If the context doesn't
  # contain an actor, fallback to the safe_user which we know exists.
  def modifying_user
    @modifying_user ||= if (actor_id = GitHub.context[:actor_id]).present?
      User.find_by(id: actor_id) || safe_user
    else
      safe_user
    end
  end
  attr_writer :modifying_user

  # Internal: For suggestions_params helper
  def suggestion_id
    id
  end

  # Public: Find all Users that have participated in this issue, by either
  # commenting or performing a participatory action.
  # Exclude Bots and users who no longer have access to this repo
  # (unless parent org has so many members that query may timeout).
  # Exclude Organizations from results as participants should be Users, but
  # Users can transform into Organizations.
  #
  # Note that the returned users are not filtered for spam.
  #
  # optimize_repo_access_checks - by default, #user_ids_to_hide_from_mentions will
  #                               check to make sure that each user returned still
  #                               has access to the repo. If optimize_repo_access_checks
  #                               is set to true, that check will not happen if the
  #                               parent org has too many members (which may
  #                               cause the access checks to time out)
  # user_limit - limits the number of Users to load when set. If participants has already been
  #               memo-ized, the limit will not be applied
  #
  # Returns an Array of Users.
  def participants(optimize_repo_access_checks: false, user_limit: nil, viewer: nil)
    return T.must(pull_request).participants(viewer:, optimize_repo_access_checks: optimize_repo_access_checks) if pull_request?
    @participants ||= begin
      user_ids = comment_and_event_participant_ids << self.user_id
      user_ids_to_hide = T.must(repository).user_ids_to_hide_from_mentions(user_ids, optimize_repo_access_checks: optimize_repo_access_checks)
      participant_ids = user_ids - user_ids_to_hide
      users = User.where(id: participant_ids, type: "User").includes(:profile).to_a
      self.participant_count = users.size
      users
    end

    if user_limit.to_i > 0
      @participants.take(user_limit.to_i)
    else
      @participants
    end
  end

  # Internal: Find all the actors that have participated in this Issue through
  # the events association
  #
  # Returns an array of actors
  def get_event_participants
    User.where(id: event_participant_ids)
  end

  # Internal: Find all the actors that have participated in this Issue through
  # the events association
  #
  # Returns an array of actor_ids
  def event_participant_ids
    # The `unscoped` call is being used on the IssueEvent model to remove the include from that model's default scope. Calling
    # `unscoped` on the 'events' association also removes the issue scoping, which is why the IssueEvent model is used directly here.
    @event_participant_ids ||= track_exec_time("issue.participants.event_participant_ids", tags: %W[pull_request:#{pull_request?}]) do
      IssueEvent.unscoped.where(issue: self).participatory.distinct.pluck(:actor_id)
    end
  end

  # Internal: Compiles the commenter IDs
  #
  # Returns an array of commenter ids
  def commenter_ids
    return [] unless comments?
    @commenter_ids ||= track_exec_time("issue.participants.commenter_ids", tags: %W[pull_request:#{pull_request?}]) do
      comments.reorder(nil).pluck(:user_id)
    end
  end

  # Internal: Compiles the comment and event participant IDs
  #
  # Returns an array of User objects
  def comment_and_event_participant_ids
    @comment_and_event_participant_ids ||= (commenter_ids + event_participant_ids).compact.uniq
  end

  # Users who should be considered issue participants.
  #
  # viewer - the User who is viewing the participants (current_user)
  # optimize_repo_access_checks - if optimize_repo_access_checks is set
  #                               to true, do not perform access checks
  #                               on repos that are owned by org's with
  #                               a lot of members
  # user_limit - limits the number of Users to load when set. If participants has already been
  #               memo-ized, the limit will not be applied
  #
  # Returns an Array of Users.
  def participants_for(viewer, optimize_repo_access_checks: false, user_limit: nil)
    participants(optimize_repo_access_checks: optimize_repo_access_checks, user_limit: user_limit, viewer:).reject do |u|
      u.hide_from_user?(viewer)
    end
  end

  # Public: Retrieve the timeline for the given viewer
  #
  # viewer         - A User that is viewing the timeline
  # filter_options - Hash of options passed to the timeline instance
  #
  # Returns Timeline::IssueTimeline
  def timeline_model_for(viewer, filter_options = {})
    return @timeline_model_for[[viewer, filter_options]] if defined?(@timeline_model_for)

    @timeline_model_for = Hash.new do |hash, (viewer, filter_options)|
      hash[[viewer, filter_options]] = Timeline::IssueTimeline.new(
        self, viewer: viewer, filter_options: filter_options
      )
    end
    @timeline_model_for[[viewer, filter_options]]
  end

  # Hardcoded to maintain a shared interface with other comment types, which assume compatability with the
  # GitHub::MinimizeComment interface.
  def minimized?
    false
  end

  def references?
    return @any_references if defined?(@any_references)
    @any_references = references.any?
  end

  # NOTE: This does not perform visibility checks on the events returned. Those
  # will be performed by the timeline loader.
  def has_timeline_items?
    comments? || timeline_events? || references?
  end

  # NOTE: This does not perform visibility checks on the events returned. Those
  # will be performed by the timeline loader.
  def timeline_is_only_comments?
    comments? && !timeline_events? && !references?
  end

  def timeline_includes_types?(types)
    events.where(event: types).any?
  end

  def show_issue_deletion_opt_in_link?(user)
    repository = T.must(self.repository)
    return false unless repository.owner&.organization?
    return false if T.unsafe(repository.owner).members_can_delete_issues?
    return false unless repository.owner&.adminable_by?(user)
    true
  end

  def transferrable_by?(user)
    repository = T.must(self.repository)
    !pull_request? && repository.writable? && repository.resources.contents.writable_by?(user) && !locked?
  end

  def async_transferrable_by?(user)
    return Promise.resolve(false) if pull_request? || !user

    repository = T.must(self.repository)

    Promise.all([
      async_locked?,
      repository.async_writable?,
      repository.resources.contents.async_writable_by?(user)
    ]).then do |(locked, writable, contents_writable)|
      !locked && writable && contents_writable
    end
  end

  def async_possible_transfer_repositories(viewer:, query: nil)
    async_repository.then do |repository|
      target_repo_scope = Repository.active.where(owner_id: T.must(repository).owner_id).
        filter_spam_and_disabled_for(viewer).
        with_issues_enabled.
        not_archived_scope

      if T.must(repository).private?
        target_repo_scope = target_repo_scope.private_scope
      end

      target_repo_scope = target_repo_scope.with_substring(:name, query) if query.present?

      if GitHub.flipper[:limit_transfer_repo_suggestions].enabled?(T.must(repository).owner)
        target_repo_scope = target_repo_scope.limit(10)
      end

      target_repo_scope_ids = target_repo_scope.ids - [repository_id]

      repository_ids = viewer.associated_repository_ids(min_action: :write, repository_ids: target_repo_scope_ids)

      repos = target_repo_scope.select { |repo| repository_ids.include?(repo.id) }.sort_by(&:updated_at).reverse.partition { |repo| repo.name == query }.flatten.take(10)

      repos = Repository.where(id: repos.collect(&:id)).to_a

      if query
        repos.sort_by! { |repo| [T.must(repo.name).start_with?(query) ? 1 : 0, repo.updated_at] }
      else
        repos.sort_by! { |repo| repo.updated_at }
      end

      repos.reverse!
    end
  end

  # Determine whether user has commented on this issue.
  #
  # user - A User object.
  #
  # Returns true when user has left at least one comment.
  def commented_on_by?(user)
    commenters.include?(user)
  end

  # Public returns a promise that is resolved with a boolean indicating if a user has commented
  # on this issue
  #
  # Note: This is different then the normal #commented_on_by? by method in that it uses a limit
  # query for efficiency instead of querying all commenters through the association:
  # `IssueComment.select(:user_id).where(issue: self, user_id: user_id).limit(1).exists?`
  #
  # user - User instance
  #
  # Returns a Promise
  def async_commented_on_by?(user)
    Platform::Loaders::HasCommented.load(self, user.id)
  end

  def generate_webhook_payload
    if modifying_user&.spammy?
      @delivery_system = nil
      return
    end

    event_guid = Events::Tier1EventPublisher.new_guid(Time.now)
    @deleted_tier1_event = Events::IssuesPublisher.generate_deleted_tier1_event(
      issue: self, actor: modifying_user, repository: repository, guid: event_guid)

    action = deletion_hook_action || :deleted
    event = Hook::Event::IssuesEvent.new issue_id: id, actor_id: modifying_user.id, action: action, event_guid: event_guid


    @delivery_system = Hook::DeliverySystem.new(event)

    @delivery_system.generate_hookshot_payloads

    if parent.present?
      @parent_issue_delivery_system = []
      sub_issue_event = Hook::Event::SubIssuesEvent.new(
        action: :sub_issue_removed,
        parent_issue_id: parent&.id,
        child_issue_id: id,
        actor_id: modifying_user.id,
        triggered_at: Time.now
      )
      parent_issue_event = Hook::Event::SubIssuesEvent.new(
        action: :parent_issue_removed,
        parent_issue_id: parent&.id,
        child_issue_id: id,
        actor_id: modifying_user.id,
        triggered_at: Time.now
      )
      @parent_issue_delivery_system << Hook::DeliverySystem.new(sub_issue_event).tap(&:generate_hookshot_payloads)
      @parent_issue_delivery_system << Hook::DeliverySystem.new(parent_issue_event).tap(&:generate_hookshot_payloads)
    end

    if sub_issues.present?
      @sub_issue_delivery_system = []
      sub_issues.each do |sub_issue|
        sub_issue_event = Hook::Event::SubIssuesEvent.new(
          action: :sub_issue_removed,
          parent_issue_id: id,
          child_issue_id: sub_issue.id,
          actor_id: modifying_user.id,
          triggered_at: Time.now
        )
        parent_issue_event = Hook::Event::SubIssuesEvent.new(
          action: :parent_issue_removed,
          parent_issue_id: id,
          child_issue_id: sub_issue.id,
          actor_id: modifying_user.id,
          triggered_at: Time.now
        )
        @sub_issue_delivery_system << Hook::DeliverySystem.new(sub_issue_event).tap(&:generate_hookshot_payloads)
        @sub_issue_delivery_system << Hook::DeliverySystem.new(parent_issue_event).tap(&:generate_hookshot_payloads)
      end
    end
  end

  def instrument_destruction
    unless defined?(@delivery_system)
      raise "`generate_webhook_payload` must be called before `instrument_destruction`"
    end

    if @deleted_tier1_event.present?
      # This is temporary until we migrate the issues deleted event to use the new staffshipping flags.
      # https://github.com/github/ecosystem-events/issues/4916
      event_flags = Events::Tier1EventPublisher::EventFlags.new(
        webhook_deliveries_enabled: false,
        hookshot_deliveries_enabled: true,
        events_v2_validation_enabled: false,
        publish_tier1_events: true,
      )
      Events::IssuesPublisher.publish_tier1_event(tier1_event: @deleted_tier1_event, event_flags: event_flags)
    end

    @delivery_system&.deliver_later
    @parent_issue_delivery_system&.map(&:deliver_later)
    @sub_issue_delivery_system&.map(&:deliver_later)
  end

  # Add labels to an issue, updates the search index and updated_at timestamp
  #
  # labels - an Array of Label objects
  def add_labels(labels)
    labels = [labels] if !labels.respond_to?(:each)

    Issue.transaction do
      labels.each do |label|
        begin
          next if self.labels.include?(label)

          trigger_label_event(label)
          self.labels << label
        rescue ActiveRecord::RecordNotUnique
          # long hair, don't care
        end
      end
      raise ActiveRecord::RecordInvalid.new(self) unless valid?

      self.touch
    end
    notify_socket_subscribers
    update_repo_community_profile(changed_labels: labels)
    self
  end

  # Add labels from issues by id.
  #
  # ids - an Array of Label ids
  def add_label_ids(ids)
    labels = T.must(repository).labels.where("labels.id IN (?)", ids).to_a
    add_labels(labels)
  end

  # Remove labels from an issue, updates the search index
  # and updated_at timestamp
  #
  # labels - an Array of Label objects
  def delete_labels(labels)
    # only delete the label and trigger events if the label is associated with the issue
    labels = self.labels.where(id: Array(labels).map(&:id))
    return self if labels.empty?

    Issue.transaction do
      labels.each do |label|
        trigger_unlabel_event(label)
      end
      self.labels.delete(labels)
      self.touch
    end

    notify_socket_subscribers
    update_repo_community_profile(changed_labels: labels)
    self
  end

  # Remove labels from issues by id.
  #
  # ids - an Array of Label ids
  def delete_label_ids(ids)
    labels = T.must(repository).labels.where("labels.id IN (?)", ids).to_a
    delete_labels(labels)
  end

  # Remove all labels from an issue, updates the search index
  # and updated_at timestamp
  def clear_labels
    labels_to_clear = self.labels
    Issue.transaction do
      labels_to_clear.each { |label| trigger_unlabel_event(label) }
      self.update(labels: [])
      self.touch
    end
    notify_socket_subscribers
    update_repo_community_profile(changed_labels: labels_to_clear)
    self
  end

  # Public: Replace all labels on an issue, updates the search index
  # and updated_at timestamp
  #
  # new_labels: an Array of Label objects
  #
  # Returns a Boolean.
  def replace_labels(new_labels)
    replacement_successful = T.let(true, T::Boolean)

    # sort labels to avoid deadlocks during concurrent transaction execution.
    old_labels = self.labels.to_a.sort_by { T.must(_1.id) }
    new_labels = new_labels.to_a.sort_by(&:id)

    Issue.transaction do
      destroy_replaced_labels(old_labels, new_labels)
      create_replaced_labels(old_labels, new_labels)

      self.touch

      # Because this method was earlier implemented to use raw SQL to insert IssuesLabels records,
      # it supported an API in which an invalid issue could be returned with a
      # valid and unchanged list of labels.
      # A minor refactor swapped the SQL for ActiveRecord statements to create
      # IssuesLabels while invoking that model's callbacks.
      # But, in order to adhere to the existing API of this method,
      # we are still manually associating labels on the two lines above
      # and manually rolling back transactions.
      unless self.valid?
        replacement_successful = false
        raise ActiveRecord::Rollback
      end
    end

    return false unless replacement_successful
    notify_socket_subscribers
    update_repo_community_profile(changed_labels: new_labels + old_labels)
    true
  end

  def pull_request?
    !pull_request.nil?
  end

  def async_pull_request?
    async_pull_request.then do |pr|
      !pr.nil?
    end
  end

  # Public: Ensures API responses stay fresh. The last_modified_at values are
  # used to calculate the Last-Modifed and ETag values for API responses.
  #
  # It's important that it returns the most recent timestamp of all the
  # associated objects, because the JSON representation of an issue includes
  # those nested objects in the response. If any of them change, the entire
  # JSON representation of the issue changes, and its ETag and Last-Modified
  # values need to reflect that.
  def last_modified_at
    @last_modified_at ||= T.unsafe(self).last_modified_with(:user, :assignees, :pull_request,
      :milestone)
  end

  # Check if this issue has already been closed by the specified commit.
  def already_closed_by_commit?(commit_oid)
    @close_commit_oids ||= Set.new(events.where(event: "closed").pluck(:commit_id).compact)
    @close_commit_oids.include?(commit_oid)
  end

  batch_method(:closed_by_commit_oids) do |issues|
    issues_by_id = issues.index_by(&:id)
    issue_ids = issues_by_id.keys

    rows = IssueEvent.unscoped. # default scope joins with details
      where(event: "closed", issue_id: issue_ids).
      pluck(:issue_id, :commit_id)

    rows.each_with_object(Hash.new { |h, k| h[k] = Set.new }) do |(issue_id, commit_id), hash|
      issue = issues_by_id[issue_id]
      hash[issue].add(commit_id)
    end
  end

  # Add an issue event to note that the issue was referenced from a commit.
  #
  #   user              - User who referenced the issue
  #   commit_id         - commit SHA1 that referenced this issue
  #   commit_repository - Repository that owns the commit (for cross repository
  #                       references only).
  #
  # Returns the new IssueEvent record when successful, nil otherwise.
  def reference_from_commit(user, commit_id, commit_repository = nil)
    # Do not create duplicate events for the same commit
    return if events.where(commit_id: commit_id, event: "referenced").exists?

    # Do not add events for commits to merge queue prep branches
    return if T.must(repository).merge_queue_commits_include?(commit_id)

    ignore_duplicate_records do
      event = events.create! \
        event: "referenced",
        actor: user,
        commit_id: commit_id,
        commit_repository: commit_repository

      # only subscribe if the commit came from the same repository
      if commit_repository&.id == repository_id
        subscribe(user, :comment)
      end

      event
    end
  end

  def subscribe(user, action = nil, events = [])
    if ["team-mentioned", "mentioned", "manual", :team_mention, :mention, :manual].include?(action)
      subscribe_with_event(user)
    end

    super user, action, events
  end

  def subscribe_all(users, action = nil)
    if ["team-mentioned", "mentioned", "manual", :team_mention, :mention, :manual].include?(action)
      subscribe_all_with_event(users)
    end

    super users, action
  end

  # Public: Subscribes a User to receive notifications from this Issue.
  #
  # user   - The User that receives the notifications.
  # action - The optional String IssueEvent action.
  #
  # Returns true if the subscription is successful.
  def subscribe_with_event(user)
    return unless subscribable_by?(user)
    ignore_duplicate_records do
      events.create(actor: user, event: "subscribed")
      true
    end
  end

  # Public: Subscribes an array of users to receive notifications from this Issue.
  #
  # user   - The array of users that receive the notifications.
  #
  def subscribe_all_with_event(users)
    users.each_slice(GitHub.subscribed_users_batch_size).each do |batched_users|
      CreateSubscribedIssueEventsJob.perform_later(self.id, batched_users.map(&:id))
    end
  end

  # Public: Unsubscribes a User from receiving any more notifications for this
  # Issue.
  #
  # user - The User that won't receive any more notifications.
  #
  # Returns true if the unsubscribe event is successful.
  def unsubscribe(user)
    super user
    ignore_duplicate_records do
      events.create(actor: user, event: "unsubscribed")
      true
    end
  end

  def notifications_author
    user
  end

  def notifications_thread
    self
  end

  # Each pull request has a backing issue with the same number.
  # Because of unfortunate historic reasons, we pass the issue of a pull request
  # to Newsies when triggering a notification. In order to support thread type subscriptions
  # for pull requests, we need to define a custom `notifications_subscription_type`
  # that allows Newsies to differentiate between "real" issues and "pull request" issues.
  def notifications_subscription_type
    PullRequest if pull_request_id.present?
  end

  def async_notifications_list
    async_repository
  end

  # Subscribe a list of mentioned users to this issue. This also creates
  # mentioned events.
  #
  # mentions - Array of users that were mentioned. This defaults to users
  #            mentioned in the issue body but a custom array may be passed
  #            from associated comment models and whatnot too.
  # author   - Author of the content being posted.  Defaults to #user.
  #
  # Returns nil.
  def subscribe_mentioned(mentions = mentioned_users, author = user)
    return if author && author.spammy?
    subscribable_user_mentions(mentions, author) do |mentionee, author|
      unless author && author.blocked_by?(mentionee)
        events.create!(event: "mentioned", actor: mentionee, author: author)
        subscribe(mentionee, :mention)
      end
    end
  end

  # Internal: Filters out users that should keep a subscription to this thread.
  # This should be called after a comment has been edited, with a mentioned
  # user removed due to a typo.  Remove anyone that hasn't commented already.
  #
  # users - Array of Users.
  #
  # Returns an Array of User that can be unsubscribed.
  def unsubscribable_users(users)
    commenters = Set.new
    collect_commented_users commenters, comments
    if pull = (pull_request? && pull_request)
      collect_commented_users commenters, pull.review_comments
    end
    commenters.add(user_id).merge(assignments.map(&:assignee_id))

    users.reject { |user| commenters.include?(user.id) }
  end

  def collect_commented_users(set, scope)
    comments.select("distinct user_id").each do |comment|
      set << comment.user_id
    end
  end

  sig { returns(T.untyped) }
  def summary_websocket_channel
    GitHub::WebSocket::Channels.issue_summary(self)
  end

  # Internal: Notify subscribers that content related to issue summary has been updated.
  #
  # Returns Set of channel id Strings that were notified.
  sig { returns(T.untyped) }
  def notify_summary_socket_subscribers
    GitHub::WebSocket.notify_issue_channel(self, summary_websocket_channel,
      timestamp: Time.now.to_i,
      wait: default_live_updates_wait,
      reason: "Issue ##{id} updated with a change relevant to summarization",
      # This is a load-bearing gid: https://github.com/github/github/pull/146273/files#r438329053
      gid: global_relay_id,
    )
  end

  # Internal: Notify subscribers that the issue has been updated.
  #
  # Returns Set of channel id Strings that were notified.
  def notify_socket_subscribers(notify_associated: true, associated_updates: {})
    # If we're being deleted, no reason to notify anyone or if being imported
    return if !repository || self.importing?

    if pull_request?
      associated_updates = {}
      if @assignees_changed
        associated_updates["assignees_updated"] = true
      end
      if @labels_changed
        associated_updates["labels_updated"] = true
      end
      if @milestone_changed
        associated_updates["milestone_updated"] = true
      end

      pull_request&.notify_socket_subscribers(associated_updates:)
    else
      data = {
        timestamp: Time.now.to_i,
        wait: default_live_updates_wait,
        reason: "issue ##{id} updated",
        gid: global_relay_id,
      }

      channel = GitHub::WebSocket::Channels.issue(self)
      GitHub::WebSocket.notify_issue_channel(self, channel, data)
      if previous_changes["state"] || previous_changes["state_reason"]
        Platform::Schema.subscriptions.trigger(:issue_updated, { id: global_relay_id }, object: { issue_state_updated: true })
      end
      if previous_changes["title"]
        Platform::Schema.subscriptions.trigger(:issue_updated, { id: global_relay_id }, object: { issue_title_updated: true })
      end
      if previous_changes["compressed_body"]
        Platform::Schema.subscriptions.trigger(:issue_updated, { id: global_relay_id }, object: { issue_body_updated: true })
      end
      if previous_changes["issue_type_id"]
        Platform::Schema.subscriptions.trigger(:issue_updated, {}, object: { issue_type_updated: true }, scope: global_relay_id)
      end
      if @sub_issues_changed
        Platform::Schema.subscriptions.trigger(:issue_updated, { id: global_relay_id }, object: { sub_issues_updated: true })
        @sub_issues_changed = nil
      end
      if @sub_issues_summary_changed
        Platform::Schema.subscriptions.trigger(:issue_updated, { id: global_relay_id }, object: { sub_issues_summary_updated: true })
        @sub_issues_summary_changed = nil
      end
      if @parent_issue_changed
        Platform::Schema.subscriptions.trigger(:issue_updated, { id: global_relay_id }, object: { parent_issue_updated: true })
        @parent_issue_changed = nil
      end
      if @transfer_state_changed
        Platform::Schema.subscriptions.trigger(:issue_updated, { id: global_relay_id }, object: { issue_transfer_state_updated: true })
        @transfer_state_changed = nil
      end
      if @labels_changed || @assignees_changed || @milestone_changed
        Platform::Schema.subscriptions.trigger(:issue_updated, { id: global_relay_id }, object: { issue_metadata_updated: true })
        reset_meta_data_changed_flags
      end

    end

    if prev_state_changes = previous_changes["state"]
      data = {
        timestamp: Time.now.to_i,
        wait: default_live_updates_wait,
        reason: "issue ##{id} state changed to #{state}",
        state_changes: prev_state_changes,
      }
      channel = GitHub::WebSocket::Channels.issue_state(self)
      GitHub::WebSocket.notify_issue_channel(self, channel, data)
    end


    if notify_associated
      if milestone
        milestone&.notify_subscribers
      end

      cards.each(&:notify_subscribers)
    end
  end

  def notify_graphql_subscribers
    unless pull_request?
      Platform::Schema.subscriptions.trigger(:issue_updated, { id: global_relay_id }, object: { issue_reaction_updated: true })
    end
  end

  # Public: Syncs the thread's read state if the user has it open in a browser.
  #
  # user - The User that read the thread.
  #
  # Returns true if queued, false if not.
  def sync_thread_read_state(user)
    target = pull_request? ? pull_request : self
    channel = GitHub::WebSocket::Channels.marked_as_read(user)
    GitHub::WebSocket.notify_user_channel(user.id, channel, gid: target&.global_relay_id, timestamp: Time.now.to_i, wait: default_live_updates_wait)
  end

  # Public: Syncs the thread's state (read/unread, save/unsave, archive/unarchive) if the user has it open in a browser.
  #
  # user - The User that read the thread.
  #
  # Returns true if queued, false if not.
  def sync_notifications_changed(user)
    target = pull_request? ? pull_request : self
    return unless target

    channel = GitHub::WebSocket::Channels.notifications_changed_per_issue(user, target.number, target.repository&.name)
    GitHub::WebSocket.notify_issue_channel(self, channel)
  end

  # Returns the timestamp of the latest change in the issue's thread,
  # usually either the issue's created_at or the created_at of the most
  # recently added comment.
  def latest_change
    if T.unsafe(self).issue_comments_count > 0 && last_comment = comments.last
      last_comment.created_at
    else
      created_at
    end
  end

  # open/close issues
  def modifiable_by?(user)
    user.is_a?(User) && T.must(repository).pushable_by?(user)
  end

  # Can the given actor lock this Issue?
  def lockable_by?(actor)
    repository = T.must(self.repository)

    case actor
    when Bot, IntegrationInstallation, ProgrammaticAccessBot
      if self.pull_request?
        repository.resources.pull_requests.writable_by?(actor)
      else
        repository.resources.issues.writable_by?(actor)
      end
    else
      repository.writable_by?(actor) || actor.site_admin?
    end
  end
  alias :unlockable_by? :lockable_by?

  def self.valid_lock_reason?(reason)
    LOCK_REASONS.include?(reason)
  end

  def active_lock_reason
    return unless locked?
    events.locks.last&.lock_reason
  end

  # This is a set of checks against the issue's parent repo, to determine
  # if it should be removed from the index. Since these are repo-level checks,
  # if the repo is found to be unsearchable, a delete of _all issues for that repo_
  # from the index will be triggered. Handle individual issue-shouldn't-be-searchable
  # events from inside prune_issue method directly, not here.
  #
  # Some reasons the parent repo might not be searchable:
  #   - repo not routed on the file servers
  #   - repo's user is a spammer
  #   - disabled by an admin
  #   - no associated issues
  #
  #   Note: some of the repository.repo_is_searchable? checks were not
  #   cargo culted into this check on issue's parent repo because GraphQL
  #   ISSUE type queries loading related models async are running into deadlock
  #   due to circular loading patterns. GraphQL folks said to punt like so for now.
  #
  # Return `true` if we should add the issue to the search index; return
  # `false` if we should not.
  #
  def parent_repo_is_searchable?
    return false unless repository&.active?

    repository = T.must(self.repository)

    # If the parent repo has no issues
    return false if !repository.has_issues?

    # When the parent repo user is spammy
    return false if T.unsafe(repository).spammy?

    # When the parent repo has been disabled for any reason
    return false if repository.disabled?

    # When the parent repo has been disabled for DMCA and similar reasons
    return false if repository.access.disabled?

    # The issue is safe to index
    true
  end

  def is_searchable?
    # Do not index spam content
    return false if user_hidden?
    # The read_attribute here is used for speed to bypass the potentially slow #spammy? method.
    return false if safe_user.read_attribute(:spammy)

    # If we got this far, then add to the search index
    true
  end

  def lock(user, reason = nil)
    return unless lockable_by?(user) && !locked?
    return if T.must(repository).locked_on_migration? || (!T.must(repository).has_issues? && !self.pull_request?)
    return if reason && !Issue.valid_lock_reason?(reason.downcase)

    GitHub.dogstats.increment("issue", tags: ["action:lock"])

    if !GitHub.context[:referrer].nil?
      if GitHub.context[:referrer].include?("stafftools") && GitHub.guard_audit_log_staff_actor?
        user = User.staff_user
        reason = nil
      end
    end

    transaction do
      event = events.create!(event: "locked", actor: user, lock_reason: reason.try(:downcase))
      update_attribute(:locked_at, event.created_at)
    end

    notify_socket_subscribers
    self
  end

  def unlock(user)
    return unless lockable_by?(user) && locked?

    # an issue that was converted to a discussion is locked during conversion and cannot be unlocked
    return if repository&.discussions_active? && self.discussion.present?

    GitHub.dogstats.increment("issue", tags: ["action:unlock"])

    if !GitHub.context[:referrer].nil?
      user = User.staff_user if GitHub.context[:referrer].include?("stafftools") && GitHub.guard_audit_log_staff_actor?
    end

    transaction do
      events.create!(event: "unlocked", actor: user)
      update_attribute(:locked_at, nil)
    end

    notify_socket_subscribers
    self
  end

  def locked_for?(user)
    async_locked_for?(user).sync
  end

  def async_locked?
    return Promise.resolve(true) if locked_at?
    async_repository.then do |repository|
      T.must(repository).async_archived?
    end
  end

  def locked?
    async_locked?.sync
  end

  def async_reactions_locked_for?(actor)
    async_locked_for?(actor)
  end

  def async_locked_for?(viewer)
    return Promise.resolve(false) if importing?

    async_repository.then do |repository|
      next true if T.must(repository).archived?

      async_locked?.then do |locked|
        next false unless locked
        next true unless viewer

        T.must(repository).async_writable_by?(viewer).then do |writable|
          !writable
        end
      end
    end
  end

  def async_lockable_by?(viewer)
    async_repository.then do |_repository|
      lockable_by?(viewer)
    end
  end

  alias_method :async_unlockable_by?, :async_lockable_by?

  def locked_reason
    return "This repository has been archived." if T.must(repository).archived?
    return "This repository is being migrated." if T.must(repository).locked_on_migration?
    "This conversation has been locked and limited to collaborators."
  end

  batch_method(:is_read_by_viewer) do |issues, viewer|
    read_issues = Issue.read_for(viewer, issues)

    result = {}
    issues.each do |issue|
      result[issue] = read_issues.include?(issue.id)
    end

    result
  end

  # Loads the issue_type if it is enabled for the org
  batch_method(:issue_type) do |issues|
    issue_type_ids = issues.map(&:issue_type_id).uniq
    issue_types = IssueType.where(id: issue_type_ids).index_by(&:id)

    issues.index_with do |issue|
      next nil unless issue.issue_type_id?

      issue_type = issue_types[issue.issue_type_id]
      issue_type&.enabled? ? issue_type : nil
    end
  end

  # Public: Filters issues to ones that have been read by the User.
  #
  # user     - The User.
  # subjects - Collection of Issues instances to lookup read
  #            status for.
  #
  # Returns a Set of Integer IDs that have been read by the User.
  def self.read_for(user, subjects)
    raise TypeError if !user.kind_of?(User)
    subject_ids = subjects.collect(&:id)

    unread_response = GitHub.newsies.web.by_conversations(user, subjects) do |notification_entry|
      notification_entry.unread?
    end
    Set.new(subject_ids - unread_response.collect(&:id))
  end

  # Returns `true` if this issue has reached the maximum allowable number of
  # comments. Returns `false` if this is not the case.
  def over_comment_limit?
    issue_comments_count && (T.unsafe(self).issue_comments_count >= COMMENT_LIMIT)
  end

  # Determines if the given `user` can comment on this issue. We look at the
  # comment limit and at the locked state of the issue to determine if the user
  # can comment.
  #
  # Returns `true` if the user can comment on the issue; `false` if they cannot
  def can_comment?(user)
    return @can_comment if defined? @can_comment
    async_can_comment?(user).sync
  end

  def async_can_comment?(user)
    return Promise.resolve(false) if !user.is_a?(User) || over_comment_limit?
    async_locked?.then do |locked|
      next true unless locked
      async_repository.then do |repo|
        T.must(repo).async_pushable_by?(user)
      end
    end
  end

  def to_param
    number.to_s
  end

  # Absolute permalink URL for this issue.
  #
  # include_host - Turn off the `GitHub.url` host in the url. (default true)
  #                issue_comment.permalink(include_host: false) => `/github/github/issue/1`
  #
  def permalink(include_host: true)
    type = pull_request? ? "pull" : "issues"
    "#{T.must(repository).permalink(include_host: include_host)}/#{type}/#{number}"
  end
  alias url permalink

  # A URL for this issue constructed with database IDs rather than mutable
  # strings.
  #
  # For example, instead of https://github.com/github/github/issues/1, this
  # returns https://github.com/123/456/issues/1.
  #
  # Since we have redirects in place to rewrite these to the more usual
  # name-based URLs, this is sometimes useful for internal applications that
  # need a URL that is stable in the face of org or repo renames.
  #
  # include_host - Whether or not to prefix the URL path with the `GitHub.url` host.
  #
  # Returns the URL as a String.
  def id_based_url(include_host: true)
    type = pull_request? ? "pull" : "issues"
    "#{T.must(repository).id_based_url(include_host: include_host)}/#{type}/#{number}"
  end

  def path_uri
    return @path_uri if defined?(@path_uri)
    @path_uri = async_path_uri.sync
  end

  def async_path_uri
    return @async_path_uri if defined?(@async_path_uri)
    @async_path_uri = fetch_path_uri
  end

  def async_path_body_uri
    return @async_path_body_uri if defined?(@async_path_body_uri)
    @async_path_body_uri = fetch_path_uri(anchor: "issue-#{id}")
  end

  def async_target_for_conditional_access
    async_repository.then { |x| T.must(x).async_target_for_conditional_access }
  end

  def og_image_url
    open_graph = OpenGraph.new(self,
      cache_key_parts: [
        updated_at,
        T.must(repository).name,
        T.must(repository).owner_id,
      ]
    )
    open_graph.og_image_url
  end

  # Unique identifier for this issue used in email messages.
  def message_id
    "<#{T.must(repository).name_with_display_owner}/issues/#{number}@#{GitHub.urls.host_name}>"
  end

  def self.find_numbers(numbers)
    where(number: numbers).to_a
  end

  # Public: can the user edit this issue?
  #
  # Returns Boolean
  def editable_by?(user)
    return false unless user
    return true if self.user == user && !locked_for?(user)
    T.must(repository).pushable_by?(user)
  end

  def async_editable_by?(viewer)
    return Promise.resolve(false) unless viewer

    async_user.then do |user|
      next false unless user

      editable_by?(viewer)
    end
  end

  def async_viewer_can_delete?(viewer)
    async_deleteable_by?(viewer)
  end

  def async_viewer_can_update?(viewer)
    async_viewer_cannot_update_reasons(viewer, fast_return: true).then(&:empty?)
  end

  # fast_return is an optional parameter that can be used when callers only care
  # about the fact update is possible or not (without all the reasons)
  # this leads to faster execution time because we stop at the first error
  # parameter is optional to keep the default behavior exposed on the public API intact
  def async_viewer_cannot_update_reasons(viewer, fast_return: false)
    return Promise.resolve([:login_required]) unless viewer

    Promise.all([async_repository, async_user]).then do |repository, user|
      errors = []
      user_can_push = repository.pushable_by?(viewer)

      unless user_can_push || user == viewer
        next [:insufficient_access] if fast_return

        errors << :insufficient_access
      end

      if locked_for?(viewer)
        next [:locked] if fast_return
        errors << :locked
      end

      User::InteractionAbility.async_interaction_allowed?(
        user: viewer,
        repository: repository,
        user_can_push: user_can_push
      ).then do |interaction_allowed|
        if !interaction_allowed
          next [:insufficient_access] if fast_return
          errors << :insufficient_access
        end

        context = { repo: repository }

        if !Issues::ContentAuthorizer.new(viewer, :edit, context).errors.map(&:symbolic_error_code).empty?
          next [:insufficient_access] if fast_return

          errors << :insufficient_access
        end

        if repository.discussions_active?
          # Only attempt to lead a discussion if the repo allows discussions, but do so asynchronously.
          async_discussion.then do |discussion|
            if discussion
              next [:locked] if fast_return

              errors << :locked
            end

            # make sure :insufficient_access is last
            errors.sort_by { |e| e == :insufficient_access ? 1 : 0 }
          end
        else
          # make sure :insufficient_access is last
          errors.sort_by { |e| e == :insufficient_access ? 1 : 0 }
        end
      end
    end
  end

  def comments_and_reference_events
    (comments.to_a + events.reference_types.to_a).
      sort_by { |record| T.must(record.created_at) }
  end

  # Makes this class compatible with IssueComments for rendering the body.
  # See GitHub::UserContent#body_pipeline for more info.
  def formatter
    :markdown
  end

  def created_via_email
    false
  end

  # Internal.
  def max_textile_id
    GitHub.max_textile_issue_id
  end

  # Public: Returns an array of User IDs that are mentioned either in this
  # Issue or any of it's comments. If no users are mentioned then the returned
  # Array is empty.
  #
  # Returns an Array of User IDs.
  def mentioned_user_ids
    IssueEvent.mentioned_users(self).map(&:actor_id)
  end
  alias :referenced_user_ids :mentioned_user_ids

  # Returns the list of mentioned Teams in this issue or its comments. We are
  # using the CrossReference table to lookup this information.
  #
  # Returns an Array of Team IDs
  def referenced_team_ids
    CrossReference.from(self).referencing("Team").map(&:target_id)
  end

  def created_by_dependabot?
    return false unless user = self.user
    return false unless user.bot?

    T.unsafe(user).integration&.dependabot_github_app?
  end

  ############################################################################
  ## Search

  # Public: Synchronize this issue with its representation in the search
  # index. If the issue is newly created or modified in some fashion, then it
  # will be updated in the search index. If the issue has been destroyed, then
  # it will be removed from the search index. This method handles both cases.
  #
  def synchronize_search_index
    if pull_request?
      pull_request&.synchronize_search_index
    else
      if self.destroyed? || !self.is_searchable?
        RemoveFromSearchIndexJob.perform_later("issue", self.id, self.repository_id)
      else
        Search.add_to_search_index("issue", self.id)
      end
    end
    self
  end

  def milestone_or_state_changed?
    saved_change_to_milestone_id? || saved_change_to_state?
  end

  def title_or_state_changed?
    saved_change_to_title? || saved_change_to_state?
  end

  def update_milestone!(working_milestone)
    open_count = working_milestone.issues.open_issues.count
    closed_count = working_milestone.issues.closed_issues.count

    working_milestone.open_issue_count = open_count
    working_milestone.closed_issue_count = closed_count
    working_milestone.save! if working_milestone.changed?
  end

  def update_milestone_counts!
    # update current milestone
    update_milestone!(self.milestone) if self.milestone

    # update previous milestone
    if old_milestone = self.milestone_id_before_last_save
      working_milestone = T.unsafe(repository&.milestones)&.find_by_id(old_milestone)
      update_milestone!(working_milestone) if working_milestone
    end
  end

  def ensure_valid_milestone
    if milestone && !T.must(repository).milestones.include?(milestone)
      errors.add :milestone, "must be valid"
    end
  end

  def ensure_creator_is_not_blocked
    if !transfer && user && repository && repository&.owner_blocking?(user)
      errors.add :user, "is blocked"
    end
  end

  def ensure_assignee_is_a_collaborator
    return if assignee && assignee&.ghost?

    if assignee && !assignable_to?(assignee)
      errors.add :assignee, "must be a collaborator"
    end
  end

  def ensure_user_can_create_pr
    if T.must(pull_request).user_unable_to_create_pr?
      errors.add(:base, "must be a collaborator")
    end
  end

  # Internal: record a "renamed" event if the issue's title has been changed.
  def create_renamed_event
    events.create(event: "renamed", title_is: title, title_was: title_before_last_save, actor: modifying_user) if title_before_last_save
  end

  def sorted_labels
    Label.smart_sort(labels)
  end

  # Public: create a "deployed" event if the pull request was deployed.
  def create_deployed_event(deployment)
    events.create({
      event: "deployed",
      actor: deployment.creator,
      performed_by_integration_id: deployment.performed_by_integration_id,
      deployment_id: deployment.id,
    })
  end

  # Public: Create a "deployment_environment_changed" event if the deployment
  #         environment was updated.
  def create_deployment_environment_changed_event(deployment_status)
    events.create({
      event: "deployment_environment_changed",
      actor: deployment_status.creator,
      performed_by_integration_id: deployment_status.performed_by_integration_id,
      deployment_status_id: deployment_status.id,
    })
  end

  # Internal: subscribe the author of this Issue.  Fires after_create
  def subscribe_author
    subscribe(user, :author)
  end

  def author_subscribe_reason
    :author
  end

  # Internal: Ensure this issue counts towards the user's contributions.
  def clear_contributions_cache(context: "unknown")
    Contribution.clear_caches_for_user(user, context: context) if user
  end

  def show_first_contribution_prompt?(viewer)
    (T.must(repository).owner == viewer) && first_contribution_prompt_active?
  end

  # The key is based on the repository owner's id because we want each user to only see this prompt once
  def first_contribution_prompt_key
    "user.show_first_contribution_prompt.#{T.must(repository).owner_id}"
  end

  # The value is based on the issue and repository ids so that we know which issue to display the prompt on
  def first_contribution_prompt_value
    "#{self.id}.#{repository_id}"
  end

  def set_first_contribution_flag
    return if GitHub.enterprise?
    return unless CommunityProfile.eligible_repository?(repository)
    return if first_contribution_prompt_active? || seen_first_contribution_prompt?
    collaborator_ids = T.must(repository).all_member_ids
    return if collaborator_ids.include?(user_id)
    all_prs = Issue.for_repository(repository_id).with_pull_requests
    collaborator_prs = all_prs.where(user_id: collaborator_ids)
    return unless (all_prs.count - collaborator_prs.count) == 1
    GitHub.kv.set(first_contribution_prompt_key, first_contribution_prompt_value) # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  def first_contribution_prompt_active?
    # rubocop:todo GitHub/DoNotUseGlobalKv
    GitHub.kv.get(first_contribution_prompt_key).value { nil } == first_contribution_prompt_value
    # rubocop:enable GitHub/DoNotUseGlobalKv
  end

  def seen_first_contribution_prompt?
    GitHub.kv.get(first_contribution_prompt_key).value { nil }.present? # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  def dismiss_first_contribution_prompt
    GitHub.kv.set(first_contribution_prompt_key, "false") # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  def self.sql_list(query)
    connection.select_all(query).to_a.map do |row|
      row.values[0].to_i
    end
  end
  delegate :sql_list, to: "self.class"

  def self.sql
    connection
  end
  delegate :sql, to: "self.class"

  def set_contributed_at
    T.unsafe(self).contributed_at ||= Time.zone.now
  end

  def trigger_milestone_event
    events.create(
      event: "milestoned",
      actor: modifying_user,
      performed_via_integration: modifying_integration,
      milestone_id: T.must(milestone).id,
      milestone_title: T.must(milestone).title,
    )
  end

  def trigger_demilestone_event(old_milestone, skip_hydro_event_instrumentation: false)
    return if old_milestone.blank?

    events.create(
      event: "demilestoned",
      actor: modifying_user,
      performed_via_integration: modifying_integration,
      milestone_id: old_milestone.id,
      milestone_title: old_milestone.title,
      skip_hydro_event_instrumentation: skip_hydro_event_instrumentation
    )
  end

  def trigger_milestone_change_events
    @milestone_changed = true
    old_milestone = Milestone.find_by(id: self.milestone_id_before_last_save)

    if old_milestone.present?
      trigger_demilestone_event(old_milestone, skip_hydro_event_instrumentation: milestone.present?)
      old_milestone.deprioritize_dependent(self)
    end
    trigger_milestone_event if milestone
  end

  # Project events
  def trigger_add_to_project_event(project:, column:, card_id:)
    return if column.blank?

    events.create! \
      event: "added_to_project",
      subject: project,
      column_name: column.name,
      actor: modifying_user,
      card_id: card_id,
      performed_by_project_workflow_action_id: project.current_workflow_action_id
  end

  def trigger_remove_from_project_event(project:, column:, card_id:)
    return if project.blank?
    return if column.blank?

    events.create! \
      event: "removed_from_project",
      subject: project,
      column_name: column.name,
      actor: modifying_user,
      card_id: card_id
  end

  def trigger_move_within_project_event(card:, project:, column:, previous_column_name:)
    return unless previous_column_name.present?

    events.create \
      event: "moved_columns_in_project",
      subject: project,
      column_name: column.name,
      previous_column_name: previous_column_name,
      actor: modifying_user,
      card_id: card.id,
      performed_by_project_workflow_action_id: project.current_workflow_action_id
  end

  # Internal: create corresponding IssueEvents when a label is added to this Issue
  def trigger_label_event(label)
    last_event = events.last
    is_duplicate = last_event.try(:event) == "labeled" && last_event&.label_name == label.name

    unless is_duplicate
      events.create \
        event: "labeled",
        actor: modifying_user,
        performed_via_integration: modifying_integration,
        label: label
    end
  end

  def trigger_unlabel_event(label)
    events.create \
      event: "unlabeled",
      actor: modifying_user,
      performed_via_integration: modifying_integration,
      label: label
  end

  def trigger_user_blocked_event(ignored_user)
    block_duration_days = ignored_user.duration || 0
    events.create(
      event: "user_blocked",
      actor: ignored_user.ignored_by,
      subject: ignored_user.ignored,
      block_duration_days: block_duration_days,
    )
  end

  def create_initial_events
    labels.each do |label|
      trigger_label_event(label)
    end

    # Dependent on the update state of labels
    update_repo_community_profile(changed_labels: labels)
  end

  # Public: Triggers the job to deliver notifications of this Comment after
  # creation.  See Summarizable.
  #
  # Returns nil.
  def deliver_notifications
    GitHub.newsies.trigger(pull_request? ? pull_request : self, event_time: created_at)
  end

  # see NotificationsContent
  def deliver_notifications?
    !importing?
  end

  # Public: Gets the NotificationSummary for this Comment's thread.
  # See Summarizable.
  #
  # Returns Newsies::Response instance.
  def get_notification_summary
    list = Newsies::List.new("Repository", repository_id)
    GitHub.newsies.web.find_rollup_summary_by_thread(list, self)
  end

  def destroy_notification_summary
    # if we don't have the repository anymore, fake it.
    # this eventually needs to be fixed up to pass the ID directly.
    repo = repository || Repository.new.tap { |r| r.id = repository_id }
    GitHub.newsies.async_delete_all_for_thread(repo, self)
  end

  # Summarizable#update_notification_rollup
  def update_notification_rollup(summary)
    changed = summarizable_changed?(:body, :title, :pull_request_id) ? :changed : :unchanged
    GitHub.dogstats.increment("newsies.rollup", tags: ["changed:#{changed}"])

    summary.summarize_issues(self)
  end

  # Ignores duplicate record creation for the duration of the block. We use
  # unique indexes to prevent records in various places.
  def ignore_duplicate_records
    yield
  rescue ActiveRecord::RecordNotUnique
    # XXX ignore duplicate entries. We can probably also do an
    # INSERT IGNORE query above instead.
  end

  def instrument_creation_event(body_template_name:)
    # We generate a single guid for both Events V1 and V2 events
    # so that we can later do a parity check on the webhook payloads generated
    # for each kind of event
    event_guid = Events::Tier1EventPublisher.new_guid(Time.now)
    event_flags = Events::Tier1EventPublisher.calculate_event_flags(
      event_type: :issues,
      event_action: :opened,
      target_repository_id: T.must(repository).id,
      target_organization_id: T.must(repository).organization_id
    )
    Events::IssuesPublisher.opened(
      actor: safe_user,
      repository: T.must(repository),
      issue: self,
      guid: event_guid,
      event_flags: event_flags
    )

    instrument :create, task_list: task_list?, event_guid: event_guid, flags: event_flags.instrumentation_flags

    body_template = body_template_name ? T.must(repository).preferred_issue_templates[body_template_name] : template

    GlobalInstrumenter.instrument "issue.create", {
      actor: safe_user,
      repository: repository,
      repository_owner: T.must(repository).owner,
      issue: self,
      issue_creator: safe_user,
      title: title,
      body: body,
      template: body_template,
      pull_request: pull_request,
      issue_type: issue_type,
    }
  end

  def instrument_transform_to_pull
    instrument :transform_to_pull, issue: self

    GlobalInstrumenter.instrument "issue.transform_to_pull", {
      repository: repository,
      issue: self,
      pull_request: pull_request,
    }
  end

  def instrument_destroy
    instrument(:destroy, {
      title: title,
      body: body,
      org: self.repository&.owner&.organization? ? self.repository&.owner : nil,
      org_id: self.repository&.owner&.organization? ? self.repository&.owner&.id : nil,
      })
  end

  # Private: Ensure that title or body were set before they were changed.
  #
  # Returns Boolean
  def title_or_body_changed?
    (self.title_changed? || previous_changes.include?(:title)) ||
    ((self.body_changed? || body_previously_changed?) &&
      # See https://github.com/github/issues/issues/5663#issuecomment-1513226511
      # At some point in time, there was a change in how an empty body is stored
      # Previously stored as an empty string, and now stored as a NULL value in the DB
      # We want to prevent such updates from triggering any change/edit events
      # so we check if both the previous and the current body are nil or empty
      body = self.body
     !((self.body_previously_was.nil? || self.body_previously_was.empty?) &&
       (body.nil? || body.empty?)))
  end

  def instrument_update_event(issue_edit_id: nil, old_title: nil, current_title: nil)
    if issue_edit_id.nil?
      old_body, current_body = body_previously_was, body
    else
      previous_edit = IssueEdit.find(issue_edit_id)
      old_body = previous_edit.compressed_diff || ""
      current_body = body || ""
    end

    if old_title.nil? && current_title.nil?
      old_title, current_title = previous_changes[:title]
    end

    payload = { issue_id: id, actor: modifying_user }
    payload[:pull_request_id] = T.must(pull_request).id if pull_request?
    payload.merge!(old_title: old_title, title: current_title) if old_title
    payload.merge!(old_body: old_body, body: current_body) if old_body

    instrument :update, payload
  end

  def issue_transfer?
    defined?(transfer) && transfer == true
  end

  def should_instrument_hydro_update_event?
    !issue_transfer? && !skip_hydro_update_event_instrumentation && !orchestrate_hydro_update_event_instrumentation
  end

  def instrument_hydro_update_event(previous_title: nil, previous_body: nil, actor: nil)
    previous_title, current_title = if !previous_title.nil?
      [previous_title, title]
    elsif previous_changes[:title].present?
      previous_changes[:title]
    else
      [title, title]
    end

    previous_body, current_body = if !previous_body.nil?
      [previous_body, body]
    elsif body_previously_changed?
      [body_previously_was, body]
    else
      [body, body]
    end

    return if previous_title == current_title && previous_body == current_body

    actor ||= modifying_user

    GlobalInstrumenter.instrument "issue.update", {
      actor: actor,
      repository: repository,
      repository_owner: repository&.owner,
      issue: self,
      issue_updater: actor,
      previous_title: previous_title,
      current_title: current_title,
      previous_body: previous_body,
      current_body: current_body,
    }
  end

  include Instrumentation::Model

  def event_prefix() :issue end

  def event_payload
    org = repository&.organization
    business = repository&.organization&.business

    payload = {
      event_prefix           => self,
      :repo                  => repository,
      safe_user.event_prefix => safe_user,
      :spammy                => modifying_user.spammy?,
      :allowed               => user_allowed?,
      :org                   => org,
      :business              => business,
    }

    if pull_request?
      payload[:pull_request] = pull_request
      payload[:primary_resource] = T.must(pull_request).attributes
    end

    payload.merge!(event_analytics_payload) if repository
    payload
  end

  def user_allowed?
    repository.permit? modifying_user, :write
  end

  def event_analytics_payload
    repository = T.must(self.repository)

    {
      # core dimensions (private/public and org- or user-owned)
      private: repository.private?,
      owner_id: repository.owner_id,
      owner_type: repository.owner&.type,

      # ancillary dimensions
      issue_id: id,
      created_at: created_at,
      updated_at: updated_at,
      closed_at: closed_at,
      milestone_id: milestone_id,
      assignee_id: assignee_id,
      assignee_ids: assignments.map(&:assignee_id),
      number: number,
      state: state,
      labels: labels.map(&:name),
      issue_comments_count: issue_comments_count,

      # measures
      mentioned_issues: mentioned_issues.size,
      mentioned_users: mentioned_usernames.size,
      mentioned_teams: mentioned_teams.size,
      task_list_items: task_list_summary.item_count || 0,
    }
  end

  def contribution_time
    @contribution_time ||= if contributed_at_timezone_aware?
      T.unsafe(self).contributed_at
    else
      T.must(created_at).localtime
    end
  end

  def contributed_on
    contribution_time.to_date
  end

  def update_issue_comments_count
    update_attribute(:issue_comments_count, comments.not_spammy.count)
  end

  def priority_for_milestone?
    issue_priorities.where(milestone_id: self.milestone_id).exists?
  end

  def prioritize_in_milestone
    return unless milestone = self.milestone
    return unless milestone.prioritizable?
    return if milestone.needs_backfill?(issue: self)
    return if priority_for_milestone?

    milestone.prioritize_issue!(self, position: :bottom)
  end

  def human_name
    if pull_request
      "pull request"
    else
      "issue"
    end
  end

  def owner
    T.must(repository).owner
  end

  # Internal: Enqueues a job if help wanted labels have been added or removed
  #
  # Returns nil
  def update_repo_community_profile(changed_labels: [])
    return unless should_update_repo_communit_profile(changed_labels)
    update_repo_community_profile!
  end

  def should_update_repo_communit_profile(labels)
    changed_names = labels.map { |label| label.name.downcase }
    changed_help_wanted_names = changed_names.select do |name|
      name.start_with?(*HELP_WANTED_LABEL_NAMES)
    end
    !changed_help_wanted_names.empty?
  end

  def update_repo_community_profile!
    CommunityProfile.enqueue_help_wanted_job(repository)
  end

  # Public: Returns this Issue. This helps to avoid `is_a?` calls when you have
  # a variable that can be an issue or PR.
  #
  # Examples
  #
  #   issue_or_pr.to_issue.my_favorite_issue_method
  #
  # Returns an Issue
  def to_issue
    self
  end

  def unique_label_ids
    @unique_label_ids ||= Set.new(label_ids)
  end

  def preload_viewer_attributes(viewer)
    viewer_data = Promise.all(
     [
       async_viewer_can_update?(viewer),
       async_viewer_cannot_update_reasons(viewer),
       async_viewer_can_report?(viewer),
       async_viewer_can_report_to_maintainer?(viewer),
       async_viewer_can_block_from_org?(viewer),
       async_viewer_can_unblock_from_org?(viewer),
       async_viewer_relationship(viewer),
       nil
     ]
    ).sync

    @viewer_can_update,
    @viewer_cannot_update_reasons,
    @viewer_can_report,
    @viewer_can_report_to_maintainer,
    @viewer_can_block_from_org,
    @viewer_can_unblock_from_org,
    @viewer_relationship,
    @viewer_can_create_issue = viewer_data
  end

  def viewer_can_create_issue?(viewer = nil)
    @viewer_can_create_issue ||= true
  end

  def viewer_can_update?(user = nil)
    return @viewer_can_update if defined? @viewer_can_update
    @viewer_can_update = user.nil? ? false : async_viewer_can_update?(user).sync
  end

  def viewer_can_report(user = nil)
    if user.nil?
      if defined? @viewer_can_report
        return @viewer_can_report
      else
        return false
      end
    end
    async_viewer_can_report?(user).sync
  end

  def viewer_can_report_to_maintainer(user = nil)
    if user.nil?
      if defined? @viewer_can_report_to_maintainer
        return @viewer_can_report_to_maintainer
      else
        return false
      end
    end
    async_viewer_can_report_to_maintainer?(user).sync
  end

  def viewer_can_block_from_org?(user = nil)
    if user.nil?
      if defined? @viewer_can_block_from_org
        return @viewer_can_block_from_org
      else
        return false
      end
    end
    async_viewer_can_block_from_org?(user).sync
  end

  def viewer_can_unblock_from_org?(user = nil)
    if user.nil?
      if defined? @viewer_can_unblock_from_org
        return @viewer_can_unblock_from_org
      else
        return false
      end
    end
    async_viewer_can_unblock_from_org?(user).sync
  end

  def viewer_relationship(user = nil)
    if user.nil?
      if defined? @viewer_relationship
        return @viewer_relationship
      else
        return false
      end
    end
    async_viewer_relationship(user).sync
  end

  def update_checklist_items(parent_issue, matching_anchors)
    updated_checklist = parent_issue.body
    matching_anchors.each do |anchor|
      if anchor.state == "open"
        updated_checklist = updated_checklist.gsub("[ ] #{anchor.title}", "[x] #{anchor.title}")
      else
        updated_checklist = updated_checklist.gsub(/\[[xX]\] #{anchor.title}/, "[ ] #{anchor.title}")
      end
    end
    parent_issue.update(body: updated_checklist)
  end

  def nwo_reference(current_repo)
    if repository == current_repo
      "##{number}"
    else
      "#{T.must(repository).nwo}##{number}"
    end
  end

  def name_with_display_owner_reference(current_repo = nil)
    if repository == current_repo
      "##{number}"
    else
      "#{T.must(repository).name_with_display_owner}##{number}"
    end
  end

  def clean_title_and_body
    self.body = strip_spammy_unicode_from(body) if body
    self.title = strip_spammy_unicode_from(title) if title
  end

  # Override Referrer#track_references_in_background? so that references
  # are created in a background job.
  def track_references_in_background?
    GitHub.flipper[:track_issue_and_pr_references_in_background].enabled?(repository)
  end

  # Override UserContent#attach_matching_assets_in_background? so that assets
  # are attached in a background job.
  def attach_matching_assets_in_background?
    true
  end

  # Override UserContent#attach_matching_assets? As we're handling this in CreateIssueOrchestration
  # and UpdateIssueOrchestration we don't need to invoke it through after_save.
  def attach_matching_assets?
    false
  end

  # Override NotificationsContent#defer_loading_mentions? so that mentions are evaluated in a background job.
  def defer_loading_mentions?
    true
  end

  def update_body(...)
    instrument_tasklist_block_add_on_update { super }
  end

  def without_update_issue_orchestration
    previous_skip_value = self.skip_update_issue_orchestration
    self.skip_update_issue_orchestration = true
    yield
    self.skip_update_issue_orchestration = previous_skip_value
  end

  def notify_parent_updated
    @parent_issue_changed = true
    notify_socket_subscribers
  end

  def notify_sub_issues_updated
    @sub_issues_changed = true
    notify_socket_subscribers
  end

  def notify_sub_issues_summary_updated
    @sub_issues_summary_changed = true
    notify_socket_subscribers
  end

  def notify_transfer_state_updated
    @transfer_state_changed = true
    notify_socket_subscribers
  end

  def enable_assignees_changed
    @assignees_changed = true
  end

  private

  def validate_can_interact(actor)
    # For an issues transfer it is not the user of the issue that needs to be checked,
    # but the user that triggers the transfer.
    actor = modifying_user if transfer
    super(actor)
  end

  def strip_spammy_unicode_from(input)
    input.gsub(/\p{M}{4,}/, "")
  end

  def set_number
    if number? && valid_number?
      Sequence.set(repository, number) if T.must(number) > Sequence.get(repository)
    else
      self.number = Sequence.next(repository)
    end
    self.class.where(id: id).update_all(number: number)
  end

  # Private: extra protection to ensure number was set to a nonzero value.
  #
  # Returns nothing or raises ActiveRecord::Rollback if number is 0.
  def ensure_valid_number
    if T.must(number).zero?
      errors.add(:number, "is invalid")
      raise ActiveRecord::Rollback
    end
  end

  def valid_number?
    non_zero_number? && number_is_available?
  end

  def non_zero_number?
    number.to_i > 0
  end

  def number_is_available?
    !self.class.exists?(["number = ? and id != ? and repository_id = ?", number, id, repository_id])
  end

  # Skip incrementing the tries count for the content creation rate limit if
  # the issue belongs to a pull request
  #
  # Overrides the method included from GitHub::RateLimitedCreation
  def check_creation_rate_limit
    if pull_request? && GitHub.flipper[:exempt_backing_issue_from_content_creation_limit].enabled?(repository&.organization)
      super(skip_increment: true)
    else
      super
    end
  end

  def creation_rate_limit_configuration
    GitHub.issue_creation_rate_limit_configuration
  end

  def apply_dynamic_rate_limit_configuration?
    creation_rate_limit_configuration.present?
  end

  def contributed_at_timezone_aware?
    contributed_at = T.unsafe(self).contributed_at
    contributed_at && contributed_at > Contribution::Calendar::TIMEZONE_AWARE_CUTOVER
  end

  def ensure_authorized_to_create_content
    operation = new_record? ? :create : :update
    authorization = Issues::ContentAuthorizer.new(modifying_user, operation, repo: repository)

    if authorization.failed?
      errors.add(:base, authorization.error_messages)
    end
  end

  def ensure_not_converting_to_discussion
    return unless with_database_error_fallback(fallback: true) { repository&.discussions_active? }

    discussion = self.discussion
    if discussion && discussion.converting?
      errors.add(:base, "Cannot be modified since it is being converted to a discussion.")
    end
  end

  # Used to report invalid pull_request_id when attaching an issue to a pull request.
  class PullRequestIdInvalid < StandardError
  end

  # Used to report invalid pull_request_id when attaching an issue to a pull request.
  class LostConversationReferenceError < StandardError
  end

  # Used to report invalid assignee when validating assigned to input.
  class AssigneeInvalid < StandardError
    attr_reader :assignee
    def initialize(assignee, msg)
      super(msg)
      @assignee = assignee
    end
  end

  def fetch_path_uri(anchor: nil)
    async_repository.then do
      type = pull_request_id.present? ? "pull" : "issues"
      URI_TEMPLATE.expand(
        nwo:    T.must(repository).name_with_display_owner,
        type:   type,
        number: number,
        anchor: anchor,
      )
    end
  end

  # Internal: Validation preventing against `pull_request_id` being set to 0.
  #
  # Returns nothing. Adds an error to :pull_request_id unless valid.
  def pull_request_id_is_not_zero
    if pull_request_id&.zero?
      boom = PullRequestIdInvalid.new("pull_request_id set to 0")
      boom.set_backtrace(caller)
      Failbot.report(boom, repo_id: repository&.id)

      errors.add(:pull_request_id, "is invalid")
    end
  end

  def label_in_the_same_repository(label)
    raise InvalidLabelAddedError::new("Label in different repository") if label.repository_id != repository_id
  end

  def update_labels_changed_status(label)
    @labels_changed = true
  end

  def update_assignees_changed_status(assignee)
    @assignees_changed = true
  end

  def reset_meta_data_changed_flags
    @labels_changed = false if @labels_changed
    @assignees_changed = false if @assignees_changed
    @milestone_changed = false if @milestone_changed
  end

  def comments?
    return @any_comments if defined?(@any_comments)
    @any_comments = comments.any?
  end

  def events?
    return @any_events if defined?(@any_events)
    @any_events = events.any?
  end

  def timeline_events?
    return @any_timeline_events if defined?(@any_timeline_events)
    @any_timeline_events = timeline_events.any?
  end

  def connects?
    return @any_connects if defined?(@any_connects)
    @any_connects = events.connects.any?
  end

  def track_exec_time(metric, tags = [])
    timer = Timer.start
    result = yield
    timer.stop

    GitHub.dogstats.distribution(metric, timer.elapsed_ms, tags: tags.uniq)
    result
  end

  def destroy_replaced_labels(old_labels, new_labels)
    (old_labels - new_labels).each do |label|
      trigger_unlabel_event label
    end

    labels.delete(*old_labels - new_labels)
  end

  def create_replaced_labels(old_labels, new_labels)
    (new_labels - old_labels).each do |label|
      trigger_label_event label
      begin
        labels << label
      rescue ActiveRecord::RecordNotUnique
      end
    end
  end

  # Private: determine if an issue is being converted to a discussion or not
  #
  # Adds an error to the base object and aborts otherwise returns nil
  # Tests in DiscussionsDependencyTest
  def abort_if_converting_to_discussion
    return unless repository&.owner&.feature_enabled?(:block_deletion_on_conversion)

    discussion = self.discussion
    # if a conversion is in progress (eg: a discussion has been created for this issue
    # and the converted at hasn't been set) we don't want to allow the issue to be deleted
    return unless discussion && discussion.converting?

    errors.add(:base, "This issue is being converted to a discussion.")
    throw :abort
  end

  def initialize_create_issue_orchestration
    return if skip_create_issue_orchestration

    @create_issue_orchestration = IssueOrchestration.create_issue!(
      actor: modifying_user,
      issue: self
    )

    @create_issue_orchestration.log_info("Create CreateIssueOrchestration")
  end

  def execute_create_issue_orchestration(synchronous: false)
    return if @create_issue_orchestration.nil?
    return if skip_create_issue_orchestration

    o = @create_issue_orchestration
    @create_issue_orchestration = nil

    o.log_info("Execute CreateIssueOrchestration")

    o.execute synchronous: synchronous
  end

  def initialize_update_issue_orchestration
    return if skip_update_issue_orchestration
    # if wrapped in a transaction block multiple calls to this method can be made but only a
    # single orchestration should be created.
    return unless @update_issue_orchestration.nil?

    @update_issue_orchestration = IssueOrchestration.update_issue!(
      actor: modifying_user,
      issue: self
    )

    @update_issue_orchestration.log_info("Create UpdateIssueOrchestration")
  end

  def execute_update_issue_orchestration
    return if skip_update_issue_orchestration
    return if @update_issue_orchestration.nil?

    o = @update_issue_orchestration
    @update_issue_orchestration = nil

    o.log_info("Execute UpdateIssueOrchestration")

    o.execute
  end

  def saved_reply_copy_target
    self.repository
  end
end
