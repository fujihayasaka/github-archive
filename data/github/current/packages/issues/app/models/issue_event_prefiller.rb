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
    def prefill(events, prefill_subject_owners: false)
      relation = if prefill_subject_owners
        GitHub::PrefillAssociations.prefill_associations(events, [
          { issue: :repository }, :repository, :actor, :performed_via_integration
        ])
      else
        GitHub::PrefillAssociations.prefill_associations(events, [:issue, :repository, :actor, :performed_via_integration])
      end

      GitHub::PrefillAssociations.prefill_batch_method(events, :milestone)

      prefill_auto_close_events(events)

      prefill_project_events(events, prefill_subject_owners)

      commit_events = events.select(&:commit_id?) + events.select(&:force_push?)
      prefill_issue_commit_references(commit_events)
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

    def prefill_issue_commit_references(events)
      GitHub::PrefillAssociations.prefill_associations(events, :commit_repository)

      events.group_by(&:repository_for_commit).each do |repo, repo_events|
        repo_oids = repo_events.collect(&:commit_id).uniq.compact
        commits   = repo.objects.read_all(repo_oids, "commit", skip_bad: true)  # some commits may be gone, GCed

        Commit.prefill_comment_counts(commits, repo)
        commits   = commits.index_by(&:oid)

        repo_events.each do |event|
          event.commit = commits[event.commit_id]
        end
      end
    end
  end
end
