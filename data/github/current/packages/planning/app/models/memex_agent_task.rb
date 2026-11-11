# typed: true
# frozen_string_literal: true

class MemexAgentTask < ApplicationRecord::Domain::Memexes
  include GitHub::Validations
  include MemexProjectItem::Content
  include ::Repositories::BelongsToRepository

  def platform_type_name
    "AgentTask"
  end
  belongs_to_repository_via_domain

  has_many :memex_project_items,
    -> { where(content_type: "MemexAgentTask") },
    class_name: "MemexProjectItem",
    foreign_key: :content_id,
    inverse_of: :content

  attribute :task_uuid, :uuid_type

  validates :task_uuid, presence: true, uniqueness: true
  validates :owner_id, presence: true
  validates :repository_id, presence: true

  sig { returns(MemexProjectColumn::IDataSource::JSONValue) }
  def memex_denormalized_title_value
    title = "Agent task"
    {
      title: {
        raw: title,
        html: title,
      }
    }
  end

  sig { returns(T::Boolean) }
  def can_have_milestone?
    false
  end

  sig { returns(NilClass) }
  def memex_denormalized_milestone_value
    nil
  end

  # Agent tasks have minimal serializable content — just the ID.
  def memex_content_hash(fields: [])
    { id: id }
  end

  sig { override.returns(Elastomer::Interfaces::Document::MemexProjectItem::Content) }
  def memex_content_elasticsearch_document
    Elastomer::Interfaces::Document::MemexProjectItem::Content.new(
      id: T.must(id),
      type: MemexProjectItem::ContentType::AgentTask,
      state: Elastomer::Interfaces::Document::MemexProjectItem::DraftIssueState::Open,
      state_reason: nil,
      is_draft: false,
      number: nil,
      repository_id: repository_id,
      closed_at: nil,
      created_at: created_at&.iso8601,
    )
  end

  # Find or create an agent task record for a given task UUID.
  # Returns the record, which provides the integer ID
  # that can be used as `content_id` in `memex_project_items`.
  #
  # owner_id and repository_id are required so that the task can later be
  # hydrated via CAPI's tasksByOwnerRepoDB partition key without
  # needing an Issue to derive the repository context.
  sig { params(task_uuid: String, owner_id: Integer, repository_id: Integer).returns(MemexAgentTask) }
  def self.find_or_create_for(task_uuid:, owner_id:, repository_id:)
    find_or_create_by!(task_uuid: task_uuid) do |task|
      task.owner_id = owner_id
      task.repository_id = repository_id
    end
  end

  # Look up an agent task by its integer ID.
  # This is used when loading a memex_project_item's content
  # to resolve the original UUID for external lookup.
  sig { params(id: Integer).returns(T.nilable(MemexAgentTask)) }
  def self.find_task(id)
    find_by(id: id)
  end

  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def readable_by?(actor)
    true
  end
end
