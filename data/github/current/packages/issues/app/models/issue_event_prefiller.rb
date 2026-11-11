# typed: true
# frozen_string_literal: true

module IssueEventPrefiller
  class << self
    # Public: Preloads #issue and #repository associations in
    # IssueEvent objects.
    #
    # Also does further processing on specific kinds of issue events
    #
    # events - an Array of IssueEvents
    #
    # Returns nothing
    def prefill(events, prefill_subject_owners: false, prefill_repository_owner: false)
      relation = if prefill_subject_owners
        GitHub::PrefillAssociations.prefill_associations(events, [ # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          { issue: :repository }, :repository, :actor, :performed_via_integration
        ])
      else
        relations = T.let([:issue, :repository, :actor, :performed_via_integration], T::Array[T.any(Symbol, T::Hash[Symbol, Symbol])])
        if prefill_repository_owner
          relations << { repository: :owner }
        end

        GitHub::PrefillAssociations.prefill_associations(events, relations) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end

      GitHub::PrefillAssociations.prefill_batch_method(events, :milestone)

      prefill_auto_close_events(events)

      prefill_project_events(events, prefill_subject_owners)
    end

    private

    def prefill_auto_close_events(events)
      auto_close_events = events.select { |event| event.auto_close_workflow_automation? }
      return if auto_close_events.empty?

      GitHub::PrefillAssociations.prefill_batch_method(auto_close_events, :memex_project)
    end

    def prefill_project_events(events, prefill_subject_owners)
      project_events = events.select { |event| event.subject_type == "Project" }
      return if project_events.empty?

      projects_by_id = {}

      projects = Project.where(id: project_events.map(&:subject_id).uniq)
      GitHub::PrefillAssociations.prefill_associations(projects, [:owner]) if prefill_subject_owners

      projects.each do |project|
        projects_by_id[project.id] = project
      end

      project_events.each do |event|
        event.issue_event_detail.subject = projects_by_id[event.subject_id]
      end
    end


  end
end
