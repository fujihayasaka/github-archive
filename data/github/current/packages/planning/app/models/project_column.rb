# typed: false
# frozen_string_literal: true

require "terminal-table"

class ProjectColumn < ApplicationRecord::Domain::Projects
  include GitHub::Prioritizable::Context
  include GitHub::Relay::GlobalIdentification
  include Instrumentation::Model
  include Project::AuthorizerDependency
  include ProjectColumn::MigrationDependency
  include GitHub::UTF8
  include LegacyImportable
  include GitHub::Tracing

  include ProjectColumn::LegacySortingOverridesDependency

  MAX_CARDS = 2500

  PURPOSE_TODO = "todo".freeze
  PURPOSE_IN_PROGRESS = "in_progress".freeze
  PURPOSE_DONE = "done".freeze

  PURPOSES = [
    PURPOSE_TODO,
    PURPOSE_IN_PROGRESS,
    PURPOSE_DONE,
  ].freeze

  belongs_to :project, inverse_of: :columns, touch: true
  has_many :cards,
    inverse_of: :column,
    class_name: "ProjectCard",
    foreign_key: :column_id
  prioritizes :cards, with: :cards

  has_many :project_workflows, dependent: :destroy

  destroy_dependents_in_background :cards

  validates :name, presence: true,
    uniqueness: { scope: :project_id },
    length: { maximum: 140 }
  validates :project, presence: true
  validates :position, presence: true, uniqueness: { scope: :project_id }
  validate :actor_can_modify_projects, unless: :importing?
  validate :max_columns_per_project, on: :create
  validates_inclusion_of :purpose, in: PURPOSES, allow_nil: true

  before_validation :set_position!, on: :create
  after_destroy :update_sibling_positions
  after_save :notify_project, if: :saved_change_to_name?, unless: :importing?

  after_commit :instrument_creation, on: :create
  after_commit :instrument_update, on: :update
  before_destroy :generate_webhook_payload
  after_commit :queue_webhook_delivery, :instrument_deletion, on: :destroy
  after_commit :synchronize_search_index

  attribute :name, StringFromBinary.new

  trace_method :prioritize_dependent!, span_attribute_extractor: -> (context, *args, **kwargs) { context.trace_tags(*args, **kwargs) }

  def inspect
    rows = Array.new.tap do |table|
      cards.includes(:creator).by_priority.each do |card|
        table << [card.id,
                  card.created_at,
                  card.creator,
                  card.content_type,
                  card.content_id,
                  card.priority]
      end
    end

    title = if project = async_project.sync
      %Q[Project "#{project.name}" Column "#{name}"]
    else
      %Q[Deleted project Column "#{name}"]
    end

    card_table = Terminal::Table.new(
      title: title,
      headings: ["Card ID", "Created", "Card Creator", "Content Type", "Content ID", "Priority"],
      rows: rows,
    )

    super + "\n\n" + card_table.render
  end

  def ordered_cards_for(viewer)
    scope = cards.by_priority

    scope = if block_given?
      yield(scope)
    else
      scope.not_archived
    end

    ProjectCard.redact_and_prefill(viewer, project, scope)
  end

  def note_cards
    cards.where(content_id: nil)
  end

  def issue_cards
    cards.where(content_type: "Issue")
  end

  def cards_count_project_column_view
    cards_ids_without_disabled_repo_issues(cards.not_archived).count
  end

  def cards_ids_without_disabled_repo_issues(all_cards)
    all_cards = cards if all_cards.nil?
    issue_ids = issue_cards.pluck :content_id
    repo_ids = Issue.where(id: issue_ids).where(has_pull_request: false).pluck :repository_id
    repo_ids = Repository.where(id: repo_ids).where(has_issues: false).pluck :id
    excluded_issue_ids = Issue.where(id: issue_ids).where("has_pull_request = false AND repository_id IN (?)", repo_ids).pluck :id
    all_cards.reject { |card| card.content_type == "Issue" && excluded_issue_ids.include?(card.content_id) }.pluck(:id)
  end

  # Public: Cursor based pagination for the cards in this column
  #
  # viewer - the User who is viewing the cards. This lets us redact
  # after - The last Card ID before the list of cards we want
  #
  # Returns a hash with values :cards and :next_after (for figuring out
  # the next page)
  def paginated_ordered_cards_for(viewer, after:)
    GitHub.dogstats.distribution_time "project_column.dist.time", tags: ["action:paginated_ordered_cards_for"] do
      card_ids = cards_ids_without_disabled_repo_issues(cards.not_archived.by_priority)


      start = if after.present?
        card_ids.index(after.to_i)&.next
      else
        0
      end

      # a cursor was provided, but it's no longer present in the column
      return { cards: [], next_after: nil } unless start.present?

      paginated_ordered_card_ids = card_ids[start, ProjectCard::PER_PAGE]
      paginated_ordered_cards = cards_by_id(paginated_ordered_card_ids)

      paginated_ordered_cards = ProjectCardRedactor.new(viewer, paginated_ordered_cards).cards
      paginated_ordered_cards = ProjectCardPrefiller.new(project, paginated_ordered_cards, viewer: viewer).cards

      has_more_pages = card_ids[start + ProjectCard::PER_PAGE].present?

      {
        cards: paginated_ordered_cards,
        next_after: (has_more_pages && paginated_ordered_card_ids.last),
      }
    end
  end

  # reindex the project in elastic search
  def synchronize_search_index
    project&.synchronize_search_index
  end

  def notify_project
    project.notify_subscribers(action: "column_updated", message: "#{name} was updated")
  end

  def as_json(*)
    json_payload = {
      id: id,
      name: name,
      card_ids: cards.not_archived.by_priority.pluck(:id),
    }

    json_payload[:purpose] = purpose_label
    json_payload[:automation_summary] = automation_summary
    json_payload
  end

  def trigger_moved_hook(after_column)
    after_column_id = after_column.id if after_column.present?
    instrument :move, after_id: after_column_id
  end

  def event_context(prefix: event_prefix)
    {
      prefix => name,
      "#{prefix}_id".to_sym => id,
    }
  end

  def async_url(suffix = "", params = {})
    async_project.then do |project|
      project.async_url("/columns/{id}#{suffix}", id: id)
    end
  end

  # Locks the project & enqueues a job to bulk archive all of column's cards
  #
  def archive_all_cards(actor:)
    return unless project.writable_by?(actor)

    project.lock!(lock_type: Project::ProjectLock::CARD_ARCHIVING, actor: actor)
    ArchiveAllCardsInProjectColumnJob.perform_later(id, **{ queued_at: Time.current.to_s })

    GitHub.dogstats.increment("projects.archive_all_cards", tags: ["column_purpose:#{purpose}"])
  end

  def get_cards_batch(timestamp: current_time_from_proper_timezone.to_s, offset_item_id: 0, batch_size: 100)
    raise Project::CardArchivingLockRequired unless project.locked_for?(Project::ProjectLock::CARD_ARCHIVING)
    cards.not_archived.created_before(timestamp.to_time).order(:id).where("id > ?", offset_item_id).limit(batch_size)
  end

  # Warning! Danger zone!
  # This method should be called from a background job after locking the project.
  # If you look up at #archive_all_cards, you will find what you're looking for :)
  def archive_cards_batch!(records)
    raise Project::CardArchivingLockRequired unless project.locked_for?(Project::ProjectLock::CARD_ARCHIVING)
    ActiveRecord::Base.connected_to(role: :reading) do
      record_batch_size records

      records.each do |card|
        card.throttle_writes do
          card.archive
        end
      end
    end
  end

  # Warning! Danger zone!
  # This method should be called from a background job after locking the project.
  # If you look up at #archive_all_cards, you will find what you're looking for :)
  # timestamp is needed to skip archiving the cards which were added after the archiving is triggered (for a long-running process)
  #
  # TODO: remove this method after the job is deployed and spent some time in prod. See also app/jobs/archive_all_cards_in_project_column_job.rb
  #
  def archive_all_cards_in_batches!(timestamp: current_time_from_proper_timezone.to_s, from_id: 0, batch_size: 100)
    raise Project::CardArchivingLockRequired unless project.locked_for?(Project::ProjectLock::CARD_ARCHIVING)
    records = get_cards_batch(timestamp: timestamp, offset_item_id: from_id, batch_size: batch_size)
    all_cards_processed = records.size < batch_size

    #return early if no cards to be archived found
    if records.size == 0
      return false
    end

    # log the total amount of cards to be archived once
    record_total_count cards.not_archived if from_id == 0
    record_batch_size records

    max_id = records.ids.max
    archive_cards_batch! records

    # if there are more cards to process, return the id to start from in the next batch.
    # otherwise return `false` to signal end of operation
    all_cards_processed ? false : max_id
  end

  def record_total_count(records)
    GitHub.dogstats.histogram("projects.archive_all_cards_count", records.count, tags: ["column_purpose:#{purpose}"])
  end

  def record_batch_size(records)
    GitHub.dogstats.histogram("projects.archive_all_cards_batch_size", records.size, tags: ["column_purpose:#{purpose}"])
  end

  # Implement GitHub::Prioritizable::Context#rebalance_job_class
  def rebalance_job_class(association: nil)
    RebalanceProjectColumnJob
  end

  # Public: Determines whether the column can be considered a "Done" column.
  #
  # A column with any workflows triggered by the DONE_TRIGGERS is considered
  # to be a column where users store "completed" cards.
  #
  # Returns a Boolean
  def automated_with_done_triggers?
    return false unless project_workflows.exists?
    (project_workflows.pluck(:trigger_type) & ProjectWorkflow::DONE_TRIGGERS).any?
  end

  private

  def max_columns_per_project
    if project.columns.count >= Project::MAX_COLUMNS
      errors.add(:max_columns, "can only create #{Project::MAX_COLUMNS} columns per project")
    end
  end

  def set_position!
    self.position = project.columns.lock.count
  end

  def update_sibling_positions
    project&.reset_column_positions
  end

  # The user who performed the action as set in the GitHub request context. If
  # the context doesn't contain an actor, fallback to the ghost user.
  def modifying_user
    @modifying_user ||= (User.find_by_id(GitHub.context[:actor_id]) || User.ghost)
  end

  def event_payload
    payload = {
      actor: modifying_user,
      project_column: self,
      project: project,
      rank: 2,
    }
  end

  def instrument_creation
    instrument :create
  end

  def instrument_update
    return if previous_changes.empty?

    changes_payload = {}.tap do |hash|
      if name_actually_changed?
        hash[:old_name] = previous_changes["name"].first
        hash[:name] = name
      end
      if previous_changes["purpose"].present?
        hash[:old_purpose] = previous_changes["purpose"].first
        hash[:purpose] = purpose
      end
    end

    return if changes_payload.empty?

    instrument :update, changes: changes_payload
  end

  def name_actually_changed?
    return unless previous_changes["name"].present? && previous_changes["name"].first.present?

    old_name = utf8(previous_changes["name"].first)

    old_name != name
  end

  def instrument_deletion
    instrument :delete
  end

  # Private: Serializes this ProjectColumn as a webhook payload for any apps
  # that listen for Hook::Event::ProjectColumnEvents. Under normal circumstances
  # we deliver webhook events using instrumentation, but this must be called as
  # a before_destroy and uses Hook::Event#generate_payload_and_deliver_later to
  # serialize the webhook payload before the record becomes unavailable.
  #
  # Returns nothing.
  def generate_webhook_payload
    if modifying_user&.spammy?
      @delivery_system = nil
      return
    end

    event = Hook::Event::ProjectColumnEvent.new(action: :deleted, project_column_id: id, actor_id: modifying_user.id, triggered_at: Time.now)
    @delivery_system = Hook::DeliverySystem.new(event)
    @delivery_system.generate_hookshot_payloads
  end

  # Private: Queue the payloads generated above for delivery to Hookshot.
  def queue_webhook_delivery
    unless defined?(@delivery_system)
      raise "`generate_webhook_payload' must be called before `queue_webhook_delivery'"
    end

    @delivery_system&.deliver_later
  end

  def purpose_label
    if purpose == "todo"
      "To do"
    else
      purpose&.humanize
    end
  end

  def automation_summary
    trigger_types = project_workflows.collect(&:trigger_type)

    return "" unless trigger_types

    trigger_types.map do |trigger_type|
      ProjectWorkflow.workflow_description(trigger_type.downcase)
    end.to_sentence.capitalize
  end
end
