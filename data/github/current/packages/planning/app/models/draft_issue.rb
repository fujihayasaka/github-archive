# typed: true
# frozen_string_literal: true

class DraftIssue < ApplicationRecord::Domain::Memexes

  include ContextualActor
  include GitHub::Validations
  include GitHub::UserContent
  include MemexProjectItem::Content
  include Instrumentation::Model
  include DraftIssue::AssignmentDependency
  include Storage::UserAssetTransfer::SavedReplyCopyDependency

  TITLE_BYTESIZE_LIMIT = 1024
  ON_UPDATE_INSTRUMENTATION_KEY = "draft_issue.update"

  attribute :title, StringFromBinary.new

  belongs_to :memex_project_item, touch: true

  setup_attachments

  def entity = memex_project
  def async_entity = async_memex_project

  has_many(
    :assignments,
    -> { where(target_type: "DraftIssue") },
    class_name: "DraftIssueAssignment",
    as: :target
  )
  has_many(
    :assignees,
    through: :assignments,
    disable_joins: true,
    source: :assignee,

    # Although we _also_ implement this behaviour using destroy callbacks on the `DraftIssueAssignment` model,
    # we need to implement it here too because Rails does not invoke destroy callbacks when we edit assignees
    # via this relation with something like `draft_issue.assignees.delete(user)`. That's a common way to edit
    # assignees, so we need to support webhooks for that use case.
    before_remove: :generate_unassigned_webhook_payload,
    after_remove: [:queue_unassigned_webhook_delivery, :instrument_destroy_event_for_hydro]
  )
  destroy_dependents_in_background :assignments

  validates :memex_project_item, presence: true, on: :create
  validates :title, presence: true, allow_nil: false
  validates :title, bytesize: { maximum: TITLE_BYTESIZE_LIMIT }, unicode: true
  validates :body, bytesize: { maximum: MYSQL_UNICODE_BLOB_LIMIT }, unicode: true

  after_commit :instrument_update_event, on: :update
  after_commit :instrument_update_event_for_hydro, on: :update
  # TODO: Switch to `attach_matching_assets` when removing feature flag
  after_commit :attach_matching_draft_issue_assets, on: :update # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  attribute :body, CompressedString.new(self.name, "body")

  delegate :creator, :async_creator, to: :memex_project_item
  delegate :memex_project, :async_memex_project, to: :memex_project_item

  MEMEX_CONTENT_HASH_FIELD_MAP = {
    body: :body,
    body_html: :body_html,
    created_at: :created_at,
    updated_at: :updated_at,
    user: :user_memex_content_hash,
  }.freeze

  # Disable the default behavior of attaching assets in `after_save` defined in `setup_attachments`.
  # We want to call it outside of the transaction in `after_commit` instead.
  def attach_matching_assets?
    false
  end

  def attach_matching_assets_in_background?
    true
  end

  # TODO: Remove this method when removing the feature flag
  def attach_matching_draft_issue_assets
    if GitHub.flipper[:draft_issue_attachment_scanning].enabled?
      attach_matching_assets
    end
  end

  # Implements MemexProjectItem::Content#memex_content_hash.
  def memex_content_hash(fields: [])
    content = { id: id }

    fields.each_with_object({ id: id }) do |field, result|
      method = MEMEX_CONTENT_HASH_FIELD_MAP[field]
      next unless method.present? && respond_to?(method)
      result[field] = if field == :body_html
        public_send(method, context: markdown_context)
      else
        public_send(method)
      end
    end
  end

  def user_memex_content_hash
    user_or_ghost = creator || User.ghost
    user_or_ghost.memex_column_hash
  end

  # Implements MemexProjectItem::Content#memex_denormalized_title_value.
  sig { returns(MemexProjectColumn::Interface::Serializable::JSONValue) }
  def memex_denormalized_title_value
    {
      title: {
        raw: title,
        html: GitHub::Goomba::TitleMarkdownFilter.call(title),
      }
    }
  end

  # Implements MemexProjectItem::Content#can_have_milestone?
  def can_have_milestone?
    false
  end

  # Implements MemexProjectItem::Content#memex_denormalized_milestone_value.
  def memex_denormalized_milestone_value
    # DraftIssues cannot be associated with milestones.
    nil
  end

  def writable_by?(user)
    memex_project_item&.memex_project&.viewer_can_write?(user)
  end

  def async_editable_by?(user)
    Promise.resolve(memex_project_item&.memex_project&.viewer_can_write?(user))
  end

  def draft?
    true
  end

  def pull_request?
    false
  end

  def open?
    true
  end

  def closed?
    false
  end

  def safe_actor
    @actor ||= User.find_by(id: GitHub.context[:actor_id]) || User.ghost
  end

  # Only issues may be converted to a hierarchy_model
  def to_hierarchy_model
    raise NotImplementedError
  end
  alias_method :to_hierarchy_model_key, :to_hierarchy_model

  def unassigned_webhook_event_payload
    organization_id = memex_project_item&.memex_project&.organization_owner_id
    return unless organization_id

    assignees_column_id = memex_project_item&.memex_project&.columns&.find(&:assignees?)&.id
    {
      action: :edited,
      actor_id: actor.id,
      memex_project_item_id: memex_project_item_id,
      changed_field_id: assignees_column_id,
      organization_id: organization_id,
    }
  end

  def event_payload
    organization_id = memex_project_item&.memex_project&.organization_owner_id
    return unless organization_id

    {
      actor_id: actor.id,
      memex_project_item_id: memex_project_item_id,
      organization_id: organization_id,
      changes: self.previous_changes,
    }
  end

  sig { override.returns(Elastomer::Interfaces::Document::MemexProjectItem::Content) }
  def memex_content_elasticsearch_document
    Elastomer::Interfaces::Document::MemexProjectItem::Content.new(
      id: T.must(id),
      type: Elastomer::Interfaces::Document::MemexProjectItem::ContentType::DraftIssue,
      state: Elastomer::Interfaces::Document::MemexProjectItem::DraftIssueState::Open,
      state_reason: nil,
      is_draft: true,
      number: nil,
      closed_at: nil,
      created_at: created_at&.iso8601,
    )
  end

  def hydro_assignee_payload
    {
      actor: safe_actor,
      draft_issue: self,
      memex_project: memex_project,
      memex_project_item: memex_project_item,
      assignees: assignees,
      request_context: GitHub.context.to_hash
    }
  end

  def hydro_update_payload
    previous_title = previous_changes[:title].present? ? previous_changes[:title].first : title
    previous_body = previous_changes[:body].present? ? previous_changes[:body].first : body
    return if previous_title == title && previous_body == body

    {
      actor: safe_actor,
      draft_issue: self,
      project: memex_project,
      project_item: memex_project_item,
      body: self.body,
      previous_body: previous_body,
      title: self.title,
      previous_title: previous_title,
      request_context: GitHub.context.to_hash
    }
  end

  def set_current_user(user)
    @current_user = user
  end

  private def generate_unassigned_webhook_payload(_assignee)
    return unless (complete_payload = unassigned_webhook_event_payload)

    future_webhook_deliveries << (
      Hook::DeliverySystem
        .new(Hook::Event::ProjectsV2ItemEvent.new(**complete_payload))
        .tap(&:generate_hookshot_payloads)
    )
  end

  private def queue_unassigned_webhook_delivery(_assignee)
    future_webhook_deliveries.map(&:deliver_later)
    future_webhook_deliveries.clear
  end

  private def future_webhook_deliveries
    return @future_webhook_deliveries if defined?(@future_webhook_deliveries)
    @future_webhook_deliveries = []
  end

  private def instrument_update_event
    return unless (complete_payload = event_payload)
    instrument(:update)
  end

  private def instrument_update_event_for_hydro
    return unless payload = hydro_update_payload
    GlobalInstrumenter.instrument(ON_UPDATE_INSTRUMENTATION_KEY, payload)
  end

  private

  def markdown_context
    {
      memex_project: memex_project_item&.memex_project,
      current_user: @current_user,
      unfurl_references: true
    }.compact
  end

  def title_column?(column)
    column.name == MemexProjectColumn::TITLE_COLUMN_NAME
  end

  def assignees_column?(column)
    column.name == MemexProjectColumn::ASSIGNEES_COLUMN_NAME
  end

  def instrument_destroy_event_for_hydro(previous_assignee)
    GlobalInstrumenter.instrument(DraftIssueAssignment::ON_DESTROY_INSTRUMENTATION_KEY,
      hydro_assignee_payload.merge(
        previous_assignee: previous_assignee
      )
    )
  end

  def saved_reply_copy_target
    self.memex_project
  end
end
