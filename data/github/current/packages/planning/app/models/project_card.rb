# typed: false
# frozen_string_literal: true

class ProjectCard < ApplicationRecord::Domain::Projects
  include GitHub::Relay::GlobalIdentification
  include Instrumentation::Model
  include GitHub::Prioritizable
  include Project::AuthorizerDependency
  include LegacyImportable
  include PreloadableAttributes
  include ProjectCard::MigrationDependency

  attr_writer :passed_redaction, :show_activity

  MAX_NOTE_LENGTH = 1024
  PENDING_LIMIT = 50
  PER_PAGE = 25

  attr_preloadable :url

  belongs_to :project, inverse_of: :cards
  belongs_to :creator, class_name: "User"
  belongs_to :column, class_name: "ProjectColumn", inverse_of: :cards, touch: true
  belongs_to :content, polymorphic: true

  prioritizable_by subject: :content, context: :column

  validates :project, presence: true
  validates :creator, presence: true, on: :create
  validates :priority,
    numericality: {
      less_than_or_equal_to: GitHub::Prioritizable::MAX_PRIORITY_VALUE,
      greater_than_or_equal_to: 0,
      allow_nil: true,
    }
  validates :note,
    length: { maximum: MAX_NOTE_LENGTH, allow_nil: true },
    presence: { if: proc { |card| card.content.blank? } } # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  validates :project_id,
    uniqueness: {
      scope: [:content_id, :content_type],
      message: "already has the associated issue",
    },
    unless: proc { |card| card.content.blank? }
  validates :archived_at, absence: true, if: :pending?
  validate :max_cards_per_column, if: :added_to_column?
  validate :actor_can_modify_projects, unless: :importing?

  before_validation :set_project, on: :create
  after_save :notify_subscribers, unless: :importing?

  before_destroy :generate_webhook_payload, unless: :spammy?
  before_destroy :track_deletion, unless: :spammy?

  # Important note: after_commit callbacks that you want to be run on create
  # must be manually added to the run_after_commit_on_create_callbacks method.
  after_commit :run_after_commit_on_create_callbacks, on: :create
  after_commit :trigger_issue_removed_from_project_event,
               unless: proc { spammy? || importing? },
               on: :destroy
  after_commit :instrument_update, on: :update
  after_commit :queue_webhook_delivery, if: :should_instrument_delete?, on: :destroy
  after_commit :instrument_deletion, on: :destroy, if: :should_instrument_delete?
  after_commit :notify_content_subscribers, unless: :importing?
  after_commit :synchronize_search_index
  after_commit :synchronize_content_search_index_check, on: [:update, :destroy]

  attribute :note, StringFromBinary.new

  scope :archived, -> { where("archived_at IS NOT NULL") }
  scope :notes, -> { where(content_type: nil, content_id: nil).where("note IS NOT NULL") }
  scope :for_content, -> (content) { where(content_type: content.class.name, content_id: content.id) }
  scope :for_content_type, -> (content_type) { where(content_type: content_type) }
  scope :in_column, -> { where("column_id IS NOT NULL") }
  scope :pending, -> { where(column_id: nil) }
  scope :not_archived, -> { where(archived_at: nil) }
  scope :created_before, ->(date) {
    raise ArgumentError, "date cannot be nil" unless date
    where("created_at < ?", date)
  }

  scope :filtered, -> (include_pending: true, include_triaged: true) {
    if include_pending && include_triaged
      scoped
    elsif include_pending
      pending
    elsif include_triaged
      in_column
    else
      none
    end
  }

  # Public: Create a new card in the specified column.
  #
  # column - The column to create the card in.
  # creator - The User who is creating the card.
  # content_params - A Hash of parameters for the card's content. See below for
  #   proper formatting.
  # after - (Optional) Another ProjectCard that this new card should come
  #   after. If none is passed, this card will be created according to the position.
  # position - (Optional) The position in the column where to create the card.
  # If none is passed, the card will be created after the `after` card, else at the top.
  #
  # content_params should look like one of these two hashes:
  #
  # { content_type: "Note", note: "The text of the note." }
  # { content_type: "Issue", content_id: 123 }
  #
  # Returns a ProjectCard (which may or may not be saved, depending on its
  # validity).
  def self.create_in_column(column, creator:, content_params:, after: nil, position: nil)
    unsaved_card = new(
      column_id: column.id,
      project_id: column.project.id,
      creator_id: creator.id,
    )

    unsaved_card.set_content_from(actor: creator, params: content_params)

    column.prioritize_card!(unsaved_card, after: after, new_card: true, position: position)
  end

  def self.filter_attrs_for_content(content, viewer: nil)
    # In addition to a tokenized version of the issue's title, we include the
    # issue's number (with and without a # in front) in the title field's
    # value, to support filtering by issue number.
    title_value = content.title.downcase.strip.split(/\s+/) + [content.number.to_s, "##{content.number}"]

    attrs = {
      assignee: content.assignees.map { |user| user.display_login.downcase },
      author: content.safe_user && content.safe_user.display_login.downcase,
      label: content.labels.map { |label| label.name.downcase },
      repo: content.repository.name_with_display_owner.downcase,
      state: content.state.to_s,
      title: title_value,
      type: content.pull_request? ? "pr" : "issue",
    }

    if content.milestone.present?
      attrs[:milestone] = content.milestone.title.downcase
    end

    # If the attached issue has a pull request, record its state too.
    if content.pull_request?
      attrs[:review] = content.pull_request.review_merge_states(viewer: viewer)
      attrs[:state] = [attrs[:state]] | [content.pull_request.state.to_s]
      status = content.pull_request.combined_status
      attrs[:status] = status.state if status.any?
    end

    # The `is` attribute is an alias for both state and type.
    attrs[:is] = Array.wrap(attrs[:state]) + Array.wrap(attrs[:type])
    attrs[:is] << "draft" if content.pull_request? && content.pull_request.draft?

    if content.close_issue_references.exists?
      attrs[:linked] = content.pull_request? ? "issue" : "pr"
    end

    attrs
  end

  # The prioritizable module uses direct SQL when inserting at the top so the
  # after_commit callbacks for creating a card get skipped.
  # This provides a way for the module to call the necessary callbacks.
  def run_after_commit_on_create_callbacks
    unless spammy? || importing?
      instrument_creation
      trigger_issue_added_to_project_event
    end

    synchronize_search_index
    synchronize_content_search_index
  end

  def safe_creator
    creator || User.ghost
  end

  def is_note?
    content.blank? && note.present? # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  def age_in_days
    ((current_time_from_proper_timezone - created_at) / 1.day).to_i
  end

  def note_version
    Digest::SHA256.hexdigest(note)
  end

  def redacted?
    false
  end

  # This only gets set to true once the card has passed through the ProjectCardRedactor
  def passed_redaction?
    @passed_redaction
  end

  # Used to determine if the live update should be included in the activity panel
  def show_activity?
    if defined?(@show_activity)
      @show_activity
    else
      !pending?
    end
  end

  def writable_by?(viewer)
    project.writable_by?(viewer)
  end

  def removable_by?(viewer)
    project.writable_by?(viewer)
  end

  def live_updates_enabled?
    persisted?
  end

  # Can this card be converted to an issue by the given user?
  # Checks whether the owner accepts issues in itself (if a repo) or any of
  # its owned repositories.
  #
  # converter - the User who would be creating the issue
  #
  # Returns a Boolean
  def can_convert_to_issue?(converter:)
    return false unless is_note?
    return false unless actor_can_modify_projects?(converter)
    return false unless writable_by?(converter)

    case project.owner
    when Repository
      project.owner.has_issues? && project.owner.readable_by?(converter)
    when Organization
      project.owner.visible_repositories_for(converter).with_issues_enabled.exists?
    when User
      scope = project.owner.repositories.with_issues_enabled

      unless project.owner == converter
        scope = scope.public_or_accessible_by(converter)
      end

      scope.exists?
    else
      false
    end
  end

  def convert_to_note_reference!
    case content # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    when Issue
      issue = content
      repo = issue.repository
      return if repo.nil? || repo.private?

      self.note = issue.url
      self.content = nil
      self.save!
      issue.trigger_remove_from_project_event(project: project, column: column, card_id: id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end
  end

  # Set content safely, taking content visibility to the actor into account
  def set_content_from(actor:, params:)
    case params[:content_type]
    when "Issue"
      self.content = project.content_scope(viewer: actor).find(params[:content_id]) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    when "Note"
      self.note = params[:note]
    else
      nil
    end
  end

  def partial
    case content_type
    when "Issue"
      "issue"
    else
      "note"
    end
  end
  alias :card_type :partial

  def channel(viewer: nil)
    channels = [GitHub::WebSocket::Channels.project_card(self)]

    if content&.pull_request?
      channels.concat(GitHub::WebSocket::Channels.pull_request_mergeable(content.pull_request))
      channels << GitHub::WebSocket::Channels.pull_request(content.pull_request)
    end

    # Add close issue references channels if the content is an actual Issue
    if content && !content.pull_request?
      channels << GitHub::WebSocket::Channels.close_issue_references(content)
    end

    if viewer && is_note?
      reference_channels = references(viewer: viewer).channels
      channels.concat(reference_channels)
    end

    channels
  end

  def notify_subscribers
    GitHub::WebSocket.notify_project_channel(project, GitHub::WebSocket::Channels.project_card(self), {
      client_uid: GitHub.context[:client_uid],
      wait: default_live_updates_wait,
      is_project_activity: show_activity?,
    })
  end

  def trigger_issue_added_to_project_event
    return unless content_type == "Issue"
    content.trigger_add_to_project_event(project: project, column: column, card_id: id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  def trigger_issue_removed_from_project_event
    return if content_type != "Issue" || content.nil? || content.repository.nil?
    content.trigger_remove_from_project_event(project: project, column: column, card_id: id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  def trigger_moved_event(after_card:, previous_column:, automated:)
    if previous_column.nil? # pending card moved into a column
      time_in_triage = Time.current.to_i - created_at.to_i
      GitHub.dogstats.distribution("project_card.dist.triage_time", time_in_triage)

      instrument_creation
      return
    end

    if previous_column == column #inter-column move
      return if modifying_user == User.ghost
    else
      changes = {
        column_id: column.id,
        column_name: column.name,
        old_column_id: previous_column.id,
        old_column_name: previous_column.name,
      }
    end

    instrument :move,
      after_id: after_card && after_card.id,
      changes: changes,
      actor: modifying_user

    GlobalInstrumenter.instrument("project_card.move", {
      actor: modifying_user,
      automated: automated,
      card: self,
      project: project,
      source_column: previous_column,
      target_column: column,
    })
  end

  def synchronize_content_search_index_check
    if (saved_change_to_content_id? && transaction_include_any_action?([:update])) || transaction_include_any_action?([:destroy])
      synchronize_content_search_index
    end
  end

  def synchronize_content_search_index
    content.synchronize_search_index if content.respond_to?(:synchronize_search_index) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  def event_context(prefix: event_prefix)
    payload = {
      "#{prefix}_id".to_sym => id,
      :note => note,
      :content_type => content_type,
      :content_id => content_id,
    }
    if content.present? && content.repository.present?
      payload[:content_url] = content.url
    end
    payload
  end

  def pending?
    column_id.blank?
  end

  def synchronize_search_index
    if destroyed?
      RemoveFromSearchIndexJob.perform_later("project_card", id, project_id)
    else
      Search.add_to_search_index("project_card", id)
    end

    self
  end

  def markdown_stripped_note
    return nil unless is_note?

    html = GitHub::Goomba::NonLinkingMarkdownPipeline.to_html(note.to_s)
    elements = Goomba::DocumentFragment.new(html)

    elements.children.map { |item| item.text_content.strip.downcase }.join(" ")
  end

  def attrs_for_filter(viewer: nil)
    return {} unless passed_redaction?

    if is_note?
      {
        author: safe_creator.display_login.downcase,
        state: "open",
        title: markdown_stripped_note.split(/\s+/),
        type: "note",
        is: %w[open note],
      }
    else
      self.class.filter_attrs_for_content(content, viewer: viewer)
    end
  end

  def url
    return @url if defined?(@url)
    @url = async_url.sync
  end

  def async_url
    async_project.then do |project|
      project.async_url("#card-{id}", id: id)
    end
  end

  def async_readable_by?(user)
    async_creator.then do |owner|
      if owner&.hide_from_user?(user)
        false
      else
        async_project.then { |project| project.async_readable_by?(user) }
      end
    end
  end

  # Fallback to the Project's permissions to check card visibility
  # Utilized by live updates where we don't have the full Project object
  def readable_by?(viewer)
    project.readable_by?(viewer)
  end

  def instrument_creation
    if pending?
      instrument :pending_create, actor: safe_creator, is_pr: content&.pull_request?
    else
      instrument :create, actor: safe_creator
    end

    GlobalInstrumenter.instrument("project_card.create", {
      actor: safe_creator,
      card: self,
      project: project,
      action: :create,
    })
  end

  def self.redact_and_prefill(viewer, project, cards)
    cards = ProjectCardRedactor.new(viewer, cards).cards
    ProjectCardPrefiller.new(project, cards, prefill_pull_requests: false, prefill_references: false).cards
  end

  def references(viewer:)
    @references_by_viewer ||= {}
    @references_by_viewer[viewer] ||= ProjectCardReferences.new(
      text: note,
      project: project,
      viewer: viewer,
    )
  end

  # When issue-backed Project cards are transferred to another repo,
  # we move them to their new home safely. Returns the new card.
  #
  # See IssueTransfer for more information on the transfer process.
  #
  # For Repository-owned projects, do nothing. Dependent destroy handles these.
  #
  # For Org- and User-owned projects, change the underlying issue.
  def transfer_issue_card(new_issue_id)
    return if project.owner_type == "Repository"

    self.content_id = new_issue_id
    save
  end

  def archived?
    archived_at.present?
  end

  def archive
    return true if archived?

    if update(priority: nil, archived_at: current_time_from_proper_timezone)
      type = content_type&.downcase || "note"

      GitHub.dogstats.increment("projects.archived_card", tags: ["content_type:#{type}", "column_purpose:#{column_purpose}"])
      GitHub.dogstats.histogram("projects.archived_card_age", age_in_days)
      instrument :archive, actor: modifying_user

      true
    else
      false
    end
  end

  def unarchive(into_column: column, after: nil)
    return true unless archived?

    archive_duration = ((current_time_from_proper_timezone - archived_at) / 1.day).to_i

    if column != into_column
      changes = {
        column_id: into_column.id,
        column_name: into_column.name,
        old_column_id: column.id,
        old_column_name: column.name,
      }
    end

    if update(archived_at: nil)
      position = :bottom unless after

      into_column.prioritize_card!(self, after: after, position: position, new_card: false)

      # Notify on the same channel that we use for new cards, since subscribers
      # won't know this was an existing card.
      project&.notify_add_cards_channel(
        is_project_activity: show_activity?,
        message: "#{modifying_user} restored an archived card.",
      )

      GitHub.dogstats.increment("projects.unarchived_card", tags: ["column_purpose:#{column_purpose}"])
      GitHub.dogstats.histogram("projects.unarchived_card_after", archive_duration)
      instrument :restore, actor: modifying_user, changes: changes

      true
    else
      false
    end
  end

  delegate :spammy?, to: :creator, allow_nil: true

  private

  def should_instrument_delete?
    !pending? && !spammy?
  end

  def added_to_column?
    new_record? || column_id_changed? || (archived_at_changed? && archived_at_change.second.nil?)
  end

  def notify_content_subscribers
    return if FeatureFlag.vexi.enabled?(:projects_classic_remove_card_subscribers, default: true)
    case content
    when Issue
      content.notify_socket_subscribers(notify_associated: false)

      # Don't try to notify on the project if it's being deleted
      if project
        project.notify_add_cards_channel(is_project_activity: show_activity?)
      end
    end
  end

  def max_cards_per_column
    if column && column.cards.not_archived.count >= ProjectColumn::MAX_CARDS
      errors.add(:max_cards, "can only have #{ProjectColumn::MAX_CARDS} cards per project column")
    end
  end

  def set_project
    if column
      self.project = column.project
    end
  end

  def event_payload
    payload = {
      project_card: self,
      rank: 3,
    }

    if column
      payload[:project_column] = column
      payload[:project] = project
    end
    payload
  end

  # The user who performed the action as set in the GitHub request context.
  # If the context doesn't contain an actor, fall back to the ghost user
  def modifying_user
    @modifying_user ||= (User.find_by_id(GitHub.context[:actor_id]) || User.ghost)
  end

  def instrument_update
    return unless previous_changes.has_key?("note")

    GlobalInstrumenter.instrument("project_card.update", {
      actor: modifying_user,
      card: self,
      project: project,
    })

    old_note = previous_changes["note"].first
    changes = { old_note: old_note, note: note }
    action = previous_changes.has_key?("content_id") ? :convert : :update

    instrument action, changes: changes, actor: modifying_user
  end

  def instrument_deletion
    instrument :delete

    GlobalInstrumenter.instrument("project_card.delete", {
      actor: modifying_user,
      card: self,
      project: project,
      action: :delete,
    })
  end

  # Metrics for DataDog
  # Hard coding the default value prevents DataDog from duplicating "N/A" values
  def column_purpose
    column&.purpose || "none"
  end

  # Private: Serializes this ProjectCard as a webhook payload for any apps
  # that listen for Hook::Event::ProjectCardEvents. Under normal circumstances
  # we deliver webhook events using instrumentation, but this must be called as
  # a before_destroy and uses Hook::Event#generate_payload_and_deliver_later to
  # serialize the webhook payload before the record becomes unavailable.
  #
  # Returns nothing.
  def generate_webhook_payload
    return unless ProjectsClassicSunset.webhooks_enabled?
    if !modifying_user || modifying_user&.spammy?
      @delivery_system = nil
      return
    end

    event = Hook::Event::ProjectCardEvent.new(action: :deleted, project_card_id: id, actor_id: modifying_user.id, triggered_at: Time.now)
    @delivery_system = Hook::DeliverySystem.new(event)
    @delivery_system.generate_hookshot_payloads
  end

  # Private: Queue the payloads generated above for delivery to Hookshot.
  def queue_webhook_delivery
    return unless ProjectsClassicSunset.webhooks_enabled?
    unless defined?(@delivery_system)
      raise "`generate_webhook_payload' must be called before `queue_webhook_delivery'"
    end

    @delivery_system&.deliver_later
  end

  # Private: sends metrics to DataDog for analytics about card age and type
  def track_deletion
    type = content_type&.downcase || "note"

    GitHub.dogstats.histogram("projects.card_deleted_age", age_in_days)
    GitHub.dogstats.increment("projects.card_deleted", tags: ["content_type:#{type}", "is_archived:#{archived?}"])
  end
end
