# typed: strict
# frozen_string_literal: true

class MemexProjectWorkflowAction < ApplicationRecord::Domain::Memexes

  belongs_to :workflow, inverse_of: :actions, class_name: "MemexProjectWorkflow",
    foreign_key: "memex_project_workflow_id"
  has_one :memex_project, through: :workflow
  has_many :memex_project_columns, through: :memex_project
  belongs_to :creator, class_name: "User"
  belongs_to :last_updater, class_name: "User"

  enum :action_type, {
    set_field: 0,
    get_project_items: 1,
    get_items: 2,
    add_project_item: 3,
    archive_project_item: 4,
    close_item: 5,
    get_sub_issues: 6,
  }

  before_validation :cast_argument_values_to_integers
  before_validation :set_last_updater, on: [:create, :update]

  validates :workflow, presence: true
  validates :creator, presence: true, on: :create
  validates :last_updater, presence: true
  validates :action_type, presence: true
  validates :arguments, presence: true, allow_blank: true

  validates_with MemexProjectWorkflowAction::ArgumentValidator

  ARGUMENT_KEYS_WITH_INTEGER_VALUES = T.let(%w(fieldId), T::Array[String])
  ACTION_PRIORITY = T.let({
    get_project_items: 0,
    get_items: 0,
    get_sub_issues: 0,
    add_project_item: 1,
    archive_project_item: 1,
    set_field: 2,
    close_item: 2,
  }.freeze, T::Hash[Symbol, Integer])

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_hash
    {
      id: id,
      actionType: action_type,
      arguments: arguments,
    }.compact
  end

  sig { params(action: MemexProjectWorkflowAction).returns(T::Boolean) }
  def equal?(action)
    case action.action_type
    when "get_items"
      self.get_items_action_equal?(action)
    else
      self.to_hash.except(:id) == action.to_hash.except(:id)
    end
  end

  sig { returns(T.nilable(MemexProjectColumn)) }
  def memex_project_column
    field_id = arguments["fieldId"]

    if association(:workflow).loaded? && workflow
      return T.must(workflow).project_column_for(field_id)
    end

    memex_project_columns.find_by(id: field_id)
  end

  sig { params(action: MemexProjectWorkflowAction).returns(T::Boolean) }
  private def get_items_action_equal?(action)
    self.arguments["repositoryId"] == action.arguments["repositoryId"] &&
      Search::Memex::QueryParser.equal?(self.arguments["query"], action.arguments["query"])
  end

  sig { void }
  private def cast_argument_values_to_integers
    return if arguments.blank?

    ARGUMENT_KEYS_WITH_INTEGER_VALUES.each do |key|
      arguments[key] = arguments[key].to_i if arguments[key]
    end
  end

  sig { void }
  private def set_last_updater
    self.last_updater = (self.memex_project&.project_migration&.requester || User.ghost) if MemexProject::Migrator.migrating?
    self.last_updater ||= contextual_actor
  end

  sig { returns(User) }
  private def contextual_actor
    User.find_by(id: GitHub.context[:actor_id]) || User.ghost
  end
end
