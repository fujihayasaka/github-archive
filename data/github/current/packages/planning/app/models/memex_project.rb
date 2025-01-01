# typed: strict
# frozen_string_literal: true

class MemexProject < ApplicationRecord::Domain::Memexes
  # Type alias to represent the possible owners of a project.
  MemexOwner = T.type_alias { T.any(Organization, User) }

  # Type alias to represent the possible collaborators in a project.
  MemexCollaborator = T.type_alias { T.any(User, Team) }

  include GitHub::Validations
  include GitHub::Prioritizable::Context
  include GitHub::Prioritizable::SBT::Context
  include Spam::Spammable
  include Project::SequenceDependency
  include Instrumentation::Model
  include Business::TenantContext
  include Entity # Required for Draft Issue attachments
  include MemexProject::PermissionsDependency
  include MemexProject::IssuesGraphDependency
  include MemexProject::MigrationDependency
  include MemexProject::TemplatesDependency
  include MemexProject::ViewDependency
  include MemexProject::FilterItemsDependency
  include MemexProject::AutomationDependency
  include MemexProject::WebsocketDependency
  include MemexProject::WorkflowDependency
  include MemexProject::ArchivalDependency
  include Permissions::Attributes::Wrapper
  include ContextualActor
  include PreloadableAttributes
  include GitHub::Memoizer
  include GitHub::FlipperActor
  include GitHub::VexiActor
  include MemexProject::NewsiesAdapter
  include MemexProject::NotifydAdapter
  include MemexProject::MemexWithoutLimitsBetaDependency
  include GitHub::Tracing

  trace_method :hide_from_user?

  self.permissions_wrapper_class = Permissions::Attributes::MemexProject

  attribute :title, StringFromBinary.new
  attribute :description, StringFromBinary.new

  attr_preloadable :url

  belongs_to :created_with_memex_template, class_name: "MemexTemplate", inverse_of: :memex_projects, optional: true

  # The memex_template association is used to determine if a project is a template.
  has_one :memex_template, dependent: :destroy

  # Where we store data about how well synchronized a project is between the DB and Elasticsearch.
  has_one :memex_project_elasticsearch_consistency, dependent: :destroy

  belongs_to :owner, polymorphic: true
  belongs_to :creator, class_name: "User"
  belongs_to :deleted_by, class_name: "User"

  delegate :resolve_tenant, to: :owner, allow_nil: true

  setup_spammable(:creator)

  has_many :memex_project_items, inverse_of: :memex_project
  destroy_dependents_in_background :memex_project_items
  accepts_nested_attributes_for :memex_project_items
  prioritizes :memex_project_items,
    with: :memex_project_items,
    inverse_of: :memex_project,
    conditions: "memex_project_items.archived_at IS NULL",
    multiple_associations: true

  has_many :memex_project_columns, -> { T.unsafe(self).by_position_and_creation_time }, inverse_of: :memex_project
  destroy_dependents_in_background :memex_project_columns

  has_many :memex_project_links, dependent: :destroy

  has_many :memex_project_statuses, inverse_of: :memex_project
  destroy_dependents_in_background :memex_project_statuses

  has_one :latest_status_update, -> { latest_project_status_update }, class_name: "MemexProjectStatus"

  has_many :user_roles, -> { where("target_type" => "MemexProject") },
    as: :target, class_name: "UserRole"
  destroy_dependents_in_background :user_roles

  has_one :project_migration, foreign_key: :target_memex_project_id, inverse_of: :memex_project

  has_one :status_column, -> do
    T.unsafe(self).single_select.named(MemexProjectColumn::STATUS_COLUMN_NAME)
  end, class_name: "MemexProjectColumn"

  @@prioritized_associations ||= T.let([:memex_project_items, :memex_project_views], T.nilable(T::Array[Symbol]))

  has_many :workflows, inverse_of: :memex_project, class_name: "MemexProjectWorkflow"
  destroy_dependents_in_background :workflows

  has_many :charts, inverse_of: :memex_project, class_name: "MemexProjectChart"
  destroy_dependents_in_background :charts

  has_many :memex_project_visits, inverse_of: :memex_project
  destroy_dependents_in_background :memex_project_visits

  TITLE_BYTESIZE_LIMIT = 1024
  DEFAULT_TITLE = "Untitled table"
  COLUMN_LIMIT = 50
  MAX_REPO_CURATED_PROJECTS = 1000
  SHORT_DESCRIPTION_LIMIT = 300
  ORGANIZATION_WIDE_ROLE_CONFIG_KEY = "memex_project_organization_wide_role"
  MAX_THROTTLE_RETRIES = 2
  MWL_MINIMUM_ITEM_THRESHOLD = T.let(1_000, Integer)
  MWL_MINIMUM_AGE_THRESHOLD = T.let(6.months, ActiveSupport::Duration)
  MWL_UNSUPPORTED_FIELD_TYPES = T.let(%w(tracks tracked_by), T::Array[String])
  MEMEX_WITHOUT_LIMITS_BETA_FEATURE_FLAGS = T.let(%w(memex_table_without_limits memex_paginated_archive).freeze, T::Array[String])
  MEMEX_WITHOUT_LIMITS_PROJECTS_BETA_BATCH_SIZE = 100

  before_validation :set_number, on: :create
  after_create :create_default_view

  validates :creator, presence: true, on: :create
  validates :title, presence: true, allow_nil: true
  validates :title, bytesize: { maximum: TITLE_BYTESIZE_LIMIT }, unicode: true
  validates :owner_type, presence: true, inclusion: { in: %w[Organization User] }
  validates :owner, presence: true, on: :create
  validates :number, presence: true, numericality: { only_integer: true, greater_than: 0 }, on: :create
  validates :number, uniqueness: { scope: [:owner_type, :owner_id] }, on: :create
  validates :short_description,  length: { maximum: SHORT_DESCRIPTION_LIMIT }, allow_nil: true
  validate :creator_has_verified_email, on: :create
  validate :default_columns_pending, on: :create
  validate :projects_enabled, on: :create
  validate :public_project_is_not_owned_by_emu, if: :public_changed?

  scope :active_projects, -> { where(deleted_at: nil) }
  scope :deleted_projects, -> { where("memex_projects.deleted_at IS NOT NULL") }

  # "Public" projects that are owned by orgs or users within an enterprise with Enterprise Managed Users (EMU)
  # should actually be considered "Internal" (i.e., visible only to members of the enterprise, not to the world).
  scope :public_projects, -> { where(public: true) }

  scope :private_projects, -> { where(public: false) }
  scope :open_projects, -> { active_projects.where(closed_at: nil) }
  scope :closed_projects, -> { active_projects.where("memex_projects.closed_at IS NOT NULL") }
  scope :templates, -> { active_projects.joins(:memex_template).merge(MemexTemplate.active) }

  # Return MemexProject records that do not have an associated MemexTemplate.
  #
  # When a project has an associated MemexTemplate record but the MemexTemplate is in an inactive state, it is no
  # longer considered a template and instead an ordinary project and should be included in results.
  scope :without_templates, -> { active_projects.left_outer_joins(:memex_template).merge(MemexTemplate.where(id: nil).or(MemexTemplate.inactive)) }

  after_commit :instrument_creation, on: :create
  after_commit :instrument_update, on: :update
  after_commit :instrument_deletion, on: :destroy
  after_commit :enqueue_memex_project_reindex_content_job, only: :update, if: :deleted_at_previously_changed?
  after_commit :enqueue_memex_project_disable_all_workflows_job, only: :update, if: :closed_at_previously_changed?
  after_commit :destroy_template_project_links, only: :update, if: :closed_at_previously_changed?

  trace_method :prioritize_dependent!, span_attribute_extractor: -> (context, *args, **kwargs) { context.trace_tags(*args, **kwargs) }
  trace_method :prioritize!, span_attribute_extractor: -> (context, *_args, **kwargs) { context.prioritize_trace_tags(**kwargs) }
  trace_method :prioritize, span_attribute_extractor: -> (context, *_args, **kwargs) { context.prioritize_trace_tags(**kwargs) }

  # Public: Atomically creates a new memex with optional first item and first column associations.
  #
  # owner - Organization or user to which the memex will belong for purposes of authorization.
  # creator - User who is creating the new memex.
  # memex_template - The MemexTemplate to use for creating the memex.
  # public - Optional Boolean for whether or not the project should be public (internal if in an EMU enterprise).
  # title - String title for the new memex.
  # description - Optional String description for the new memex.
  # with_default_workflows - Boolean for whether or not to also create default workflows.
  # with_mwl_enabled - Boolean for whether or not to enable the mwl FF after creation if the project is eligible
  #
  # Returns a MemexProject object that may or may not be valid or persisted.
  sig do
    params(
      owner: MemexOwner,
      creator: User,
      memex_template: T.nilable(MemexTemplate),
      public: T::Boolean,
      title: T.nilable(String),
      description: T.nilable(String),
      with_default_workflows: T::Boolean,
      with_mwl_enabled: T::Boolean
    ).returns(MemexProject)
  end
  def self.create_with_associations(
      owner:,
      creator:,
      memex_template: nil,
      public: false,
      title: nil,
      description: nil,
      with_default_workflows: true,
      with_mwl_enabled: false
    )
    if title.nil?
      raise ArgumentError, "Must provide :title"
    end

    memex = owner.memex_projects.build(
      created_with_memex_template: memex_template,
      title: title,
      description: description,
      creator: creator,
      public: public,
    )
    attrs_for_columns = default_column_attributes(excluding: excluded_default_columns(creator, owner))
    new_columns = Array.wrap(memex.memex_project_columns.build(attrs_for_columns))

    begin
      MemexProject.throttle_writes_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) { memex.save }
    rescue ActiveRecord::ConnectionFailed => e
      GitHub.logger.error(
        e,
        "error.context": "memex project creation failed",
        "code.namespace": self.class.name
      )
      GitHub.dogstats.increment("memex.create_with_associations.creation_failure", tags: ["error:#{e.class.name}"])
    end

    if with_mwl_enabled && create_with_mwl_enabled?(creator, owner)
      memex.enable_feature(:memex_table_without_limits)
    end

    # Now that the memex_project and default_columns have been persisted,
    # we can build and persist the default workflows. In the arguments of a workflow's set field
    # action, we persist the id of the status column, so we cannot build and save these
    # workflows until that column has an id.
    #
    # Additionally, when creating a MemexProject from a MemexTemplate with_default_workflows is set to false to avoid
    # creating duplicate workflows. The workflows will be copied over from the template project.
    if with_default_workflows && memex.persisted?
      status_column = new_columns.detect(&:status?)
      attrs_for_workflows = default_persisted_workflow_attributes(creator: creator, status_column: status_column)
      MemexProjectWorkflow.throttle_with_retry { memex.workflows.create(attrs_for_workflows) }
    end

    memex
  end

  # This method is actually defined on the MemexProjectStatus model, but we want to be able to call it on a MemexProject
  sig { returns(T.nilable(MemexProjectStatus)) }
  def self.latest_project_status_update
  end

  sig { params(user: User).returns(String) }
  def self.default_user_title(user)
    "@#{user.display_login}\'s untitled project"
  end

  sig { params(user: User).returns(String) }
  def self.default_user_template_title(user)
    "@#{user.display_login}\'s untitled template"
  end

  sig { params(excluding: T::Array[String]).returns(T::Array[T::Hash[String, T.untyped]]) }
  def self.default_column_attributes(excluding: [])
    MemexProjectColumn.default_columns(excluding: excluding).each_with_index.map do |c, index|
      c.attributes.except(:id).merge(position: index + 1)
    end
  end

  # Returns an array of default columns that should be conditionally excluded during project creation.
  #   For example: memex_reviewers_column_create FF should be enabled at 100% soon after deployment,
  #   but we can initially turn it on for specific project creators for testing in review-lab and production.
  #
  # IMPORTANT: This is a temporary measure to facilitate testing. Please remove the feature flags in this method
  # prior to production deployment and/or onboarding external customers. Otherwise the necessary order of operations is:
  #   - Roll out feature flag to 100% of users
  #   - Perform transition to backfill column creation
  sig { params(creator: T.nilable(User), owner: T.nilable(MemexOwner)).returns(T::Array[String]) }
  def self.excluded_default_columns(creator, owner)
    # If the project owner is a user we don't want to create the system-defined Type column.
    if owner&.user?
      [MemexProjectColumn::TYPE_COLUMN_NAME]
    else
      []
    end
  end

  sig { returns(T.nilable(Addressable::URI)) }
  def url
    async_url.sync
  end

  sig { returns(T.any(Promise[NilClass], Promise[Addressable::URI])) }
  memoize def async_url
    async_owner.then do |owner|
      next Promise.resolve(nil) unless owner.present?

      case owner_type
      when "Organization"
        template = Addressable::Template.new("/orgs/{org}/projects/{number}")
        template.expand({ org: owner.display_login, number: number })
      when "User"
        template = Addressable::Template.new("/users/{user}/projects/{number}")
        template.expand({ user: owner.display_login, number: number })
      else
        raise NotImplementedError, "Only org and user projects are supported"
      end
    end
  end

  # To satisfy the Notifyd interface we implement the permalink method.
  sig { params(include_host: T::Boolean).returns(T.nilable(String)) }
  def permalink(include_host: true)
    if include_host
      "#{GitHub.url}#{url}"
    else
      url&.to_s
    end
  end

  # Generates a List-ID email header value for the MemexProject. This is used to
  # uniquely identify the project in email threads.
  sig { returns(String) }
  def list_id
    "#{title} <#{number}.projects.#{owner&.display_login}.#{GitHub.urls.host_name}>"
  end

  sig { params(user_id: Integer, guid: String, use_new_url: T::Boolean).returns(String) }
  def private_asset_url(user_id, guid, use_new_url)
    return "#{GitHub.url}/user-attachments/assets/#{guid}" if use_new_url
    "#{GitHub.url}#{url}/assets/#{user_id}/#{guid}"
  end

  sig { returns(T.nilable(String)) }
  def owner_display_name
    owner.display_login
  end

  sig { returns(Promise[T.nilable(Business)]) }
  def async_business
    async_owner.then do |owner|
      next nil unless owner

      if org_owned?
        owner.async_business
      elsif user_owned?
        owner.async_enterprise_managed_business
      else
        nil
      end
    end
  end

  # Public: Builds and returns the unique project search slug as a String.
  sig { returns(String) }
  def search_slug
    "#{owner.display_login}/#{number}"
  end

  # Public: HTML rendering of the rich markdown preview of the project title
  sig { returns(String) }
  def title_html
    return "" unless title
    GitHub::Goomba::TitleMarkdownFilter.call(title)
  end

  # Public: HTML rendering of the rich markdown preview of the project's short description
  sig { returns(String) }
  def short_description_html
    return "" unless short_description
    # Removes the wrapping `<div>` tags so that short_description_html
    # is an empty string when the user has not provided any content.
    Nokogiri::HTML::DocumentFragment.parse(GitHub::Goomba::DescriptionPipeline.to_html(short_description)).child.inner_html
  end

  # Some memexes had to be renumbered as part of https://github.com/github/i2c-backlog/issues/673
  # Given an org_id and the original number, returns the key needed to lookup the new number
  # in GitHub::KV
  sig { params(org_id: Integer, old_number: T.any(Integer, String)).returns(String) }
  def self.renumbered_memex_kv_key(org_id, old_number)
    "memex:renumbered:#{org_id}:#{old_number}"
  end

  # TODO: skip_draft_issue_reference can be deleted when the classic project migrator is deleted
  sig { params(creator: User, draft_issue_title: T.nilable(String), draft_issue_body: T.nilable(String), issue_or_pull: T.nilable(T.any(Issue, PullRequest)), column_data: T::Hash[Symbol, T.untyped], build_denormalized_values: T::Boolean, skip_draft_issue_reference: T::Boolean).returns(MemexProjectItem) }
  def build_item(creator:, draft_issue_title: nil, draft_issue_body: nil, issue_or_pull: nil, column_data: {}, build_denormalized_values: true, skip_draft_issue_reference: false)
    memex_item = if issue_or_pull
      memex_project_items.build(
        creator: creator,
        content: issue_or_pull
      )
    elsif draft_issue_title
      build_draft_issue(creator: creator, title: draft_issue_title, body: draft_issue_body, build_denormalized_values: false, skip_draft_issue_reference:)
    else
      raise ArgumentError, "Must provide either an issue, pull request, or draft issue title (received neither)"
    end

    memex_item.build_denormalized_column_values(creator) if build_denormalized_values

    if column_data[:column]
      memex_item.memex_project_column_values.build(
        memex_project_column: column_data[:column],
        value: column_data[:value],
        creator: creator
      )
    end

    memex_item
  end

  # Queues a job which will resync the Elasticsearch index for a single project's items.
  # Returns a JobStatus so that the progress of the job can be monitored.
  sig do
    params(
      enable_beta_flag: T.nilable(T::Boolean),
      read_only: T.nilable(T::Boolean),
    )
    .returns(ResyncMemexProjectItemsIndexJobStatus)
  end
  def queue_reindex_items(enable_beta_flag: nil, read_only: nil)
    resync_items = MemexProject::ResyncItems.new(id, enable_beta_flag:, read_only:)
    resync_items.resync_later
  end

  sig { params(creator: User, issues_or_pulls: T::Array[T.any(Issue, PullRequest)], memex_project_column_values: T::Array[T::Hash[String, T.untyped]]).returns(T.nilable(JobStatus)) }
  def bulk_add_multiple_items(creator:, issues_or_pulls:, memex_project_column_values: [])
    return nil if !self.persisted? || issues_or_pulls.empty?

    job_status = MemexBulkAddJob.create_job_status
    MemexBulkAddJob.perform_later(job_status.id, issues_or_pulls, creator.id, self.id, memex_project_column_values)

    job_status
  end

  sig { params(viewer: User, item_ids: T::Array[Integer]).returns(T.nilable(JobStatus)) }
  def destroy_project_items_later(viewer:, item_ids:)
    return nil if !self.persisted? || item_ids.empty?

    job_status = MemexDestroyItemsJob.create_job_status
    MemexDestroyItemsJob.perform_later(job_status.id, item_ids, viewer.id, self.id)

    job_status
  end

  # TODO: skip_draft_issue_reference can be deleted when the classic project migrator is deleted
  sig { params(creator: User, title: String, assignees: T::Array[User], body: T.nilable(String), build_denormalized_values: T::Boolean, skip_draft_issue_reference: T::Boolean).returns(MemexProjectItem) }
  def build_draft_issue(creator:, title:, assignees: [], body: nil, build_denormalized_values: true, skip_draft_issue_reference: false)
    item = memex_project_items.build(creator: creator)

    first_reference = if skip_draft_issue_reference
      nil
    else
      filter = DraftIssueReferenceFilter.new(text: title, viewer: creator)
      filter.first_reference
    end

    if first_reference
      item.content = first_reference
    else
      # this build_draft_issue is the AR association builder
      item.content = item.build_draft_issue(title: title, body: body, assignees: assignees)
    end

    item.build_denormalized_column_values(creator) if build_denormalized_values
    item
  end

  sig { params(name: T.nilable(String), data_type: T.any(String, Symbol), position: T.nilable(T.any(Integer, String)), creator: User, settings: T.nilable(T.any(ActionController::Parameters, T::Hash[Symbol, T.untyped]))).returns(MemexProjectColumn) }
  def add_user_defined_column(name:, data_type:, position:, creator:, settings: nil)
    new_column = build_user_defined_column(
      name: name,
      data_type: data_type,
      settings: settings,
      creator: creator
    )

    # If a desired position is provided and is not equal to the default (last) position,
    # insert the new column in the desired position. Otherwise, save the column as is.
    if position && position.to_i != new_column.position
      reload # Clear newly created column from cached list of columns.
      insert_column(new_column, position.to_i - 1)
    else
      # If the save is successful, make sure to clear the cached value of `columns`.
      new_column.save && reload
    end

    new_column
  end

  sig { params(data_type: T.any(String, Symbol), creator: User, name: T.nilable(String), settings: T.nilable(T.any(ActionController::Parameters, T::Hash[Symbol, T.untyped]))).returns(MemexProjectColumn) }
  def build_user_defined_column(data_type:, creator:, name: nil, settings: nil)
    # The column is built with the last position by default.
    # Use MemexProject#reorder_columns to place it in the desired position within the memex.
    last_position = columns.maximum(:position) + 1

    memex_project_columns.build(
      name: name || suggested_user_defined_column_name,
      data_type: data_type,
      position:  last_position,
      creator: creator,
      user_defined: true,
      visible: true,
      settings: settings,
    )
  end

  sig do
    params(
      column: MemexProjectColumn,
      name: T.nilable(String),
      position: T.nilable(T.any(Integer, String)),
      visible: T.nilable(T::Boolean),
      settings: T.nilable(T.any(ActionController::Parameters, T::Hash[Symbol, T.untyped]))
    ).returns(T::Boolean)
  end
  def update_column(column, name: nil, position: nil, visible: nil, settings: nil)
    column.name = name unless name.nil?
    column.visible = visible unless visible.nil?
    column.settings = (column.settings || {}).merge(settings) unless settings.blank?

    success = if !position.nil? && column.position != position
      insert_column(T.must(columns.delete_at(column.position - 1)), position.to_i - 1)
    else
      # If the transaction is rolled back by raising ActiveRecord::Rollback, the column will not be saved and
      # ActiveRecord returns nil.
      column.save || false
    end

    if (view = default_view) && !position.nil?
      view.update_column_order!
    end

    success
  end

  sig { params(column: MemexProjectColumn).returns(T::Boolean) }
  def delete_column(column)
    column.destroy

    if column.destroyed?
      columns.delete(column)
      reorder_columns(columns)
    else
      false
    end
  end

  sig { params(user: User).void }
  def soft_delete!(user)
    self.deleted_at = Time.zone.now
    self.deleted_by_id = user.id

    save!
    self.workflows.update_all(enabled: false)
    self.remove_template!
  end

  sig { void }
  def restore!
    self.deleted_at = nil
    self.deleted_by_id = nil

    save!
  end

  sig { override.params(association: T.nilable(Symbol)).returns(T.class_of(ApplicationJob)) }
  def rebalance_job_class(association: nil)
    if association == :memex_project_items
      RebalanceMemexProjectJob
    elsif association == :memex_project_views
      RebalanceMemexProjectViewsJob
    else
      raise ArgumentError, "Unknown association: #{association}"
    end
  end

  sig { override.params(association: Symbol, read_from_legacy_column: T.nilable(T::Boolean)).returns(ActiveRecord::Relation) }
  def prioritized_scope(association, read_from_legacy_column: nil)
    raise ArgumentError, "Invalid association: #{association}" if association != :memex_project_items
    memex_project_items.where(archived_at: nil).order(virtual_priority: :desc)
  end

  sig { params(association: Symbol).returns(Promise[ActiveRecord::Relation]) }
  def async_prioritized_scope(association)
    Platform::Loaders::ActiveRecord.load_relation(
      prioritized_scope(association).limit(MemexProjectItem::PER_PAGE_LIMIT)
    )
  end

  # Assigns the given item a priority based on the prioritization options passed.
  # If the options parameter is nil, it sets a priority such that it is the lowest priority item
  # in the memex, and then returns the newly saved item.
  #
  # Note that this can raise due to `GitHub::Prioritizable::Context::LockedForRebalance`
  # in addition to validation errors from calls to `item.validate!`.
  #
  # Returns a Boolean for whether or not the item was successfully saved
  sig { params(item: MemexProjectItem, options: T.untyped).returns(T::nilable(MemexProjectColumn::Interface::Writeable::Result)) }
  def save_with_priority!(item, **options)
    item_already_exists = !item.new_record?
    perform_elasticsearch_updates = item_already_exists && !options.delete(:skip_elasticsearch_updates)
    previous_item_prior_to_move = previous_prioritized_item(item)

    return unless save_and_prioritize!(item, options)

    if item_already_exists
      item.instrument(
        :reorder,
        actor_id: actor&.id,
        changes: {
          previous_projects_v2_item_node_id: {
            from: previous_item_prior_to_move&.global_relay_id,
            to: options.dig(:after)&.global_relay_id,
          }
        }
      )
    end

    MemexProjectColumn::Interface::Writeable::Result.new(
      mysql: MemexProjectColumn::Interface::Writeable::PartialResult.success,
      elasticsearch: perform_elasticsearch_updates ? item.update_elasticsearch_metadata! : nil
    )
  end

  sig { params(item: MemexProjectItem, options: T.untyped).returns(T::Boolean) }
  private def save_and_prioritize!(item, options)
    item.disable_hydro_event_instrumentation = options.delete(:suppress_hydro_events)

    if options.blank?
      last_item_scope = prioritized_scope(:memex_project_items)
      last_item_scope = last_item_scope.where.not(id: item.id) if item.id
      options = { after: last_item_scope.last }.compact
    end

    prioritize!(
      item:,
      association: :memex_project_items,
      position: GitHub::Prioritizable::SBT::Position.from_options(options)
    )

  rescue ActiveRecord::RecordNotUnique
    item.errors.add(:base, "Your attempt to move this item created a temporary conflict. Please try again.")
    false
  end

  # Returns the item that is immediately before the given item in the prioritized
  # list of items belonging to this project.
  #
  # @param item The current item to which the result of this method is relative.
  #   If this item has not yet been persisted, then this method will return `nil`.
  sig { params(item: MemexProjectItem).returns(T.nilable(MemexProjectItem)) }
  private def previous_prioritized_item(item)
    return unless item.id

    prioritized_scope(:memex_project_items)
      .reverse_order
      .where("virtual_priority > ?", item.virtual_priority)
      .limit(1)
      .first
  end

  sig { params(column: MemexProjectColumn, options: T.untyped).returns(T::Boolean) }
  def save_column_with_priority(column, **options)
    if options.blank?
      # default will be to place the column in the last position
      last_column = memex_project_columns.order(position: :desc).first
      options = { after: last_column }
    end
    column.validate!

    reprioritize_memex_project_columns(column, **options)
    # TODO: is it necessary to reload the related columns?
  end

  sig { returns(T.nilable(MemexProjectColumn)) }
  def status_column
    return @status_column if defined?(@status_column)
    result = if association(:memex_project_columns).loaded?
      memex_project_columns.detect(&:status?)
    else
      super # use the `has_one :status_column` relation to load just the status column
    end
    @status_column = T.let(result, T.nilable(MemexProjectColumn))
  end

  # Public: Fetch the ordered list of current columns for this memex.
  #
  # Note that this is NOT the same as the `memex_project_columns` method. That
  # method will only ever return persisted columns, whereas this method may
  # return default, unpersisted columns. Furthermore, the result of this method
  # is memoized, so the memex must be reloaded after column changes are made in
  # order for this to show accurate information.
  #
  # Returns Array<MemexProjectColumn>
  sig { returns(T::Array[MemexProjectColumn]) }
  def columns
    @columns ||= T.let(begin
      non_default_columns = memex_project_columns.to_a
      non_default_columns.any? ? non_default_columns : MemexProjectColumn.default_columns
    end, T.nilable(T::Array[MemexProjectColumn]))
  end

  # Retrieves any column by ID or a system-defined column by name.
  # This is useful for finding a default column before it may have been persisted.
  #
  # Returns MemexProjectColumn or nil.
  sig { params(identifier: T.nilable(T.any(Integer, String))).returns(T.nilable(MemexProjectColumn)) }
  def find_column_by_name_or_id(identifier)
    return unless identifier
    columns.find { |column| column.matches_identifier?(identifier) }
  end

  # Override ApplicationRecord::Base#reset_memoized_attributes to make sure that we clear memoization variables, like
  # the list of cached columns, on reload.
  sig { void }
  def reset_memoized_attributes
    remove_instance_variable(:@columns) if defined?(@columns)
    remove_instance_variable(:@automations_enabled) if defined?(@automations_enabled)
    remove_instance_variable(:@auto_add_creation_limit) if defined?(@auto_add_creation_limit)
    remove_instance_variable(:@insights_entity_org_id) if defined?(@insights_entity_org_id)
    remove_instance_variable(:@feature_template_normalized) if defined?(@feature_template_normalized)
    remove_instance_variable(:@feature_template) if defined?(@feature_template)
    remove_instance_variable(:@backlog_template_normalized) if defined?(@backlog_template_normalized)
    remove_instance_variable(:@backlog_template) if defined?(@backlog_template)
    remove_instance_variable(:@status_column) if defined?(@status_column)
    remove_instance_variable(:@is_memex_paginated_archive_enabled) if defined?(@is_memex_paginated_archive_enabled)
  end

  # Reorder persisted columns such that they match the given column order.
  #
  # reordered_columns - Array<MemexProjectColumn>, all of which should belong to this memex and
  #   should have already been persisted. Note that any other outstanding changes on these objects
  #   will also be persisted.
  #
  # Returns Boolean for whether or not the operation succeeded.
  sig { params(reordered_columns: T::Array[MemexProjectColumn]).returns(T::Boolean) }
  def reorder_columns(reordered_columns)
    # Bail early if there are other changes to a column that make it invalid.
    return false unless reordered_columns.all?(&:valid?)

    # First move everything out of the way so that we avoid collisions that
    # would upset the uniqueness constraint on `position`.
    MemexProjectColumn
      .where(id: reordered_columns.map(&:id))
      .update_all(["position = position + ?", COLUMN_LIMIT * 2]) # temporary fix for `position` collision

    # Then update positions to what they should be. This intentionally uses `update_column` so that
    # we don't need to reload records in order to avoid ActiveRecord short-circuiting an update
    # because it matches an old value from before the `update_all` statement above.
    results = []
    reordered_columns.each_with_index do |c, index|
      success = if c.persisted?
        c.update_column(:position, index + 1)
      else
        c.position = index + 1
        c.save
      end
      results << success
    end

    results.all?
  end

  # Check whether hierarchy fields (Tracks and Tracked by) are enabled for the project.
  # Hierarchy fields are typically enabled by the :tasklist_block feature flag,
  # but are disabled by when memex_table_without_limits is enabled.
  sig { returns(T::Boolean) }
  memoize def tracks_and_tracked_by_enabled?
    # Tracks & Tracked By columns are always created by default, but they are not enabled for use on GitHub Enterprise
    return false if GitHub.enterprise?

    !!(owner&.feature_enabled?(:tasklist_block) && !memex_table_without_limits_or_pwl_public_beta_enabled?)
  end

  # Returns a list of project ids enrolled in the Memex Without Limits beta experience.
  #
  # For details on the Memex Without Limits enrollment strategy, please see:
  # https://github.com/github/projects-backend/blob/main/docs/initiatives/memex-without-limits/onboarding-projects-to-memex-without-limits.md
  sig { returns(T::Array[Integer]) }
  def self.memex_without_limits_beta_projects
    # de-duplicate any ids that might be in both feature flags
    result = Set.new

    MEMEX_WITHOUT_LIMITS_BETA_FEATURE_FLAGS.each do |flag_name|
      each_project_id_with_feature_flag_enabled(flag_name) do |project_id|
        result << project_id if project_id.present?
      end
    end

    result.to_a
  end

  sig { returns(T::Enumerable[T::Array[Integer]]) }
  def self.memex_without_limits_beta_projects_in_batches
    memex_without_limits_beta_projects.each_slice(MEMEX_WITHOUT_LIMITS_PROJECTS_BETA_BATCH_SIZE)
  end

  sig { returns(T::Boolean) }
  def has_reached_items_limit?
    memex_project_items.for_page_limit.count >= items_limit
  end

  # Naming it slightly differently to avoid confusion with the method above
  batch_method(:has_exceeded_items_limit?) do |projects|
    # Get all MPIs for the batch of projects, apply scope, group by project and count
    project_item_counts = MemexProjectItem
                          .where(memex_project_id: projects.map(&:id))
                          .for_page_limit
                          .group(:memex_project_id)
                          .count

    # creates a hash where keys are `project` objects and values are the results of the block below
    projects.index_with do |project|
      limit = project.items_limit
      project_item_counts[project.id].to_i >= limit
    end
  end

  sig { returns(Integer) }
  memoize def items_limit
    if !GitHub.flipper[:memex_without_limits_kill_switch].enabled? && memex_table_without_limits_or_pwl_public_beta_enabled?
      MemexProjectItem::EXPANDED_ITEM_LIMIT
    else
      MemexProjectItem::PER_PAGE_LIMIT
    end
  end

  # Returns the subset of persisted charts based on the account plan limits and Insights enablement.
  # If memex_insights is enabled, we'll continue to honor full chart functionality with no limits.
  sig { returns(T::Array[MemexProjectChart]) }
  memoize def supported_charts
    supported = T.let(charts.order(:number).to_a, T::Array[MemexProjectChart])
    unless insights_enabled_for_owner?
      supported = supported.reject { |chart| chart.configuration&.dig("xAxis", "dataSource", "column") == "time" }
    end
    unless unlimited_charts?
      supported = supported.take(MemexProjectChart::LIMITED_CHARTS_LIMIT)
    end
    supported
  end

  # Returns true if the number of persisted charts has reached the limit allowed by the account plan.
  # If memex_insights is enabled, we'll continue to honor full chart functionality with no limits.
  sig { returns(T::Boolean) }
  memoize def has_reached_chart_limit?
    !unlimited_charts? && supported_charts.length >= MemexProjectChart::LIMITED_CHARTS_LIMIT
  end

  # Unlimited charts depend on the account and project visibility, or enabled by the memex_charts_basic_allow feature flag
  sig { returns(T::Boolean) }
  memoize def unlimited_charts?
    visibility = public? ? :public : :private
    owner.plan_supports?(:projectsv2_charts_basic, visibility: visibility) ||
      insights_enabled_for_owner? ||
      GitHub.flipper[:memex_charts_basic_allow].enabled?(owner)
  end

  # Historical insights charts (Time for the x-axis) are enabled only for paid plans or by the legacy memex_insights feature flag
  # memex_charts_for_all is a new feature flag that allows all plans to have historical insights charts
  sig { params(viewer: T.nilable(User)).returns(T::Boolean) }
  def insights_enabled_for_owner?(viewer: actor)
    return true if GitHub.flipper[:memex_charts_for_all].enabled? || viewer&.feature_enabled?(:memex_charts_for_all)

    visibility = public? ? :public : :private
    owner.plan_supports?(:projectsv2_insights_limited, visibility: visibility) ||
      owner.plan_supports?(:projectsv2_insights_basic, visibility: visibility) ||
      GitHub.flipper[:memex_insights].enabled?(owner)
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_hash
    {
      closedAt: closed_at&.utc&.iso8601,
      createdAt: created_at&.utc&.iso8601,
      description: description,
      id: id,
      number: number,
      public: public,
      shortDescription: short_description,
      shortDescriptionHtml: short_description_html,
      title: title,
      titleHtml: title_html,
      updatedAt: updated_at&.utc&.iso8601,
      isTemplate: is_template?,
      templateId: memex_template&.id,
    }
  end

  sig { returns(T::Boolean) }
  def closed?
    closed_at.present?
  end

  sig { returns(T::Boolean) }
  def deleted?
    deleted_at.present?
  end

  sig { returns(T.nilable(Integer)) }
  def set_number
    return if self.number
    return unless owner

    create_sequence_if_missing
    self.number = Sequence.next(self)
  end

  # Returns a suggested column name for new columns created for this memex.
  #
  # Note this method is not thread-safe, and _can_ result in duplicate suggested
  # names. See https://github.com/github/memex/issues/739 for more details
  #
  # Returns a String.
  sig { returns(String) }
  def suggested_user_defined_column_name
    user_column_count = memex_project_columns.user_defined.count
    name = MemexProjectColumn::NEW_COLUMN_NAME.dup

    if user_column_count.zero?
      name
    else
      [name, user_column_count + 1].join(" ")
    end
  end

  sig { returns(String) }
  def display_title
    title || DEFAULT_TITLE
  end
  alias_method :name, :display_title

  sig { returns(String) }
  def platform_type_name
    @platform_type_name || "ProjectV2"
  end

  sig { params(platform_type_name: String).returns(T.nilable(String)) }
  attr_writer :platform_type_name

  sig { returns(T::Boolean) }
  def internally_owned?
    org_owned? && owner_id == FlipperFeature::GITHUB_ORG_ID
  end

  sig { returns(T::Boolean) }
  def org_owned?
    owner_type == "Organization"
  end

  sig { returns(T::Boolean) }
  def user_owned?
    owner_type == "User"
  end

  # This is a required field for NotifyD, used to determine the author of a 'thread'
  sig { returns(T.nilable(Integer)) }
  def user_id
    creator_id
  end

  sig { returns(T.nilable(Integer)) }
  def organization_owner_id
    org_owned? ? owner_id : nil
  end

  sig { returns(T.nilable(Organization)) }
  def organization_owner
    org_owned? ? owner : nil
  end

  # Handles the scenario where we are transforming a User into an Organization.
  # - changes the memex owner to an Organization
  # - updates the creator to the new org's administrator
  sig { params(new_owner: Organization, new_creator: T.nilable(User)).void }
  def transform_owner_type!(new_owner:, new_creator:)
    new_owner_type = new_owner.class.name
    raise "Cannot transform #{owner_type} memex project to #{new_owner_type} project" unless new_owner.organization? && new_owner_type

    # Set the new attribute values
    self.owner = new_owner
    self.owner_type = new_owner_type
    self.creator = new_creator
    self.number = nil

    # Remove the memoized sequence context since it references the old owner
    remove_instance_variable(:@sequence_context) if instance_variable_defined?(:@sequence_context)

    # This prevents a frankenquery composed of a SELECT on the new owner_type's
    # table with a WHERE clause from the old owner_type's table and old
    # owner_id.
    #
    # Calling reset_scope on the association before
    # ActiveRecord::Associations::SingularAssociation#find_target gets called
    # resets the scope and executes the correct query.
    association(:owner).reset_scope

    create_sequence_if_missing
    self.number = Sequence.next(self)
    save!

  end

  # The class name persisted as `target_type` when a UserRole is created
  # with this object as target.
  #
  # Returns: String
  sig { returns(String) }
  def user_role_target_type
    "MemexProject"
  end

  # All Memex projects should have an owner for the CAP target, but this may be nil from a hacked cross-tenant API request
  # such as in this bounty issue: https://github.com/github/memex/issues/17198.
  # In that case, return :no_target_for_conditional_access to avoid a 500 error in the CAP code.
  # This is still safe because :require_this_memex will 404 if the Memex project or owner is nil.
  sig { returns T.any(MemexOwner, Symbol) }
  def target_for_conditional_access
    # In the CAP framework, TFCA refers to the entity governing
    # the conditional access rules that grant access to resources they own.
    # If any changes are done to this method, please loop in @github/authorization.
    # https://thehub.github.com/engineering/development-and-ops/dotcom/cap/how-does-cap-evaluation-work/#target-for-conditional-access-tfca
    owner || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  # Determines the target for for conditional access for multiple projects.
  #
  # Parameters:
  # memex_projects - the list of memex projects we want to check access to
  #
  # Returns: a hash mapping each memex project to its target for conditional access
  sig { params(memex_projects: T::Enumerable[MemexProject]).returns(T::Hash[MemexProject, MemexOwner]) }
  def self.multiple_target_for_conditional_access(memex_projects)
    ConditionalAccess::Filter.ensure_with_class(memex_projects, MemexProject)

    owners = User.where(id: memex_projects.map(&:owner_id))
    owner_to_target = User.multiple_target_for_conditional_access(owners)

    owner_id_to_target = owner_to_target.transform_keys { |k| k.id }
    memex_projects.each_with_object({}) { |v, h| h[v] = owner_id_to_target[v.owner_id] }
  end

  # This method is taking list of memex ids we want to check access to and returns list of memex_projects that viewer has access to.
  #
  # Parameters:
  # viewer - the user that is trying to get access to the list of memex projects
  # memex_project_ids - ids of memex projects viewer trying to get access to
  # min_permission_level - what permission level we're checking for. Possible values: read, write, admin
  sig { params(viewer: T.nilable(User), memex_project_ids: T::Array[Integer], min_permission_level: T.nilable(T.any(String, Symbol))).returns(Promise[T::Array[MemexProject]]) }
  def self.async_accessible_memexes(viewer, memex_project_ids, min_permission_level = "read")
    Platform::Loaders::ActiveRecord.load_all(::MemexProject, memex_project_ids).then do |memex_projects|
      GitHub::PrefillAssociations.prefill_associations(memex_projects, :owner)

      self.async_filter_accessible_memexes(viewer, memex_projects.compact, min_permission_level)
    end
  end

  # This method is taking list of MemexProjects, returning those which the given user has the min_permission_level of access to
  #
  # Parameters:
  # viewer - the user that is trying to get access to the list of memex projects
  # memex_projects - memex projects viewer trying to get access to
  # min_permission_level - what permission level we're checking for. Possible values: read, write, admin
  sig { params(viewer: T.nilable(User), memex_projects: T::Array[MemexProject], min_permission_level: T.nilable(T.any(String, Symbol))).returns(Promise[T::Array[MemexProject]]) }
  def self.async_filter_accessible_memexes(viewer, memex_projects, min_permission_level = "read")
    async_accessible_projects = memex_projects.map do |memex_project|
      memex_project.async_accessible(viewer, min_permission_level).then do |accessible|
        next unless accessible
        next memex_project
      end
    end

    Promise.all(async_accessible_projects).then(&:compact)
  end

  sig { params(viewer: User).returns(T::Array[MemexProjectCollaborator]) }
  def collaborators(viewer)
    roles = UserRole.includes(:role).where(actor_type: %w[User Team], target_type: "MemexProject", target: self)

    user_roles, team_roles = roles.partition { |user_role| user_role.actor_type == "User" }

    user_ids = user_roles.map(&:actor_id)
    users_by_id = User.includes(:profile).where(id: user_ids).index_by(&:id)

    team_ids = team_roles.map(&:actor_id)
    teams_by_id = {}

    if org_owned? && team_ids.present?
      visible_team_ids = owner.visible_teams_for(viewer).where(id: team_ids)
      teams_by_id = Team.where(organization: owner, id: visible_team_ids).index_by(&:id)
    end

    roles.map do |role|
      actor = role.actor_type == "User" ? users_by_id[role.actor_id] : teams_by_id[role.actor_id]
      next unless actor
      MemexProjectCollaborator.new(actor, role.role)
    end.compact
  end

  sig { params(actors: T::Array[MemexCollaborator]).returns(T::Array[String]) }
  def remove_collaborators(actors)
    failed = []
    memex_roles = Role.system_project_roles
    actor_type = T.let(nil, T.nilable(String))

    actors.each do |actor|
      if actor.is_a?(Team) && owner.user?
        actor_type = actor.class.to_s.downcase
        failed.push "#{actor_type}/#{actor.id}"
        next
      end

      memex_roles.each do |role|
        begin
          revoke_role(actor, role)
        rescue ArgumentError, Permissions::Granters::RoleGranter::GrantFailure
          actor_type = actor.class.to_s.downcase
          failed.push "#{actor_type}/#{actor.id}"
          break
        end
      end
    end

    failed
  end

  sig { params(actor: MemexCollaborator).returns(T::Array[String]) }
  def remove_collaborator(actor)
    failed = []
    memex_roles = Role.system_project_roles
    actor_type = T.let(nil, T.nilable(String))

    if actor.is_a?(Team) && owner.user?
      actor_type = actor.class.to_s.downcase
      failed.push "#{actor_type}/#{actor.id}"
      return failed
    end

    memex_roles.each do |role|
      begin
        revoke_role(actor, role)
      rescue ArgumentError, Permissions::Granters::RoleGranter::GrantFailure
        actor_type = actor.class.to_s.downcase
        failed.push "#{actor_type}/#{actor.id}"
        break
      end
    end

    failed
  end

  sig { params(is_selected: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
  def to_suggestion_hash(is_selected: false)
    {
      id: id,
      name: name,
      owner: owner.organization? ? owner.safe_profile_name : owner.display_login,
      selected: is_selected,
      template: is_template?,
    }
  end

  sig { params(is_selected: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
  def to_repo_projects_suggestion_hash(is_selected: false)
    {
      number: number,
      name: name,
      owner: owner.organization? ? owner.safe_profile_name : owner.display_login,
      selected: is_selected,
      template: is_template?,
    }
  end

  # Public: Check readability by a given user of a list of memex project items by their ids.
  # This method calls async_readable_by_viewer? for each of the items passed in,
  # and partitions those items into two groups: one that is readable by the viewer, and one that is not.
  #
  # viewer        - The user to perform the ability check for.
  # item_ids      - List of items to include in the ability check.
  #
  # Examples
  #   memex_project.partition_items_by_readability(current_user, [1, 2, 3])
  #
  # Returns the two groups of items, as a two-element array. The first array is viewable items,
  # and the second array is items that cannot be viewed.
  sig { params(viewer: T.nilable(User), item_ids: T::Array[Integer]).returns([T::Array[MemexProjectItem], T::Array[MemexProjectItem]]) }
  def partition_items_by_readability(viewer, item_ids)
    items = memex_project_items.where(id: item_ids)
    viewable_states = Promise.all(items.map { |item| item.async_readable_by_viewer?(viewer) }).sync
    items.partition.with_index { |_, i| viewable_states[i] }
  end

  # Public: Keep track of the last day a MemexProject was visited. Per-user timestamps are available in the
  # MemexProjectVisit model.
  sig { returns(T::Boolean) }
  def update_last_visited_on
    return false if last_visited_on&.today?

    # Skip firing callbacks when updating the last_visited_on timestamp
    update_columns(last_visited_on: Date.current)
  end

  # Public: Upsert a MemexProjectVisit for the given viewer with the current timestamp
  # viewer - The user to upsert a MemexProjectVisit for.
  # Examples
  #   memex_project.update_last_visited_at_for_viewer(viewer: current_user)
  sig { params(viewer: User).void }
  def update_last_visited_at_for_viewer(viewer:)
    update_last_visited_on
    MemexProjectVisit.upsert({
      viewer_id: viewer.id,
      memex_project_id: id,
      last_visited_at: Time.now.utc,
      owner_id: owner_id,
      owner_type: owner_type
    })
  end

  # column ids for serialization purposes, use memex_project_column_ids
  # for `ALL`` project column ids. column_ids excludes columns that are not meant to be
  # serialized as part of the API response according to feature flags.
  sig { returns(T::Array[String]) }
  def column_ids
    hide_hierarchy_fields = !tracks_and_tracked_by_enabled?

    columns.reject { |c| hide_hierarchy_fields && (c.data_type == "tracks" || c.data_type == "tracked_by") }
      .pluck(:id)
  end

  sig { returns(Promise[T::Array[String]]) }
  def async_column_ids
    async_memex_project_columns.then { column_ids }
  end

  sig { returns(Promise[String]) }
  def async_issue_type_column_ids
    async_memex_project_columns.then do |columns|
      columns.select(&:issue_type?).pluck(:id)
    end
  end

  sig { returns(Promise[String]) }
  def async_parent_issue_column_ids
    async_memex_project_columns.then do |columns|
      columns.select(&:parent_issue?).pluck(:id)
    end
  end

  sig { returns(Promise[String]) }
  def async_sub_issues_progress_column_ids
    async_memex_project_columns.then do |columns|
      columns.select(&:sub_issues_progress?).pluck(:id)
    end
  end

  sig { returns(Promise[T::Boolean]) }
  def async_owner_is_enterprise_managed?
    async_owner.then do |owner|
      next false unless owner
      if org_owned?
        T.cast(owner, Organization).async_enterprise_managed_user_enabled?
      elsif user_owned?
        owner.is_enterprise_managed?
      else
        false
      end
    end
  end

  sig { returns(T::Boolean) }
  def owner_is_enterprise_managed?
    org_owned? ? owner.enterprise_managed_user_enabled? : owner.is_enterprise_managed?
  end

  sig { override.params(association: T.nilable(Symbol)).returns(GitHub::Prioritizable::Context::RebalanceMode) }
  def rebalance_mode(association:)
    if association == :memex_project_items
      GitHub::Prioritizable::Context::RebalanceMode::Current
    else
      GitHub::Prioritizable::Context::RebalanceMode::Legacy
    end
  end

  sig { params(actor_display_name: String).returns(T.nilable(MemexProject)) }
  def self.find_with_actor_display_name(actor_display_name)
    owner_type, owner_login, project_number = actor_display_name.split("/")

    owner = case owner_type
    when "User"
      User.find_by_login(owner_login)
    when "Organization"
      Organization.find_by_login(owner_login)
    else
      raise ArgumentError, "Invalid owner type: #{owner_type}"
    end

    owner&.memex_projects&.find_by(number: project_number)
  end

  sig { override.returns(String) }
  def flipper_actor_name
    "#{owner_type}/#{search_slug}"
  end

  sig { override.params(name: String).returns(T.nilable(GitHub::FlipperActor)) }
  def self.from_flipper_actor_name(name)
    MemexProject.find_with_actor_display_name(name)
  end

  sig { params(queue_reindex_project_items_after_create_commit: T::Boolean).returns(MemexProjectColumn) }
  def backfill_issue_type_column(queue_reindex_project_items_after_create_commit: true)
    existing_issue_type_column = columns.find(&:issue_type?)
    return existing_issue_type_column if existing_issue_type_column

    last_position = memex_project_columns.maximum(:position) + 1
    issue_type_column = memex_project_columns.create(
      name: MemexProjectColumn::TYPE_COLUMN_NAME,
      data_type: :issue_type,
      visible: false,
      position: last_position,
      user_defined: false,
      queue_reindex_project_items_after_create_commit:,
    )

    # Make sure to clear the cached value of `columns`.
    reload

    issue_type_column
  end

  sig { params(viewer: T.nilable(User)).returns(T.nilable(T::Hash[Symbol, Float])) }
  def consistency_metrics(viewer: nil)
    return unless viewer&.employee?

    {
      consistency: memex_project_elasticsearch_consistency&.percentage,
      inconsistencyThreshold: MemexProjectElasticsearchConsistency::INCONSISTENCY_THRESHOLD
    }
  end

  sig { returns(T::Boolean) }
  def memex_table_without_limits_or_pwl_public_beta_enabled?
    if owner&.feature_enabled?(:memex_project_without_limits_public_beta, memoize: false)
      !feature_enabled?(:memex_table_without_limits_disabled, memoize: false)
    else
      feature_enabled?(:memex_table_without_limits, memoize: false)
    end
  end

  # Methods required for Entity compatibility
  sig { returns(T::Boolean) }
  def public?
    public
  end

  sig { returns(T::Boolean) }
  def private?
    !public?
  end

  sig { params(user: T.nilable(User)).returns(T::Boolean) }
  def writable_by?(user)
    self.viewer_can_write?(user)
  end

  alias name_with_owner search_slug

  private

  sig { void }
  def creator_has_verified_email
    return unless GitHub.email_verification_enabled?

    return if creator&.bot?

    errors.add(:creator, "must have a verified email address") unless creator&.verified_emails?
  end

  sig { void }
  def default_columns_pending
    # Column names are unique, so determine if all default columns are about to
    # be saved by comparing the set of default column names to the set of
    # pending column names.  This occurs on project creation.
    default_column_names = Set.new(MemexProjectColumn.default_columns(excluding: self.class.excluded_default_columns(creator, owner)).map(&:name))
    pending_column_names = Set.new(memex_project_columns.map(&:name))

    unless pending_column_names >= default_column_names
      errors.add(:base, "Default columns must be saved at the same time")
    end
  end

  sig { params(column: MemexProjectColumn, index: Integer).returns(T::Boolean) }
  def insert_column(column, index)
    columns.insert([index, columns.length].min, column)
    reorder_columns(columns)
  end

  # Reprioritize persisted columns position following the GitHub::Prioritizable API.
  #
  # This method had to be added because the position table column of MemexProjectColumn is currently a tinyint,
  # preventing the usage of GitHub::Prioritizable that expects a column of type bigint.
  #
  # NOTE: this method should be removed in favor of prioritizable once DB migrations are unlocked.
  sig { params(memex_project_column: MemexProjectColumn, options: T.untyped).returns(T::Boolean) }
  def reprioritize_memex_project_columns(memex_project_column, **options)
    reordered_columns = memex_project_columns.where.not(id: memex_project_column.id).to_a

    memex_project_column_index = memex_project_column.position - 1
    if options[:position] == :top
      memex_project_column_index = 0
    elsif options[:after]
      # Determine the index after the target MemexProjectColumn
      memex_project_column_index = T.must(reordered_columns.index(options[:after])) + 1
    end

    # already at the right place, no reprioritization required
    return true if memex_project_column.position == (memex_project_column_index + 1)

    reordered_columns.insert(memex_project_column_index, memex_project_column)

    # note: ideally, the safe_position_delta could be negative (-128), so it wouldn't ever be a situation
    # where the values could overflow. But because the position is required to be positive on validation,
    # that was not a viable strategy.
    max_position = reordered_columns.map(&:position).push(memex_project_column.position).max
    safe_position_delta = max_position + 1
    successfully_updated = T.let(true, T::Boolean)
    MemexProjectColumn.transaction do
      reordered_columns.each_with_index do |column, index|
        next if column.position == (index + 1)

        # Due to a database unique index for positions, when reordering positions, it's required
        # to move each updated column to a position out of the way first to avoid any conflict.
        column.update!(position: index + 1 + safe_position_delta)
      end

      # now it's safe to update each position to its final state
      reordered_columns.each do |column|
        next if column.position < safe_position_delta

        column.update!(position: column.position - safe_position_delta)
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved
      successfully_updated = false
    end

    successfully_updated
  end

  sig { void }
  def enqueue_memex_project_reindex_content_job
    MemexProjectReindexContentJob.perform_later(id)
  end

  sig { void }
  def instrument_creation
    GlobalInstrumenter.instrument("memex_project.create", {
      project: self,
      owner: owner,
      actor: creator || User.ghost,
      action: :create,
    })

    instrument :create, prefix: "project", project_kind: "MemexProject"
  end

  sig { void }
  def instrument_update
    return if self.previous_changes.blank? # `touch` does not dirty the model, no need

    action, legacy_action = if previous_changes.has_key?("public")
      [:update, public ? :visibility_public : :visibility_private]
    elsif previous_changes.has_key?("closed_at")
      [closed? ? :close : :open]
    elsif previous_changes.has_key?("deleted_at")
      [deleted? ? :soft_delete : :restore]
    else
      [:update]
    end

    legacy_action ||= action

    # project_kind: "MemexProject" prevents triggering a legacy project webhook for Memex projects
    instrument legacy_action, prefix: "project", project_kind: "MemexProject"

    GlobalInstrumenter.instrument("memex_project.update", {
      project: self,
      owner: owner,
      actor: actor,
      action: action,
    })
  end

  sig { void }
  def instrument_deletion
    GlobalInstrumenter.instrument("memex_project.delete", {
      project: self,
      owner: owner,
      actor: actor,
      action: :delete,
    })
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def event_payload
    payload = {
      project: self,
      project_name: name,
      actor: actor,
      performed_at: Time.current,
      public_project: public?
    }

    payload[owner.event_prefix] = owner if owner.present?

    payload[:changes] = previous_changes if previous_changes.present?

    payload
  end

  sig { void }
  def projects_enabled
    return unless org_owned?
    unless owner.organization_projects_enabled?
      errors.add(:owner, "has disabled projects for this organization")
    end
  end

  batch_method(:is_template?) do |projects|
    template_project_ids = MemexTemplate.where(memex_project: projects, active: true).pluck(:memex_project_id)

    projects.index_with do |project|
      template_project_ids.any? { |template_project_id| template_project_id == project.id }
    end
  end

  batch_method(:last_project_visit_by_viewer) do |projects, viewer_id|
    last_visits = MemexProjectVisit.where(memex_project_id: projects.map(&:id), viewer_id: viewer_id).group_by(&:memex_project_id)
    projects.index_with { |memex_project| last_visits[memex_project.id]&.maximum(:last_visited_at) }
  end

  sig { params(feature_flag_name: String, block: T.proc.params(id: T.nilable(Integer)).void).void }
  def self.each_project_id_with_feature_flag_enabled(feature_flag_name, &block)
    feature_flag = FlipperFeature.find_by(name: feature_flag_name)
    return yield nil unless feature_flag

    feature_flag.flipper_gates
      .actor_gates(actor_type: "MemexProject")
      .in_batches(of: MEMEX_WITHOUT_LIMITS_PROJECTS_BETA_BATCH_SIZE)
      .each_record do |actor|
        yield T.let(actor.value.partition(":").last.to_i, Integer)
      end
  end
  private_class_method :each_project_id_with_feature_flag_enabled

  sig { params(creator: User, owner: MemexOwner).returns(T::Boolean) }
  def self.create_with_mwl_enabled?(creator, owner)
    return false unless creator.feature_enabled?(:memex_mwl_new_projects)
    return false unless creator.employee?
    return false unless owner.display_login == "github" || owner.display_login == "unicorns-r-us"
    true
  end
  private_class_method :create_with_mwl_enabled?

  # This was a temporary restriction applied while addressing https://github.com/github/memex/issues/16355
  # The GraphQL vulnerability for 'public' projects owned by an EMU enterprise has been fixed and this
  # method and memex_no_public_emu_projects feature flag can most likely be removed soon.
  sig { void }
  private def public_project_is_not_owned_by_emu
    will_become_public = T.must(public_change).second
    if will_become_public && owner_is_enterprise_managed? && GitHub.flipper[:memex_no_public_emu_projects].enabled?
      errors.add(:owner, "cannot own a public project because they are an enterprise-managed user or organization")
    end
  end

  sig { void }
  def destroy_template_project_links
    return unless (memex_template = self.memex_template)
    memex_template.destroy_organization_memex_project_links if self.closed?
  end
end
