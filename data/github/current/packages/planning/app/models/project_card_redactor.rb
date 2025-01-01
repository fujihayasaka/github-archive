# typed: true
# frozen_string_literal: true

class ProjectCardRedactor
  include Scientist

  # Public: Card to pass to the partial that contains no confidential
  # data and just enough to render the redacted card partial.
  class RedactedCard
    SPAMMY_CONTENT = :spammy
    INSUFFICIENT_PERMISSION = :permissions
    REPOSITORY_MISSING = :repository_missing
    ISSUE_MISSING = :issue_missing

    include GitHub::Relay::GlobalIdentification

    attr_reader :id, :column, :project, :creator, :created_at, :updated_at, :global_relay_id, :next_global_id, :reason_for_redaction, :archived_at

    def initialize(card, reason_for_redaction)
      @id = card.id
      @column = card.column
      @project = card.project
      @creator = card.creator
      @created_at = card.created_at
      @updated_at = card.updated_at
      @global_relay_id = card.global_relay_id
      @next_global_id = card.next_global_id
      @archived_at = card.archived_at
      @reason_for_redaction = reason_for_redaction
    end

    def async_column
      Promise.resolve(column)
    end

    def async_creator
      Promise.resolve(creator)
    end

    def async_project
      Promise.resolve(project)
    end

    # FIXME Could this reuse the implementation from ProjectCard?
    def async_url
      async_project.then do |project|
        project.async_url("#card-{id}", id: id)
      end
    end

    def note
      nil
    end

    def is_note?
      false
    end

    def content_type
      "Redacted"
    end

    def redacted?
      true
    end

    def archived?
      @archived_at.present?
    end

    def pending?
      column_id.blank?
    end

    def passed_redaction?
      true
    end

    # Must be used anywhere a creator is assumed to exist. A user is required
    # when creating a card but they can delete their account and the card
    # will still exist.
    def safe_creator
      creator || User.ghost
    end

    def column_id
      column && column.id
    end

    def creator_id
      creator && creator.id
    end

    def content_id
      nil
    end
    alias :content :content_id

    def project_id
      project && project.id
    end

    def partial
      "redacted"
    end

    def writable_by?(viewer)
      [SPAMMY_CONTENT, REPOSITORY_MISSING, ISSUE_MISSING].include?(reason_for_redaction) && project.writable_by?(viewer)
    end

    def removable_by?(viewer)
      project.writable_by?(viewer)
    end

    def persisted?
      !@id.nil?
    end

    def live_updates_enabled?
      false
    end

    def attrs_for_filter(viewer: nil)
      {}
    end
  end

  def initialize(viewer, unfiltered_cards)
    @viewer, @unfiltered_cards = viewer, unfiltered_cards
  end

  def self.check_one(viewer, card)
    new(viewer, [card]).cards.first
  end

  def cards
    @cards ||= begin
      # Preload issues and projects associated with unfiltered cards
      GitHub::PrefillAssociations.prefill_associations @unfiltered_cards, [:content, :creator, :project]
      # Preload repositories for associated issues since that is used by repository_missing?
      GitHub::PrefillAssociations.prefill_associations @unfiltered_cards.map(&:content).compact, [:repository]

      @unfiltered_cards.map do |card|
        if repository_missing?(card)
          RedactedCard.new(card, RedactedCard::REPOSITORY_MISSING)
        elsif issue_missing?(card)
          RedactedCard.new(card, RedactedCard::ISSUE_MISSING)
        elsif permissions_redact?(card)
          RedactedCard.new(card, RedactedCard::INSUFFICIENT_PERMISSION)
        elsif spammy_content_redact?(card)
          RedactedCard.new(card, RedactedCard::SPAMMY_CONTENT)
        else
          card.passed_redaction = true
          card
        end
      end
    end
  end

  def platform_type_name
    "ProjectCard"
  end

  private

  def repository_missing?(card)
    case card.content
    when Issue
      card.content.repository.nil?
    else
      false
    end
  end

  def issue_missing?(card)
    case card.content
    when Issue
      card.content.repository &&
        DeletedIssues::Public.by_old_issue(card.content_id, repository_id: card.content.repository.id) &&
        card.content.repository.readable_by?(@viewer)
    else
      false
    end
  end

  def permissions_redact?(card)
    case card.content
    when Issue
      visible_issue_ids.exclude?(card.content_id)
    else
      false
    end
  end

  def spammy_content_redact?(card)
    if card.is_note?
      card.creator_id != @viewer&.id && card.spammy?
    elsif card.content_type == "Issue"
      non_spammy_issue_ids.exclude?(card.content_id)
    else
      Failbot.report(StandardError.new("Invalid content type"))
      false
    end
  end

  def non_spammy_issue_ids
    return [] unless visible_issue_ids.present?
    return @non_spammy_issue_ids if defined?(@non_spammy_issue_ids)

    scope = Issue.where(id: visible_issue_ids).filter_spam_for(@viewer, show_spam_to_staff: false)
    scope_repo_ids = scope.select(:repository_id).distinct.pluck(:repository_id)
    filtered_repo_ids = Repository.where(id: scope_repo_ids, user_hidden: false).pluck(:id)
    @non_spammy_issue_ids = scope.where(repository_id: filtered_repo_ids).pluck(:id)
  end

  def visible_issue_ids
    @visible_issue_ids ||= begin
      issue_cards = @unfiltered_cards.select { |c| c.content_type == "Issue" }
      Issue.legacy_visible_ids_for(issue_cards.map(&:content_id), viewer: @viewer)
    end
  end
end
