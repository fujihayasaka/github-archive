# typed: strict
# frozen_string_literal: true

class MemexProjectWorkflow < ApplicationRecord::Domain::Memexes
  include GitHub::Validations
  include Sequence::Context
  include MemexProjectWorkflow::WorkflowLimitsDependency
  include GitHub::Memoizer
  extend GitHub::Encoding

  # This value is stored in a varchar(255) column, so account for the space
  # required to store 4-byte characters.
  NAME_CHARACTER_LIMIT = 63

  belongs_to :memex_project, inverse_of: :workflows
  belongs_to :creator, class_name: "User"
  belongs_to :last_updater, class_name: "User"

  has_many :actions, inverse_of: :workflow, class_name: "MemexProjectWorkflowAction", foreign_key: "memex_project_workflow_id"
  destroy_dependents_in_background :actions
  accepts_nested_attributes_for :actions

  enum :trigger_type, {
    closed: 0,
    item_added: 1,
    reopened: 2,
    review_changes_requested: 3,
    review_approved: 4,
    merged: 5,
    query_matched: 6,
    project_item_column_update: 7,
    sub_issues: 8,
  }

  before_validation :set_enabled_to_false_by_default, on: :create
  before_validation :set_number, on: [:create]
  before_validation :set_last_updater, on: [:create, :update]

  validates :memex_project, presence: true
  validates(
    :number,
    presence: true,
    numericality: { only_integer: true, greater_than: 0 },
    uniqueness: { scope: [:memex_project_id] },
    on: :create
  )
  validates :creator, presence: true, on: :create
  validates :last_updater, presence: true
  validates :name, presence: true, length: { maximum: NAME_CHARACTER_LIMIT }
  validates :trigger_type, presence: true
  validates :enabled, inclusion: { in: [true, false], message: "must be true or false" }
  validates :content_types, presence: true
  validate :content_types_are_valid_for_trigger_type
  # When migrating a classic project, we do not check for uniqueness of the workflow name, because this is validated
  # beforehand, so we do not need to check each time a workflow is created.
  validate :name_does_not_exist, unless: -> { MemexProject::Migrator.migrating? }
  validate :matching_workflow_does_not_exist, if: :is_auto_add_workflow?

  validates_with MemexProjectWorkflow::ActionsValidator, if: -> { T.bind(self, MemexProjectWorkflow); actions.any? && !GitHub.flipper[:memex_workflow_actions_validator_kill_switch].enabled? }

  scope :with_trigger_type, ->(trigger_type) { where(trigger_type: trigger_type) }

  CONTENT_TYPE_CONSTRAINTS_BY_TRIGGER_TYPE = T.let({
    closed: [MemexProjectItem::ISSUE_TYPE, MemexProjectItem::PULL_REQUEST_TYPE],
    item_added: [MemexProjectItem::ISSUE_TYPE, MemexProjectItem::PULL_REQUEST_TYPE],
    reopened: [MemexProjectItem::ISSUE_TYPE, MemexProjectItem::PULL_REQUEST_TYPE],
    review_changes_requested: [MemexProjectItem::PULL_REQUEST_TYPE],
    review_approved: [MemexProjectItem::PULL_REQUEST_TYPE],
    merged: [MemexProjectItem::PULL_REQUEST_TYPE],
    query_matched: [MemexProjectItem::ISSUE_TYPE, MemexProjectItem::PULL_REQUEST_TYPE],
    project_item_column_update: [MemexProjectItem::ISSUE_TYPE],
    sub_issues: [MemexProjectItem::ISSUE_TYPE],
  }.freeze, T::Hash[Symbol, T::Array[String]])

  TRIGGER_TYPES_BY_ENABLEMENT = T.let({
    closed: true,
    item_added: true,
    reopened: true,
    review_changes_requested: true,
    review_approved: true,
    merged: true,
    query_matched: true,
    project_item_column_update: true,
    sub_issues: true,
  }.freeze, T::Hash[Symbol, T::Boolean])

  DEFAULT_NAME_BY_TRIGGER_TYPE = T.let({
    closed: "Item closed",
    item_added: "Item added to project",
    reopened: "Item reopened",
    review_changes_requested: "Code changes requested",
    review_approved: "Code review approved",
    merged: "Pull request merged",
    project_item_column_update: "Item field updated",
  }.freeze, T::Hash[Symbol, String])

  ACTIONS_BY_TRIGGER_TYPE = T.let({
    closed: [[:set_field]],
    item_added: [[:set_field]],
    reopened: [[:set_field]],
    review_changes_requested: [[:set_field]],
    review_approved: [[:set_field]],
    merged: [[:set_field]],
    query_matched: [
      [:get_project_items, :archive_project_item],
      [:get_items, :add_project_item]
    ],
    project_item_column_update: [[:get_project_items, :close_item]],
    sub_issues: [[:add_project_item], [:get_sub_issues, :add_project_item]],
  }.freeze, T::Hash[Symbol, T::Array[T::Array[Symbol]]])

  sig do
    params(status_column: MemexProjectColumn, creator: T.nilable(User), enabled: T::Boolean)
      .returns(T::Hash[Symbol, T.untyped])
  end
  def self.default_item_added_workflow_attributes(status_column:, creator:, enabled: false)
    field_option_id = self.get_first_status_column_option(status_column)

    {
      name: "Item added to project",
      trigger_type: :item_added,
      enabled: enabled,
      content_types: %w[Issue PullRequest],
      creator: creator,
      actions_attributes: [
        {
          action_type: :set_field,
          creator: creator,
          arguments: {
            fieldId: status_column.id,
            fieldOptionId: field_option_id,
          }
        }.compact
      ]
    }.compact
  end

  sig do
    params(status_column: MemexProjectColumn, creator: T.nilable(User), enabled: T::Boolean)
      .returns(T::Hash[Symbol, T.untyped])
  end
  def self.default_reopened_workflow_attributes(status_column:, creator:, enabled: false)
    field_option_id = self.get_second_status_column_option(status_column)

    {
      name: DEFAULT_NAME_BY_TRIGGER_TYPE[:reopened],
      trigger_type: :reopened,
      enabled: enabled,
      content_types: %w[Issue PullRequest],
      creator: creator,
      actions_attributes: [
        {
          action_type: :set_field,
          creator: creator,
          arguments: {
            fieldId: status_column.id,
            fieldOptionId: field_option_id,
          }
        }.compact
      ]
    }.compact
  end

  sig do
    params(status_column: MemexProjectColumn, creator: T.nilable(User), enabled: T::Boolean)
      .returns(T::Hash[Symbol, T.untyped])
  end
  def self.default_review_changes_requested_workflow_attributes(status_column:, creator:, enabled: false)
    field_option_id = self.get_second_status_column_option(status_column)

    {
      name: DEFAULT_NAME_BY_TRIGGER_TYPE[:review_changes_requested],
      trigger_type: :review_changes_requested,
      enabled: enabled,
      content_types: ["PullRequest"],
      creator: creator,
      actions_attributes: [
        {
          action_type: :set_field,
          creator: creator,
          arguments: {
            fieldId: status_column.id,
            fieldOptionId: field_option_id,
          }
        }.compact
      ]
    }.compact
  end

  sig do
    params(status_column: MemexProjectColumn, creator: T.nilable(User), enabled: T::Boolean)
      .returns(T::Hash[Symbol, T.untyped])
  end
  def self.default_review_approved_workflow_attributes(status_column:, creator:, enabled: false)
    field_option_id = self.get_second_status_column_option(status_column)

    {
      name: DEFAULT_NAME_BY_TRIGGER_TYPE[:review_approved],
      trigger_type: :review_approved,
      enabled: enabled,
      content_types: ["PullRequest"],
      creator: creator,
      actions_attributes: [
        {
          action_type: :set_field,
          creator: creator,
          arguments: {
            fieldId: status_column.id,
            fieldOptionId: field_option_id,
          }
        }.compact
      ]
    }.compact
  end

  sig do
    params(status_column: MemexProjectColumn, creator: T.nilable(User), enabled: T::Boolean)
      .returns(T::Hash[Symbol, T.untyped])
  end
  def self.default_closed_workflow_attributes(status_column:, creator:, enabled: false)
    field_option_id = self.get_last_status_column_option(status_column)

    {
      name: DEFAULT_NAME_BY_TRIGGER_TYPE[:closed],
      trigger_type: :closed,
      enabled: enabled,
      content_types: %w[Issue PullRequest],
      creator: creator,
      actions_attributes: [
        {
          action_type: :set_field,
          creator: creator,
          arguments: {
            fieldId: status_column.id,
            fieldOptionId: field_option_id,
          }
        }.compact
      ]
    }.compact
  end

  sig do
    params(status_column: MemexProjectColumn, creator: T.nilable(User), enabled: T::Boolean)
      .returns(T::Hash[Symbol, T.untyped])
  end
  def self.default_merged_workflow_attributes(status_column:, creator:, enabled: false)
    field_option_id = self.get_last_status_column_option(status_column)

    {
      name: DEFAULT_NAME_BY_TRIGGER_TYPE[:merged],
      trigger_type: :merged,
      enabled: enabled,
      content_types: ["PullRequest"],
      creator: creator,
      actions_attributes: [
        {
          action_type: :set_field,
          creator: creator,
          arguments: {
            fieldId: status_column.id,
            fieldOptionId: field_option_id,
          }
        }.compact
      ]
    }.compact
  end

  sig { params(creator: T.nilable(User), enabled: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
  def self.default_auto_archive_workflow_attributes(creator:, enabled: false)
    {
      name: "Auto-archive items",
      trigger_type: :query_matched,
      enabled: enabled,
      content_types: ["Issue"],
      creator: creator,
      actions_attributes: [
        {
          action_type: :get_project_items,
          creator: creator,
          arguments: { query: "is:closed updated:<@today-2w" }
        }.compact,
        {
          action_type: :archive_project_item,
          creator: creator,
          arguments: {}
        }.compact
      ]
    }.compact
  end

  sig do
    params(creator: T.nilable(User), repository: T.nilable(Repository), enabled: T::Boolean)
      .returns(T::Hash[Symbol, T.untyped])
  end
  def self.default_auto_add_workflow_attributes(creator:, repository: nil, enabled: false)
    {
      name: "Auto-add to project",
      trigger_type: :query_matched,
      enabled: enabled,
      content_types: %w[Issue PullRequest],
      creator: creator,
      actions_attributes: [
        {
          action_type: :get_items,
          creator: creator,
          arguments: {
            query: "is:issue,pr is:open label:bug",
            repositoryId: repository&.id
          }
        }.compact,
        {
          action_type: :add_project_item,
          creator: creator,
          arguments: {
            repositoryId: repository&.id
          }
        }.compact
      ]
    }.compact
  end

  sig { params(status_column: MemexProjectColumn, creator: T.nilable(User), enabled: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
  def self.default_auto_close_workflow_attributes(status_column:, creator:, enabled: false)
    field_option_id = self.get_last_status_column_option(status_column)

    {
      name: "Auto-close issue",
      trigger_type: :project_item_column_update,
      enabled: enabled,
      content_types: ["Issue"],
      creator: creator,
      actions_attributes: [
        {
          action_type: :get_project_items,
          creator: creator,
          arguments: {
            fieldId: status_column.id,
            fieldOptionId: field_option_id
          }
        }.compact,
        {
          action_type: :close_item,
          creator: creator,
          arguments: {}
        }.compact
      ]
    }.compact
  end

  sig do
    params(creator: T.nilable(User), enabled: T::Boolean)
      .returns(T::Hash[Symbol, T.untyped])
  end
  def self.default_sub_issues_workflow_attributes(creator:, enabled: false)
    {
      name: "Auto-add sub-issues to project",
      trigger_type: :sub_issues,
      enabled: enabled,
      content_types: %w[Issue],
      creator: creator,
      actions_attributes: [
        {
          action_type: :get_sub_issues,
          creator: creator,
          arguments: {}
        }.compact,
        {
          action_type: :add_project_item,
          creator: creator,
          arguments: {
            subIssue: true
          }
        }.compact
      ]
    }.compact
  end

  sig { params(trigger_type: Symbol).returns(T.nilable(T::Array[String])) }
  def self.get_valid_content_types_for_trigger_type(trigger_type)
    CONTENT_TYPE_CONSTRAINTS_BY_TRIGGER_TYPE[trigger_type]
  end

  sig { params(trigger_type: Symbol, actor: T.nilable(User)).returns(T::Boolean) }
  def self.trigger_type_is_enableable(trigger_type, actor)
    T.must(TRIGGER_TYPES_BY_ENABLEMENT[trigger_type])
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_hash
    # Use the trigger type as a pseudo-ID if the object doesn't otherwise have an ID. This is useful
    # for default worklows (which are constructed from MemexProject#default_workflows). Using
    # trigger_type as an ID for default workflows should not result in conflicts because only have
    # one default workflow per trigger type. Overall, assigning a pseudo-ID makes it easier for
    # clients to work with default workflow objects.
    serialized_id = id || "#{trigger_type}_#{actions.last&.action_type}"

    {
      id: serialized_id,
      name: name,
      number: number,
      triggerType: trigger_type,
      contentTypes: content_types,
      enabled: enabled,
      actions: actions.map(&:to_hash),
    }.compact
  end

  # Override ApplicationRecord::Base#reset_memoized_attributes to make sure that we clear memoization variables
  # on reload.
  sig { void }
  def reset_memoized_attributes
    remove_instance_variable(:@creation_limit) if defined?(@creation_limit)
  end

  sig { returns(String) }
  def sequence_context_type
    T.must(self.class.name)
  end

  sig { returns(T.nilable(Integer)) }
  def sequence_context_id
    memex_project_id
  end

  sig { returns(T::Boolean) }
  def actions_valid?
    return false unless actions.present?
    return false unless (type = trigger_type)

    key = type.to_sym
    all_default_actions = ACTIONS_BY_TRIGGER_TYPE[key]
    # If there are no matching actions for the trigger type, it's not valid.
    return false if !all_default_actions
    # If there are duplicate actions, it's not valid.
    return false if actions.size != actions.map(&:action_type).uniq.count
    # If the workflow actions don't match any of the default actions for the trigger type, it's not valid.
    all_default_actions.any? do |default_actions|
      default_actions.count == actions.size && actions.all? { |action| default_actions.include?(action.action_type.to_sym) }
    end
  end

  sig { returns(String) }
  def platform_type_name
    "ProjectV2Workflow"
  end

  sig { returns(T::Boolean) }
  def allow_manual_run?
    manually_runable_workflows = [is_archive_workflow?, is_sub_issues_workflow?]
    manually_runable_workflows.any?
  end

  sig { returns(T::Boolean) }
  def is_auto_add_workflow?
    trigger_type == "query_matched" &&
      actions.any? { |action| action.action_type == "add_project_item" }
  end

  sig { returns(T::Boolean) }
  def is_archive_workflow?
    trigger_type == "query_matched" && T.must(actions.last).action_type == "archive_project_item"
  end

  sig { returns(T::Boolean) }
  def is_sub_issues_workflow?
    trigger_type == "sub_issues"
  end

  sig { returns(T::Array[MemexProjectWorkflowAction]) }
  def sorted_actions
    actions.sort_by do |action|
      action_priority_for(action)
    end
  end

  sig { params(action: MemexProjectWorkflowAction).returns(Integer) }
  def action_priority_for(action)
    # If the action type is not in the priority hash, default to 100.
    MemexProjectWorkflowAction::ACTION_PRIORITY[action.action_type.to_sym] || 100
  end

  sig { params(field_id: T.nilable(Integer)).returns(T.nilable(MemexProjectColumn)) }
  def project_column_for(field_id)
    return unless field_id
    memex_project&.columns&.detect { |column| column.id == field_id }
  end

  sig { void }
  private def set_number
    return if self.number
    return unless memex_project

    Sequence.create(self, self.class.where(memex_project_id: memex_project_id).maximum(:number) || 0) unless Sequence.exists?(self)
    self.number = Sequence.next(self)
  end

  sig { void }
  private def set_enabled_to_false_by_default
    self.enabled = false if self.enabled.nil?
  end

  sig { returns(User) }
  private def set_last_updater
    self.last_updater = (self.memex_project&.project_migration&.requester || User.ghost) if MemexProject::Migrator.migrating?
    self.last_updater ||= contextual_actor
  end

  sig { returns(User) }
  private def contextual_actor
    User.find_by(id: GitHub.context[:actor_id]) || User.ghost
  end

  sig { void }
  private def content_types_are_valid_for_trigger_type
    return unless (type = trigger_type)
    return unless content_types.present?

    key = type.to_sym

    if !CONTENT_TYPE_CONSTRAINTS_BY_TRIGGER_TYPE.key?(key)
      raise NotImplementedError.new(
        "content type validation has not been implemented for #{key} trigger"
      )
    end

    valid_content_types = CONTENT_TYPE_CONSTRAINTS_BY_TRIGGER_TYPE[key]
    invalid_content_types = content_types - valid_content_types

    if invalid_content_types.any?
      errors.add(:content_types, "contains invalid value(s): #{invalid_content_types.join(", ")}")
    end
  end

  sig { void }
  private def matching_workflow_does_not_exist
    return unless (project = memex_project)
    project.workflows.includes(:actions).where.not(id: id).each do |workflow|
      next false if workflow.actions.empty?

      equal = workflow.sorted_actions.zip(sorted_actions).map do |workflow_action, action|
        workflow_action.nil? || action.nil? ? false : workflow_action.equal?(action)
      end.all?

      if equal
        errors.add(:base, "The \"#{workflow.name}\" workflow already matches this query and repository")
      end
    end
  end

  sig { void }
  private def name_does_not_exist
    return unless (project = memex_project)
    if project.workflows.where.not(id: id).find_by(name: name)
      errors.add(:base, "A workflow with the name \"#{name}\" already exists")
    end
  end

  sig { params(status_column: MemexProjectColumn).returns(String) }
  def self.get_first_status_column_option(status_column)
    self.get_status_column_option_id_by_index(status_column, 0)
  end

  sig { params(status_column: MemexProjectColumn).returns(String) }
  def self.get_last_status_column_option(status_column)
    self.get_status_column_option_id_by_index(status_column, -1)
  end

  sig { params(status_column: MemexProjectColumn).returns(String) }
  def self.get_second_status_column_option(status_column)
    begin
      self.get_status_column_option_id_by_index(status_column, 1)
    rescue ArgumentError
      self.get_status_column_option_id_by_index(status_column, 0)
    end
  end

  sig { params(status_column: MemexProjectColumn, index: Integer).returns(String) }
  def self.get_status_column_option_id_by_index(status_column, index)
    field_option_id = status_column.settings_options[index]&.fetch("id", nil)
    raise ArgumentError, "Status column must have at least one option" unless field_option_id
    field_option_id
  end

  private_class_method :get_first_status_column_option
  private_class_method :get_last_status_column_option
  private_class_method :get_second_status_column_option
  private_class_method :get_status_column_option_id_by_index
end
