# typed: true
# frozen_string_literal: true

module Timeline
  class EntryLoader
    include GitHub::ResilienceMixin

    def self.load_entries(issue_id, viewer, cap_filter: nil)
      EntryLoader.new(issue_id, viewer, cap_filter: cap_filter).fetch_entries
    end

    # Loads a single entry from the issues graph, without performing any authorization checks.
    def self.load_entry(issue_id, entry_id)
      return nil unless issue_id && entry_id

      begin
        response = GitHub.timeline_api_client.get_timeline_entry(issue_id, entry_id)

        if response.data
          EntryLoader.map_entry(response.data.timeline_entry, issue_id)
        end
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        # just log all errors for now
        GitHub.logger.error(
          "Project timeline events exception in EntryLoader#load_entry",
          {
            exception: e,
            "gh.issue.id": issue_id,
            "gh.issue.timeline.entry.id": entry_id,
          }
        )
      end
    end

    def initialize(issue_id, viewer, cap_filter: nil)
      @viewer = viewer
      @issue_id = issue_id
      @cap_filter = cap_filter
    end

    def fetch_entries
      return [] unless @viewer

      entries = []
      begin
        issue_entity = { id: @issue_id, type: "Issue" }
        viewer = { id: @viewer.id, include_hidden_content: @viewer.site_admin? }

        response = GitHub.timeline_api_client.get(issue_entity, viewer)

        if response.data
          timeline_entries = response.data.timeline.timeline_entries

          timeline_entries.each do |entry|
            mapped_entry = EntryLoader.map_entry(entry, @issue_id)
            entries << mapped_entry if mapped_entry
          end
        end
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        Failbot.report(e)
      end

      return entries if entries.empty?

      project_ids = entries.map(&:memex_id)
      active_projects = with_database_error_fallback(fallback: []) do
        MemexProject.async_active_memexes(project_ids).sync
      end
      accessible_projects = @cap_filter.present? ? @cap_filter.authorized_resources(active_projects) : active_projects
      accessible_project_ids = accessible_projects.map(&:id).to_set

      entries.select { |entry| accessible_project_ids.include?(entry.memex_id) }
    end

    def self.map_entry(entry, issue_id)
      created_at = entry.created_at.to_time

      case entry.type
      when "AddedToProjectEvent"
        ::Timeline::Placeholder::AddedToMemexProject.new(
          id: entry.id,
          issue_id: issue_id,
          created_at: created_at,
          sort_datetimes: [created_at],
          actor_id: entry.actor.id,
          memex_id: entry.subject.id.to_i,
          was_automated: false,
         )
      when "RemovedFromProjectEvent"
        ::Timeline::Placeholder::RemovedFromMemexProject.new(
          id: entry.id,
          issue_id: issue_id,
          created_at: created_at,
          sort_datetimes: [created_at],
          actor_id: entry.actor.id,
          memex_id: entry.subject.id.to_i,
          was_automated: false,
         )
      when "ProjectItemStatusChangedEvent"
        status = entry.properties.find { |prop| prop.key == "status" }&.value
        previous_status = entry.properties.find { |prop| prop.key == "previousStatus" }&.value

        ::Timeline::Placeholder::ProjectItemStatusChanged.new(
          id: entry.id,
          issue_id: issue_id,
          created_at: created_at,
          sort_datetimes: [created_at],
          actor_id: entry.actor.id,
          memex_id: entry.subject.id.to_i,
          was_automated: false,
          status: status,
          previous_status: previous_status,
         )
      when "ConvertedFromDraftEvent"
        ::Timeline::Placeholder::ConvertedFromDraft.new(
          id: entry.id,
          issue_id: issue_id,
          created_at: created_at,
          sort_datetimes: [created_at],
          actor_id: entry.actor.id,
          memex_id: entry.subject.id.to_i,
          was_automated: false,
         )
      end
    end
  end
end
