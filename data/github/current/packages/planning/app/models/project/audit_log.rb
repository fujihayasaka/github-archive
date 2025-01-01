# typed: true
# frozen_string_literal: true

class Project
  class AuditLog
    include Scientist, AuditLogHelper

    class Entry < ::AuditLogEntry
      attr_accessor :card_content
      attr_accessor :card_redacted_reason
      attr_writer :card_redacted
      attr_writer :passed_redaction
      attr_writer :active_card

      def new_from_hash(entry)
        T.bind(self, T.untyped)
        super
      end

      def card_redacted?
        @card_redacted
      end

      def active_card?
        @active_card
      end

      def card_id
        data["project_card_id"]
      end

      def automated?
        data["project_workflow_action_id"].present?
      end

      def automation_trigger
        data["project_workflow_trigger"]
      end

      def automation_action
        data["project_workflow_action"]
      end

      def workflow_type
        return "" unless data["project_workflow"].present?

        case data["project_workflow"]
        when ProjectWorkflow::PR_CLOSED_NOT_MERGED_TRIGGER
          "Pull Request closed without merge"
        when "content_reopened"
          # the old audit log entries for the V1 automation where not updated
          # as part of the V1 -> V2 transformation so keeping the string
          # version around for the activity feed string
          "Issue or Pull Request reopened"
        else
          data["project_workflow"].humanize.gsub("Pr ", "Pull Request ")
        end
      end

      def card_title
        @card_title ||= if card_redacted?
          nil
        elsif card_content.present?
          card_content.title
        else
          html = GitHub::Goomba::NonLinkingMarkdownPipeline.to_html(note.to_s)
          root_element = Goomba::DocumentFragment.new(html).children.first
          stripped_text = root_element ? root_element.text_content.strip : ""

          stripped_text.lines.first
        end
      end

      def card_converted_to_issue_with_title_change?
        action == "project_card.convert" &&
        card_content &&
        card_content.title != data["changes"]["old_note"]
      end

      def column_name
        data["project_column"]
      end

      def old_name
        data.dig("changes", "old_name")
      end

      def name_changed?
        old_name.present?
      end

      def previous_column_name
        data.dig("changes", "old_column_name") if data

      end

      def column_purpose
        data.dig("changes", "purpose")
      end

      def old_column_purpose
        data.dig("changes", "old_purpose")
      end

      def column_purpose_changed?
        column_purpose.present? || old_column_purpose.present?
      end

      def column_purpose_change_type
        if old_column_purpose.present? && column_purpose.present?
          "updated"
        elsif old_column_purpose.present?
          "removed"
        elsif column_purpose.present?
          "added"
        end
      end

      def event_type
        @event_type ||= action.split(".").pop
      end

      def past_tense_event_type
        @past_tense_event_type ||= case event_type
        when "close"
          "closed"
        when "create"
          "created"
        when "convert"
          "converted"
        when "delete"
          "deleted"
        when "open"
          "reopened"
        when "rename"
          "renamed"
        when "move"
          "moved"
        when "update"
          "updated"
        when "archive"
          "archived"
        when "restore"
          "restored"
        when "link"
          "linked"
        when "unlink"
          "unlinked"
        else
          raise "Unknown event type #{event_type}"
        end
      end

      def event_namespace
        @event_namespace ||= action.split(".").shift
      end

      def passed_redaction?
        @passed_redaction
      end

      def show_column_name?
        return false if %w(archive create move restore).exclude?(event_type)
        return false if column_name.blank?

        if event_type == "restore"
          # For "restored from archive" events, only show the column name if
          # the column didn't change during the restore event. If it did, we'll
          # also be generating a "move" event that shows the column name
          data.dig("changes", "column_id") == data.dig("changes", "old_column_id")
        else
          true
        end
      end

      def linking_event?
        %w(link unlink).include?(event_type)
      end

      def linked_repository
        return @linked_repository if defined? @linked_repository

        @linked_repository = if linking_event? && repo_id
          Repository.find_by(id: repo_id)
        end
      end
    end

    RECORDING_STARTED_DATE = Time.new(2017, 1, 26)

    attr_reader :project, :latest_allowed_entry_time, :last_viewed_time

    def initialize(project, viewer:, page: 1, after: "", latest_allowed_entry_time: nil, last_viewed_time: nil)
      @project = project
      @viewer = viewer
      @latest_allowed_entry_time = latest_allowed_entry_time || Time.current
      @last_viewed_time = last_viewed_time || Time.current
      @audit_log = @project.audit_log({
        current_user: viewer,
        page: page,
        after: after,
        latest_allowed_entry_time: latest_allowed_entry_time,
      })
    end

    # May want to limit how many pages we will load here?
    def has_next_page?
      if @audit_log.respond_to?(:has_next_page?)
        @audit_log.has_next_page?
      elsif @audit_log.respond_to?(:next_page?)
        @audit_log.next_page?
      end
    end

    def next_page
      if @audit_log.respond_to?(:next_page)
        @audit_log.next_page
      end
    end

    def after_cursor
      if @audit_log.respond_to?(:after_cursor)
        @audit_log.after_cursor
      end
    end

    def each
      entries.each { |entry| yield entry }
    end

    def select
      entries.select { |entry| yield entry }
    end

    def empty?
      entries.empty?
    end

    def size
      entries.size
    end

    def possible_gaps?
      # The project was created before we started reliably recording activity.
      project.created_at < RECORDING_STARTED_DATE ||

      # The project's first activity entry was not a project creation event.
      (!has_next_page? && entries.last&.action != "project.create")
    end

    private

    def entries
      return @entries if defined?(@entries)

      issue_ids = Set.new
      card_ids = Set.new
      note_to_redact_ids = Set.new

      @audit_log.each do |entry_hash|
        data = entry_hash["data"]

        if data["content_id"] && data["content_type"] == "Issue"
          issue_ids << data["content_id"]
        end

        if data["project_card_id"]
          card_ids << data["project_card_id"]
        end
      end

      issues = if issue_ids.present?
        Issue.legacy_visible_for(issue_ids, viewer: @viewer)
      else
        []
      end

      issues_by_id = issues.index_by(&:id)

      non_spammy_issues_by_id = if issues_by_id.present?
        scope = Issue.where(id: issues_by_id.keys).filter_spam_for(@viewer, show_spam_to_staff: false)
        scope_repo_ids = scope.select(:repository_id).distinct.pluck(:repository_id)
        filtered_repo_ids = Repository.where(id: scope_repo_ids, user_hidden: false).pluck(:id)
        scope.where(repository_id: filtered_repo_ids).index_by(&:id)
      else
        {}
      end

      active_card_ids = @project.cards.where(id: card_ids.to_a).pluck(:id)

      @entries = @audit_log.map do |entry_hash|
        entry = Entry.new_from_hash(entry_hash)
        entry.project = @project
        data = entry_hash["data"]

        if data["content_id"] && data["content_type"] == "Issue"
          if issue = issues_by_id[data["content_id"]]
            if non_spammy_issues_by_id[data["content_id"]]
              entry.card_content = issue
            else
              # The viewer can't see the issue because it has spammy content
              entry.card_redacted = true
              entry.card_redacted_reason = ProjectCardRedactor::RedactedCard::SPAMMY_CONTENT
            end
          elsif (deleted_issue = DeletedIssue.where(old_issue_id: data["content_id"]).first) && deleted_issue.repository&.readable_by?(@viewer)
            # The viewer can't see the issue because it was deleted
            entry.card_redacted = true
            entry.card_redacted_reason = ProjectCardRedactor::RedactedCard::ISSUE_MISSING
          else
            # The viewer can't see the issue because they don't have permission
            entry.card_redacted = true
            entry.card_redacted_reason = ProjectCardRedactor::RedactedCard::INSUFFICIENT_PERMISSION
          end
        end

        # Note this relies on the fact that the audit log entries are ordered by
        # timestamp descending. So the creation of a note that should be
        # redacted when converted to an issue will be iterated over _after_ the
        # redacted issue has already been redacted.
        if data["project_card_id"] && entry_hash["action"] == "project_card.convert" && entry.card_redacted?
          note_to_redact_ids << data["project_card_id"]
        end

        if data["project_card_id"] && entry_hash["action"] == "project_card.create" && note_to_redact_ids.include?(data["project_card_id"])
          entry.card_redacted = true
          entry.card_redacted_reason = ProjectCardRedactor::RedactedCard::INSUFFICIENT_PERMISSION
        end

        if data["project_card_id"]
          entry.active_card = active_card_ids.include?(data["project_card_id"])
        end

        entry.passed_redaction = true

        entry
      end
    end
  end
end
