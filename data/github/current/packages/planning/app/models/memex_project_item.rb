# typed: true
# frozen_string_literal: true

class MemexProjectItem < ApplicationRecord::Domain::Memexes

  include GitHub::Validations
  include GitHub::Prioritizable
  include GitHub::Prioritizable::SBT::Item
  include Spam::Spammable
  include MemexProjectItem::ArchivalDependency
  include MemexProjectItem::ColumnDependency
  include MemexProjectItem::CsvColumnDependency
  include MemexProjectItem::IssuesGraphDependency
  include MemexProjectItem::StateReasonDependency
  include ContextualActor
  include ActiveModel::Dirty
  include Instrumentation::Model
  extend Scientist
  include ActiveSupport::NumberHelper
  include GitHub::Tracing

  class ItemPrefillError < StandardError
    attr_reader :memex_project_column

    def initialize(message, memex_project_column)
      super(message)
      @memex_project_column = memex_project_column
    end
  end

  class ProjectLimitReachedError < StandardError

    sig { returns(T::Array[MemexProject]) }
    attr_reader :memex_projects_with_errors

    def initialize(message, memex_projects_with_errors)
      super(message)
      @memex_projects_with_errors = memex_projects_with_errors
    end
  end

  belongs_to :memex_project, inverse_of: :memex_project_items, touch: true
  belongs_to :creator, class_name: "User"
  belongs_to :content, polymorphic: true
  belongs_to :repository
  belongs_to :issue
  has_one :issue_type, through: :issue
  has_one :draft_issue, autosave: true, dependent: :destroy
  destroy_dependents_in_background :memex_project_column_values

  attr_accessor :source_project_card_id

  # A transient flag to indicate that this item is part of a bulk operation. The expectation is that, when true, we
  # will suppress instrumentation related to our denormalization pipeline, but it may end up being use for other
  # purposes as well.
  sig { returns(T.nilable(T::Boolean)) }
  attr_accessor :bulk_operation

  # Transient attribute used to disable hydro event instrumentation.
  sig { returns(T.nilable(T::Boolean)) }
  attr_accessor :disable_hydro_event_instrumentation

  # Identifies this item in a paginated context.
  #
  # Since this attribute is transient, it should only be used when you are sure that it has been set appropriately.
  sig { returns(T.nilable(String)) }
  attr_accessor :cursor

  setup_spammable :creator

  prioritizable_by subject: :content, context: :memex_project

  scope :is_draft, -> { where(content_type: DRAFT_ISSUE_TYPE) }

  scope :for_page_limit, -> {
    if GitHub.spamminess_check_enabled?
      not_archived.not_spammy
    else
      not_archived
    end
  }

  VALID_CONTENT_TYPES = [
    ISSUE_TYPE = Issue.name,
    PULL_REQUEST_TYPE = PullRequest.name,
    DRAFT_ISSUE_TYPE = DraftIssue.name,
  ].freeze

  GRAPH_DRAFT_ISSUE_STATE = [
    GRAPH_DRAFT_OPEN = TasklistBlocks::DraftIssueState::OPEN,
    GRAPH_DRAFT_CLOSED = TasklistBlocks::DraftIssueState::CLOSED,
  ].freeze

  before_validation :set_item_repository_id, if: :repository_required?
  before_validation :set_denormalize_issue_fields, if: :issue_required?

  validates :creator, presence: true, on: :create
  validates :memex_project, presence: true, on: :create
  validates :content_type, presence: true, inclusion: { in: VALID_CONTENT_TYPES }
  # Projects cannot contain more than one item for any issue/PR. However, when we are copying items from an existing
  # project, we can skip this validation because it is assumed that the source project is valid and will be valid after
  # copying as well. This saves N DB queries when copying N memex project items to a new project.
  # To skip checking content uniqueness, wrap the creation code inside a `MemexProject::Copier.with_copying` block.
  # Callers SHOULD ensure that the content is unique before calling `with_copying`.
  # Given that classic projects have a similar uniqueness validation to them, we can skip this as part of the migration as well.
  validates_uniqueness_of :content_id, scope: [:memex_project_id, :content_type], message: "already exists in this project", unless: -> { MemexProject::Copier.copying? || MemexProject::Migrator.migrating? }
  validates :content, presence: true, on: :create, unless: -> { MemexProject::Migrator.migrating? }
  validates :repository, presence: true, if: :repository_required?
  validates :issue, presence: true, if: :issue_required?, unless: -> { MemexProject::Migrator.migrating? }
  validate :creator_has_verified_email, on: :create
  # The number of items in a project cannot exceed the maximum limit for project items. However, when we are copying
  # items from an existing project, we can skip this validation because it is assumed that the source project is valid
  # and will be valid after copying as well. This saves 2*N DB queries when copying N memex project items to a new project,
  # because we don't need to query to check if the item is archived and also don't need to get the total count of items
  # after creating each new item.
  # To skip checking item limits, wrap the creation code inside a `MemexProject::Copier.with_copying` block.
  # Callers SHOULD ensure that the content is unique before calling `with_copying`.
  # We also specifically count out the number of items to add to a project and to the archive when migrating a project
  # so we can stop doing this check when migrating a project
  validate :item_can_be_created, on: :create, unless: -> { MemexProject::Copier.copying? || MemexProject::Migrator.migrating? }
  validates(
    :priority,
    uniqueness: { scope: :memex_project_id, allow_nil: true },
    numericality: {
      less_than_or_equal_to: GitHub::Prioritizable::MAX_PRIORITY_VALUE,
      greater_than_or_equal_to: 0,
      allow_nil: true,
    }
  )

  delegate :memex_denormalized_title_value, :memex_denormalized_milestone_value, :can_have_milestone?, to: :content
  alias_method :denormalized_title_value, :memex_denormalized_title_value
  alias_method :denormalized_milestone_value, :memex_denormalized_milestone_value

  ON_CREATE_INSTRUMENTATION_KEY = "item_create"
  ON_UPDATE_INSTRUMENTATION_KEY = "item_update"
  ON_DESTROY_INSTRUMENTATION_KEY = "item_delete"

  after_commit :instrument_create_event, on: :create
  after_commit :instrument_update_event, on: :update
  after_commit :instrument_delete_event, on: :destroy

  # This uses `prepend: true` to ensure that this runs before any `dependent: destroy` hooks, regardless of where
  # those are defined in this file.
  #
  # See https://api.rubyonrails.org/classes/ActiveRecord/Callbacks.html#module-ActiveRecord::Callbacks-label-Ordering+callbacks.
  before_destroy :generate_deleted_webhook_payload, prepend: true

  after_destroy_commit -> { T.bind(self, MemexProjectItem); queue_deleted_webhook_delivery }
  after_commit :synchronize_content_search_index, on: [:create, :destroy]
  # When migrating projects, instead of syncing project items to hierarchy each item, we only do it once for the whole
  # project if the user is flagged in to :tasklist_block
  after_commit :enqueue_sync_to_hierarchy_job, on: [:create, :update], unless: -> { MemexProject::Migrator.migrating? }
  after_commit :notify_socket_subscribers, if: :should_notify_socket_subscribers?

  # Whenever a project item is created, we mark that as "visiting" the project so that it shows up in the recently
  # visited/updated list. However, when we are copying items from an existing project or migrating, we can skip this update because
  # the project will be newly created and should be visited via the URL anyway to record a project visit.
  # This ends up saving N write queries to the visits table when creating N memex project items.
  # To disable visit record creation, wrap the creation code inside a `MemexProject::Copier.with_copying` block.
  after_create_commit -> { T.bind(self, MemexProjectItem); update_recently_visited }, unless: -> { T.bind(self, MemexProjectItem); MemexProject::Copier.copying? || MemexProject::Migrator.migrating? }

  # Temporary pagination limit until https://github.com/github/memex/issues/720 is implemented
  PER_PAGE_LIMIT = 1200 # TODO: move to MemexProject for has_reached_items_limit?
  EXPANDED_ITEM_LIMIT = 50_000 # Project item limit for Projects Without Limits projects
  ARCHIVED_ITEM_LIMIT = 10_000 # TODO: move to MemexProject for has_reached_archived_items_limit?
  EXPANDED_ARCHIVED_ITEM_LIMIT = EXPANDED_ITEM_LIMIT - PER_PAGE_LIMIT # https://github.com/github/github/pull/267777/files#r1154991128
  ARCHIVE_IN_FOREGROUND_LIMIT = 10
  UNARCHIVE_IN_FOREGROUND_LIMIT = 10
  DELETE_IN_FOREGROUND_LIMIT = 10

  REDACTED_ITEM_TYPE = "RedactedItem"

  def redact!
    now = Time.zone.now
    self.class.new(
      id: id,
      priority: priority,
      content_id: -1,
      content_type: REDACTED_ITEM_TYPE,
      updated_at: now,
      created_at: now,
      archived_at: archived_at
    )
  end

  def target_for_conditional_access
    return memex_project&.target_for_conditional_access if draft_issue?

    content.target_for_conditional_access
  end

  def self.multiple_target_for_conditional_access(items)
    repository_ids = items.map(&:repository_id).compact.uniq
    repos_to_owner_ids = Repository.where(id: repository_ids).pluck(:id, :owner_id).to_h
    owners = User.where(id: repos_to_owner_ids.values.uniq).index_by(&:id)

    results = {}
    items.each do |item|
      if item.draft_issue?
        results[item] = item.target_for_conditional_access
      else
        results[item] = owners[repos_to_owner_ids[item.repository_id]]
      end
    end
    results
  end

  # Builds a hash that will ultimately be converted to JSON to represent this
  # object in the internal memex API.
  #
  # columns - Array<MemexProjectColumn> for the columns whose data we should serialize
  # require_prefilled_associations - Whether or not we should raise an exception if we're about to
  #   serialize an association that has not already been prefilled (meaning we're likely to generate
  #   an N+1).
  # prefilled_associations - MemexProjectItem::PrefilledAssociation object returned from a previous
  #   call to MemexProjectItemPrefiller#prefill.
  #
  # Returns a Hash.
  def to_hash(columns: [], require_prefilled_associations: true, prefilled_associations: nil, redacted_issue_ids: [])
    result = {
      contentId: content_id,
      contentType: content_type,
      contentRepositoryId: repository_id,
      id: id,
      priority: priority,
      virtualPriority: stringified_virtual_priority,
      updatedAt: updated_at&.utc&.iso8601,
      createdAt: created_at&.utc&.iso8601
    }

    if archived?
      result[:archived] = {
        archivedAt: archived_at,
        archivedBy: archiver&.memex_column_hash,
      }
    end

    if issue_created_at?
      result[:issueCreatedAt] = issue_created_at&.utc&.iso8601
    end

    if issue_closed_at?
      result[:issueClosedAt] = issue_closed_at&.utc&.iso8601
    end

    if state?
      result[:state] = state
    end

    if state_reason?
      result[:stateReason] = state_reason
    end

    return result unless columns.present?

    result[:memexProjectColumnValues] = column_values(
      columns: columns,
      require_prefilled_associations: require_prefilled_associations,
      prefilled_associations: prefilled_associations,
      redacted_issue_ids: redacted_issue_ids
    )

    result[:content] = if redacted_item_type?
      { id: content_id }
    elsif prefilled_associations
      ensure_preloaded_column_values! if require_prefilled_associations
      {
        id: content_id,
        url: content_url(prefilled_associations: prefilled_associations),
        globalRelayId: content_is_issue? ? prefilled_associations.global_relay_id(self) : nil,
      }.compact
    else
      content_hash = content.memex_content_hash(fields: [:id, :url])

      # The memex prefiller only includes global_relay_id when the parent_issue column is visible,
      # so do the same thing here.
      content_hash.delete(:globalRelayId) if !columns.find(&:parent_issue?)
      content_hash
    end

    result
  end

  # Returns the underlying unique value used to group like items by column.  This value should have deterministic
  # characteristics that make it suitable for grouping and sorting.
  #
  # column - MemexProjectColumn for the column we're trying to get the value for
  # require_prefilled_associations - Boolean indicating whether or not prefilled associations should be enforced.
  # prefilled_associations - MemexProjectItem::PrefilledAssociation
  # redacted_issue_ids - Array of issue ids that are currently redacted.
  #
  # Returns the underlying data-type-sensitive value for the given column/is non-groupable.  Can return nil which
  # represents no value.  Can also return an array for certain column types, such as assignees and labels.
  #
  # Here are some examples:
  #  - item.group_by_value(assignees_column) => ["user1", "user2"]
  #  - item.group_by_value(date_column) => Date.parse("2020-01-01")
  #  - item.group_by_value(number_column) => 123.456
  #  - item.group_by_value(iteration_column) => "abc01def"
  #  - item.group_by_value(milestone_column) => "Large Project Support"
  #  - item.group_by_value(repository_column) => "github/github"
  #  - item.group_by_value(single_select_column) => "abc01def"
  #  - item.group_by_value(text_column) => "This is a text value"
  def group_by_value(column, require_prefilled_associations: true, prefilled_associations: nil, redacted_issue_ids: [])
    data = column_values(
      columns: [column],
      require_prefilled_associations: require_prefilled_associations,
      prefilled_associations: prefilled_associations,
      redacted_issue_ids: redacted_issue_ids
    )&.first

    dig_by = COLUMN_VALUE_KEYS[column.data_type.to_sym]

    # You must declare how to extract the item value from the column value hash.
    raise ArgumentError, "Unsupported groupable column type: #{column.data_type}" unless dig_by

    value = data.dig(*dig_by)

    # The #presence calls are to ensure empty values/arrays are returned as nil to represent the group having no
    # underlying value(s).
    case column.data_type
    when "assignees"
      value&.map { |assignee| assignee[:login] }&.uniq&.sort&.presence
    when "date"
      value&.to_date
    when "number"
      value&.to_f
    when "iteration", "milestone", "repository", "single_select", "issue_type"
      value.presence
    when "text"
      value.to_s
    else
      raise ArgumentError, "Unsupported groupable column type: #{column.data_type}"
    end
  end

  # Returns an instance of MemexProject::Group for this specific item.  The group is based on the title
  # and value derived from this item and a specified column.
  #
  # Examples:
  #   - item.to_group(assignees_column, view) => #<MemexProject::Group view="..." title="user1, user2", value=["user1", "user2"]>
  #   - item.to_group(single_select_column, view) => #<MemexProject::Group view="..." title="todo", value="abc01def">
  def to_group(column, view, require_prefilled_associations: true, prefilled_associations: nil, redacted_issue_ids: [])
    MemexProject::Group.new(
      view: view,
      column: column,
      title: column_value(
        column,
        require_prefilled_associations: require_prefilled_associations,
        prefilled_associations: prefilled_associations,
        redacted_issue_ids: redacted_issue_ids
      ),
      value: group_by_value(
        column,
        require_prefilled_associations: require_prefilled_associations,
        prefilled_associations: prefilled_associations,
        redacted_issue_ids: redacted_issue_ids
      )
    )
  end

  def platform_type_name
    @platform_type_name || "ProjectV2Item"
  end

  attr_writer :platform_type_name

  def async_viewer_can_update?(viewer)
    async_memex_project.then do |memex_project|
      T.must(memex_project).async_viewer_can_update?(viewer)
    end
  end

  def async_readable_by?(viewer)
    async_memex_project.then do |memex_project|
      T.must(memex_project).async_readable_by?(viewer)
    end
  end

  # When issues are transferred to another repo, we should update the association
  # in the memex_project_item to refer to the new issue association.
  #
  # See IssueTransfer for more information on the transfer process.
  #
  # For non-issue based content, do nothing. Only issues can be transferred.
  #
  # If the issue's org owner is different from the memex's owning org, do nothing.
  # Dependent destroy will destroy the memex_project_item, because we're not sure
  # if the memex should have access to the issue in its new repo home in the case of
  # cross-org memex items.
  def transfer_issue_item(new_issue)
    return unless content_type == ISSUE_TYPE
    return unless new_issue.repository.owner == memex_project&.owner

    replace_content(new_issue, creator)
  end

  # Updates the content for this memex item - the issue/pull request that is passed in
  # to this method. Will also build denormalized column values to reflect the canonical source
  def replace_content(issue_or_pull, actor)
    if update(content: issue_or_pull)
      # Despite calling a "build*" method, which we would normally expect to only construct
      # objects and not make any writes to the database, because build_denormalized_column_value
      # uses set_json_value under the hood (which will write to the database if the item has already
      # been persisted), this usage of build_denormalized_column_values *will* perform database updates.
      build_denormalized_column_values(actor)
    end
  end

  # Helper method to check that the item can be converted
  def can_convert_to_issue?
    draft_issue_type?
  end

  def synchronize_content_search_index
    content.synchronize_search_index if content.respond_to?(:synchronize_search_index)
  end

  def should_notify_socket_subscribers?
    content.present? && !draft_issue? && content.respond_to?(:notify_socket_subscribers)
  end

  def notify_socket_subscribers
    associated_updates = {}
    if content&.repository&.feature_enabled?(:project_event_updates)
      associated_updates = { projects_updated: true }
    end
    content.notify_socket_subscribers(associated_updates:)
  end

  # returns invalid assignee logins
  def build_assignee_params(assignees, builder_params, target_repo)
    valid_assignees = []
    invalid_assignees = []

    return [] if assignees.empty?

    Promise.all(assignees.map do |assignee|
      target_repo.async_readable_by?(assignee).then do |readable|
        if readable
          valid_assignees << assignee
        else
          invalid_assignees << assignee
        end
      end
    end).sync

    builder_params[:issue][:user_assignee_ids] = valid_assignees.map(&:id) if valid_assignees.any?

    invalid_assignees.map(&:display_login)
  end

  # Public: defines identity methods on items. For each valid content type, this
  # creates a predicate method to avoid having to do:
  #
  # item.content_type == "DraftIssue"
  #
  # Now instead, do `item.draft_issue?` or
  #
  # `item.issue?`
  # `item.pull_request?`
  #
  # Returns a boolean
  VALID_CONTENT_TYPES.each do |type|
    define_method :"#{type.underscore}?" do
      T.bind(self, MemexProjectItem)
      content_type == type
    end
  end

  def async_readable_by_viewer?(viewer)
    return async_readable_by?(viewer) if draft_issue?

    async_issue_or_pull.then do |issue_or_pull|
      next false if issue_or_pull.nil?
      issue_or_pull.async_readable_by?(viewer)
    end
  end

  # For graphQL, ProjectV2Items are not returned when underlying content is spammy.
  sig { params(viewer: User).returns(Promise[T::Boolean]) }
  def async_spammy_by_viewer?(viewer)
    return Promise.resolve(T.let(false, T::Boolean)) unless GitHub.spamminess_check_enabled?

    async_hide_from_user?(viewer).then do |should_hide|
      next true if should_hide

      async_issue_or_pull.then do |issue_or_pull|
        next false if issue_or_pull.nil?

        # preloading async user prevents n+1 when checking async_hide_from_user
        issue_or_pull.async_user.then do |_async_content_user|
          issue_or_pull.async_hide_from_user?(viewer).then do |should_hide_content|
            should_hide_content
          end
        end
      end
    end
  end

  def async_issue_or_pull
    return nil if content_id.nil? || draft_issue?

    column = content_type == MemexProjectItem::PULL_REQUEST_TYPE ? :pull_request_id : :id
    Platform::Loaders::ActiveRecord.load(::Issue, content_id, column: column).then do |issue|
      next nil if issue.nil?
      issue.async_pull_request.then do |pull_request|
        pull_request || issue
      end
    end
  end

  batch_method(:is_content_spammy?, T::Boolean) do |items, viewer|
    promises = items.map do |item|
      item.async_spammy_by_viewer?(viewer)
    end

    results = Promise.all(promises).sync
    items.zip(results).to_h
  end

  # Public: Returns a list of valid content_type options.
  def self.content_types
    content_types = Set.new(VALID_CONTENT_TYPES)
    content_types << REDACTED_ITEM_TYPE
  end

  def to_issue_authorizable
    Issue::Authorizable.new(issue_id, repository_id)
  end

  def diff_tracked_by_values(child, parents_param = [], actor)
    tracked_by_parents_param = parents_param.filter_map do |parent|
      DraftIssueReferenceFilter.new(text: parent.to_s, viewer: actor).first_reference
    end

    current_tracked_by_parents = child.normalized_tracking_issues(viewer: actor)

    # Split between new (to add), does not exist (to remove), and unchanged (to keep)
    #
    # Returns an array of arrays, where the sub-array is a list of issues to add or remove
    tracked_by_parents_to_add = []
    parents_to_remove = current_tracked_by_parents.clone # exists in current but not in params
    tracked_by_parents_param.each do |parent_param|
      index_of_parent = parents_to_remove.find_index { |i| i[:issue_id] == parent_param.id }
      if index_of_parent.nil?
        # exists in params but not current
        tracked_by_parents_to_add.push(parent_param)
      else
        # unchanged, exist in current and is still in params
        parents_to_remove.delete_at(index_of_parent)
      end
    end
    tracked_by_parents_to_remove = Issue.where(id: parents_to_remove.map { |parent| parent[:issue_id] })

    [tracked_by_parents_to_add, tracked_by_parents_to_remove]
  end

  def self.children_for_parent(parent_issue)
    return [] unless parent_issue.present?

    children_for_parent_response(parent_issue)
  rescue Faraday::Error => e
    GitHub.logger.error(
      e,
      "error.context": "children failed",
      "code.namespace": "MemexProjectItem"
    )
    GitHub.dogstats.increment("memex_project_item.get_project_item_completions_failed")
    []
  end

  def redacted_item_type?
    content_type == REDACTED_ITEM_TYPE
  end

  def draft_issue_type?
    content_type == DRAFT_ISSUE_TYPE
  end

  # Helper to determine if the item is an issue. Specifically avoiding issue_type? to prevent
  # confusion witth the issue types feature.
  def content_is_issue?
    content_type == ISSUE_TYPE
  end

  # Override ApplicationRecord::Base#reset_memoized_attributes to make sure that we clear memoization variables
  # on reload.
  sig { void }
  def reset_memoized_attributes
    remove_instance_variable(:@issue_for_content) if defined?(@issue_for_content)
    remove_instance_variable(:@delivery_system) if defined?(@delivery_system)
    remove_instance_variable(:@insights_entity_org) if defined?(@insights_entity_org)
  end

  sig { returns(Elastomer::Interfaces::Document::MemexProjectItem::Metadata) }
  def elasticsearch_metadata
    Elastomer::Interfaces::Document::MemexProjectItem::Metadata.new(
      id: T.must(id),
      memex_project_id:,
      virtual_priority: stringified_virtual_priority,
      creator_id: creator_id,
      archived_at: archived_at&.iso8601,
      created_at: created_at&.iso8601,
      updated_at: updated_at&.iso8601,
    )
  end

  sig do
    params(
      prioritization_options: T::Hash[T.untyped, T.untyped],
      suppress_hydro_events: T::Boolean,
      skip_elasticsearch_updates: T::Boolean
    )
    .returns(T.nilable(MemexProjectColumn::Interface::Writeable::Result))
  end
  def update_priority(prioritization_options, suppress_hydro_events: false, skip_elasticsearch_updates: false)
    options = prioritization_options.merge({ suppress_hydro_events:, skip_elasticsearch_updates: })
    T.must(memex_project).save_with_priority!(self, **options)
  end

  sig do
    params(
      column_value_updates: T::Array[T::Hash[T.untyped, T.untyped]],
      user: User,
      suppress_hydro_events: T::Boolean,
      skip_elasticsearch_updates: T::Boolean,
    ).returns(T.nilable(MemexProjectColumn::Interface::Writeable::Result))
  end
  def update_column_values(column_value_updates, user, suppress_hydro_events: false, skip_elasticsearch_updates: false)
    mysql_write_succeeded = update_column_values_in_mysql(column_value_updates, user, suppress_hydro_events:)
    return nil unless mysql_write_succeeded

    elasticsearch_result = if !skip_elasticsearch_updates
      bulk_update_actions = column_value_updates.each_with_object([]) do |update, acc|
        action = update[:column]&.to_field&.elasticsearch_bulk_update_action(self)
        acc << action if action
      end
      self.class.bulk_update_elasticsearch(bulk_update_actions)
    end

    MemexProjectColumn::Interface::Writeable::Result.new(
      mysql: MemexProjectColumn::Interface::Writeable::PartialResult.success,
      elasticsearch: elasticsearch_result
    )
  end

  sig do
    params(
      column_value_updates: T::Array[T::Hash[T.untyped, T.untyped]],
      user: User,
      suppress_hydro_events: T::Boolean,
    ).returns(T::Boolean)
  end
  private def update_column_values_in_mysql(column_value_updates, user, suppress_hydro_events: false)
    disable_hydro_event_instrumentation = suppress_hydro_events

    update_results = column_value_updates.map do |column_value_update|
      set_column_value(
        column_value_update[:column],
        column_value_update[:value],
        user,
        column_value_update[:append_only],
        suppress_hydro_events:,
      )
    end

    # Each update result is a boolean indicating success or failure, so check that they are all truthy.
    update_results.all?
  end

  sig do
    params(
      prioritization_options: T::Hash[T.untyped, T.untyped],
      column_value_updates: T::Array[T::Hash[T.untyped, T.untyped]],
      user: User,
      project_view: MemexProjectView
    ).returns(T.nilable(MemexProjectColumn::Interface::Writeable::Result))
  end
  def move(prioritization_options:, column_value_updates:, user:, project_view:)
    column_value_updates.each do |column_value_update|
      column = column_value_update[:column]
      column_value_update[:previous_value] = find_column_value(column.id)&.value
    end

    mysql_result = MemexProjectItem.transaction do
      successfully_updated_column_values = update_column_values_in_mysql(
        column_value_updates,
        user,
        suppress_hydro_events: true
      )
      successfully_updated_priority = update_priority(
        prioritization_options,
        suppress_hydro_events: true,
        skip_elasticsearch_updates: true
      )

      next true if successfully_updated_column_values && successfully_updated_priority
      raise ActiveRecord::Rollback
    end

    elasticsearch_result = nil

    if mysql_result
      bulk_update_actions = column_value_updates.each_with_object([]) do |update, acc|
        action = update[:column]&.to_field&.elasticsearch_bulk_update_action(self)
        acc << action if action
      end
      bulk_update_actions << elasticsearch_metadata_bulk_update_action
      elasticsearch_result = self.class.bulk_update_elasticsearch(bulk_update_actions.compact)

      GlobalInstrumenter.instrument "memex.project_item_move", {
        actor: user,
        project: memex_project,
        project_item: self,
        project_view: project_view,
        project_column_value_records: instrument_new_column_values(column_value_updates)
      }
    end

    if mysql_result
      MemexProjectColumn::Interface::Writeable::Result.new(
        mysql: MemexProjectColumn::Interface::Writeable::PartialResult.success,
        elasticsearch: elasticsearch_result
      )
    else
      nil
    end
  end

  sig do
    params(actions: T::Array[MemexProjectColumn::Interface::Writeable::BulkUpdateAction])
    .returns(T.nilable(MemexProjectColumn::Interface::Writeable::PartialResult))
  end
  def self.bulk_update_elasticsearch(actions)
    return if actions.empty?

    response = Search::Memex::Client.new(Elastomer::Indexes::MemexProjectItems.new).bulk do |bulk|
      actions.each { |a| bulk.update(a.body, a.params) }
    end

    if response.errors
      GitHub.logger.error(
        "Synchronous bulk update of project item data in Elasticsearch failed",
        {
          "code.namespace" => self.name,
          "code.function" => "bulk_update_elasticsearch",
          "gh.memex.es.api.bulk.actions" => actions.map(&:serialize).to_json,
          "gh.memex.es.api.bulk.response" => response.to_hash.to_json
        }
      )
      MemexProjectColumn::Interface::Writeable::PartialResult.failure("Bulk update failed")
    else
      MemexProjectColumn::Interface::Writeable::PartialResult.success
    end
  rescue ElastomerClient::Client::RequestError => error
    MemexProjectColumn::Interface::Writeable.rescue_client_error(error:, context: self.name)
  end

  def issue_for_content
    @issue_for_content ||= \
      case content_type
      when PULL_REQUEST_TYPE
        content.issue
      when ISSUE_TYPE
        content
      else
        nil
      end
  end

  sig { returns(T.nilable(MemexProjectColumn::Interface::Writeable::PartialResult)) }
  def update_elasticsearch_metadata!
    return unless update_params = elasticsearch_metadata_update_action

    response = Search::Memex::Client.new(Elastomer::Indexes::MemexProjectItems.new).update(*update_params)

    if response.success?
      MemexProjectColumn::Interface::Writeable::PartialResult.success
    elsif response
      GitHub.logger.error(
        "Synchronous update of project item metadata in Elasticsearch failed",
        {
          "code.namespace" => self.class.name,
          "code.function" => "update_elasticsearch_metadata",
          "gh.memex.project.id" => memex_project_id,
          "gh.memex.item.id" => id,
          "gh.memex.es.api.update.response" => response.to_hash.to_json
        }
      )
      MemexProjectColumn::Interface::Writeable::PartialResult.failure(response.result.serialize)
    end
  rescue ElastomerClient::Client::RequestError => error
    MemexProjectColumn::Interface::Writeable.rescue_client_error(error:, context: self.class.name)
  end

  # Returns the parameters used to update metadata for this item in Elasticsearch via the single item update API.
  sig { returns(T.nilable([Elastomer::Interfaces::Api::Update::Request::Body, Elastomer::Interfaces::Api::Update::Request::Params])) }
  def elasticsearch_metadata_update_action
    return unless memex_project&.feature_enabled?(:memex_sync_write_to_es)

    [
      Elastomer::Interfaces::Api::Update::Request::Body.new(doc: elasticsearch_metadata.to_hash),
      Elastomer::Interfaces::Api::Update::Request::Params.new(id: T.must(id), routing: memex_project_id)
    ]
  end

  # Returns the parameters used to update metadata for this item in Elasticsearch via the bulk update API.
  sig { returns(T.nilable(MemexProjectColumn::Interface::Writeable::BulkUpdateAction)) }
  def elasticsearch_metadata_bulk_update_action
    return unless memex_project&.feature_enabled?(:memex_sync_write_to_es)

    MemexProjectColumn::Interface::Writeable::BulkUpdateAction.new(
      body: { doc: elasticsearch_metadata.to_hash },
      params: { _id: id, _routing: memex_project_id },
    )
  end

  private

  def instrument_new_column_values(column_value_updates)
    column_value_updates.map do |new_column_value|
      column = new_column_value[:column]
      {
        memex_project_column_id: column.id,
        value: new_column_value[:value].to_s,
        previous_value: new_column_value[:previous_value],
        project_column: column,
      }
    end
  end

  batch_method(:completion) do |items|
    default = items.each_with_object({}) { |item, hash| hash[item] = {} }
    next default if items.empty?

    memex_project = items.first.memex_project
    next default unless memex_project.tracks_and_tracked_by_enabled?
    next default unless GitHub.flipper[:project_hierarchy_columns].enabled?
    # If we're only fetching one item, we can use the hierarchy state of the item instead. If this is an issue in a large
    # project, this will be faster than fetching the full project, and if it is a project with a single item, the difference
    # is negligible.
    if items.length == 1 && items.first.issue? && GitHub.flipper[:optimize_single_memex_hierarchy_prefill].enabled?(memex_project.owner)
      item = items.first
      completion = item.content.hierarchy_completion
      next { item => {
          total: completion.total,
          completed: completion.completed,
          percent: completion.percent,
        }
      } if completion
    end

    response = projects_completions_response(memex_project)

    next default if response.error?

    item_completions = response.data["items"].index_by { |item| item["key"]["itemId"] }

    completeables = memex_project.owner.feature_enabled?(:tasklist_block) ? items.reject(&:draft_issue?) : items.select(&:issue?)
    completeables.each_with_object(Hash.new) do |item, hash|
      next unless item_completion = item_completions[item.content_id]

      hash[item] = {
        total: item_completion["total"],
        completed: item_completion["completed"],
        percent: item_completion["percent"],
      }
    end
  end

  def self.projects_completions_response(memex_project)
    request_options = {
      owner_id: memex_project.owner_id,
      item_id: memex_project.id,
      force_graph: GitHub.issues_graph_api_disable_denormalized_read_enabled?,
      stat_tags: ["context:memex_project_item.batch_method.completion", "client:strict"]
    }

    if GitHub.flipper[:memex_increased_issues_graph_timeouts].enabled?(memex_project)
      GitHub.issues_graph_api_client_slow.get_project_item_completions(**request_options)
    else
      GitHub.issues_graph_api_client_strict.get_project_item_completions(**request_options)
    end
  end
  private_class_method :projects_completions_response

  batch_method(:tracked_by_items) do |items|
    default = items.each_with_object({}) { |item, hash| hash[item] = [] }
    next default if items.empty?

    memex_project = items.first.memex_project
    next default unless memex_project.tracks_and_tracked_by_enabled?
    next default unless GitHub.flipper[:project_hierarchy_columns].enabled?
    # If we're only fetching one item, we can use the hierarchy state of the item instead. If this is an issue in a large
    # project, this will be faster than fetching the full project, and if it is a project with a single item, the difference
    # is negligible.
    if items.length == 1 && items.first.issue? && GitHub.flipper[:optimize_single_memex_hierarchy_prefill].enabled?(memex_project.owner)
      item = items.first
      hierarchy_state = item.content.hierarchy_state
      next { item => hierarchy_state.trackedBy.map { |i| i.issues.empty? ? nil : TasklistBlocks::Issue.from_proto(issue: i.issues.first) }.compact } if hierarchy_state
    end

    response = project_item_tracked_by_response(memex_project)

    raise ItemPrefillError.new('We encountered a problem retrieving the "Tracked by" data. Please try again later.', MemexProjectColumn::TRACKED_BY_COLUMN_NAME) if response.error?

    items_tracked_by_items = response.data["items"].index_by { |item| item["key"]["itemId"] }

    trackables = memex_project.owner.feature_enabled?(:tasklist_block) ? items.reject(&:draft_issue?) : items.select(&:issue?)
    trackables.each_with_object(Hash.new) do |item, hash|
      next unless tracked_by_items = items_tracked_by_items[item.content_id]
      hash[item] = tracked_by_items["trackedByItems"].uniq.map { |issue| TasklistBlocks::Issue.from_proto(issue: issue) }
    end
  end

  def self.project_item_tracked_by_response(memex_project)
    request_options = {
      owner_id: memex_project.owner_id,
      item_id: memex_project.id,
      force_graph: GitHub.issues_graph_api_disable_denormalized_read_enabled?,
      stat_tags: ["context:memex_project_item.batch_method.tracked_by_items", "client:strict"],
    }

    if GitHub.flipper[:memex_increased_issues_graph_timeouts].enabled?(memex_project)
      GitHub.issues_graph_api_client_slow.get_project_tracked_by_items(**request_options)
    else
      GitHub.issues_graph_api_client_strict.get_project_tracked_by_items(**request_options)
    end
  end
  private_class_method :project_item_tracked_by_response

  def self.children_for_parent_response(parent_issue)
    default = []
    return default unless parent_issue.present?

    request_options = {
      ownerId: parent_issue.repository.owner_id,
      itemId: parent_issue.id,
    }

    result = GitHub.issues_graph_api_client_strict.get_issue(
      key: request_options,
      stat_tags: ["context:memex_project_item.children_for_parent_response", "client:strict"]
    )
    return default if result.error?

    parent = result.data.issue || {}
    tracking_blocks = result.data["tracking"] || []
    completion = parent["completion"] || {}

    children = tracking_blocks.reduce(default) do |acc, tracking_block|
      next acc if (issues = tracking_block["issues"]).empty?
      acc += issues
        .map { |issue| TasklistBlocks::Issue.from_proto(issue: issue) }
        .reject { |issue| GRAPH_DRAFT_ISSUE_STATE.include?(issue.state) }
    end

    [children, {
      item_id:   completion["key"]["itemId"],
      owner_id:  completion["key"]["ownerId"],
      repository_id: parent_issue.repository.id,
      completed: completion["completed"],
      total:     completion["total"],
      percent:   completion["percent"],
    }]
  end
  private_class_method :children_for_parent_response

  def set_item_repository_id
    self.repository_id = content.repository_id
  end

  def set_denormalize_issue_fields
    self.issue_id = issue_for_content.id
    self.issue_created_at = issue_for_content.created_at
    self.issue_closed_at = issue_for_content.closed_at
    self.state = issue_for_content.state
    self.state_reason = issue_for_content.state_reason
  end

  # This uses the given prefilled_associations to mimic the `url` method on the
  # underlying content object. That saves us having to load the content object
  # itself.
  #
  # prefilled_associations - MemexProjectItem::PrefilledAssociation object returned from a previous
  #   call to MemexProjectItemPrefiller#prefill.
  #
  # Returns String URL of this item's content object.
  def content_url(prefilled_associations:)
    denormalized_title_column_value = find_preloaded_column_value(prefilled_associations.title_column.id)
    number = denormalized_title_column_value&.json_value&.fetch("number", nil)
    repository = prefilled_associations.repository(self)
    return unless number && repository

    case content_type
    when PULL_REQUEST_TYPE
      "#{repository.permalink}/pull/#{number}"
    when ISSUE_TYPE
      "#{repository.permalink}/issues/#{number}"
    else
      nil
    end
  end

  def creator_has_verified_email
    return unless creator&.must_verify_email?

    return unless GitHub.email_verification_enabled?

    return if creator&.bot?

    errors.add(:creator, "must have a verified email address") unless creator&.verified_emails?
  end

  def repository_required?
    [ISSUE_TYPE, PULL_REQUEST_TYPE].include?(content_type)
  end

  def issue_required?
    [ISSUE_TYPE, PULL_REQUEST_TYPE].include?(content_type)
  end

  def item_can_be_created
    return unless (project = memex_project)

    if archived? && project.has_reached_archived_items_limit?
      errors.add(:base, "Projects cannot have more than #{project.archived_items_limit} archived items. Please delete existing archived items.")
    elsif !archived? && project.has_reached_items_limit?
      errors.add(:base, :project_limit_reached, message: "Projects cannot have more than #{project.items_limit} items. To add more, please archive or delete existing items.")
    end
  end

  def instrument_create_event
    payload_actor = creator || User.ghost

    instrument(:create, actor_id: payload_actor&.id)
    GlobalInstrumenter.instrument "memex_event", {
      actor: payload_actor,
      memex_project: memex_project,
      memex_project_item: self,
      performed_at: Time.current,
      name: ON_CREATE_INSTRUMENTATION_KEY
    }
  end

  private def should_instrument_hydro_event?
    disable_hydro_event_instrumentation != true
  end

  def instrument_update_event
    return unless should_instrument_hydro_event?

    shared_payload = {
      actor: actor,
      memex_project: memex_project,
      memex_project_item: self,
      previous_values: self.previous_changes || {},
    }
    instrument_metadata_update_event(shared_payload)

    return if self.previous_changes.blank? # `touch` does not dirty the model, no need
    payload_creator = creator || User.ghost

    instrument(:update, actor_id: actor&.id)
    GlobalInstrumenter.instrument "memex_event", {
      performed_at: Time.current,
      creator: payload_creator,
      name: ON_UPDATE_INSTRUMENTATION_KEY,
      **shared_payload,
      previous_values: shared_payload[:previous_values].to_s
    }
  end

  def instrument_metadata_update_event(payload)
    return if part_of_bulk_operation?
    return unless metadata_changed?(payload)

    GlobalInstrumenter.instrument "memex.project_item_metadata_update", {
      **payload,
      previous_values: payload[:previous_values]&.to_json.to_s,
    }
  end

  def instrument_delete_event
    GlobalInstrumenter.instrument "memex_event", {
      actor: actor,
      memex_project: memex_project,
      memex_project_item: self,
      performed_at: Time.current,
      name: ON_DESTROY_INSTRUMENTATION_KEY
    }
  end

  # Implements Instrumentation::Model#event_payload, which is used to generate
  # webhook event payloads via calls to Instrumentation::Model#instrument.
  def event_payload
    {
      memex_project_item_id: id,
      changed_field_id: previous_changes&.fetch(:repository_id, nil) ? memex_project&.columns&.find(&:repository?)&.id : nil,
      organization_id: memex_project&.organization_owner_id,
      changes: previous_changes
    }.compact
  end

  def generate_deleted_webhook_payload
    # webhooks only support organization installs currently
    return unless memex_project
    return unless memex_project&.organization_owner_id
    event = Hook::Event::ProjectsV2ItemEvent.new(T.unsafe({
      action: :deleted,
      actor_id: actor&.id,
      **event_payload
    }))
    @delivery_system = Hook::DeliverySystem.new(event)
    @delivery_system.generate_hookshot_payloads
  end

  def queue_deleted_webhook_delivery
    @delivery_system&.deliver_later
  end

  def update_recently_visited
    return unless memex_project
    return unless (viewer = creator)
    memex_project&.update_last_visited_at_for_viewer(viewer: viewer)
  end

  def get_tracking_blocks_by_parent(owner_id, item_id)
    client = GitHub.issues_graph_api_client
    response = client.get_tracking_blocks_by_parent(owner_id, item_id, stat_tags: ["context:memex_project_item.get_tracking_blocks_by_parent"])
    return false if response.error?

    response.data["blocks"].map(&:to_h)
  end

  def metadata_changed?(payload)
    change_keys = payload[:previous_values].except("updated_at").symbolize_keys.keys

    # If changes are blank it means the item was `touch`ed, and we consider a change
    # to the `updated_at` column as a metadata change.
    return true if change_keys.blank?

    # Any change to the priority system counts as a metadata change.
    return true if change_keys.any? { [:priority_numerator, :priority_denominator].include?(_1) }

    metadata_keys = self.elasticsearch_metadata.to_hash.keys

    # The only other changes that count are those that include attributes that are tracked by Elasticsearch.
    change_keys.any? { metadata_keys.include?(_1) }
  end

  def part_of_bulk_operation?
    self.bulk_operation == true
  end
end
