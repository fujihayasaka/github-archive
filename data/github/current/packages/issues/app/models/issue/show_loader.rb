# typed: true
# frozen_string_literal: true

class Issue::ShowLoader
  include Issue::PrefillHelper
  include GitHub::ResilienceMixin

  PROJECT_EVENTS = %w(
    added_to_project
    converted_note_to_issue
    moved_columns_in_project
    removed_from_project
  )

  SUPPORTED_EVENTS = %w(
    assigned
    closed
    comment_deleted
    connected
    converted_to_discussion
    demilestoned
    disconnected
    labeled
    locked
    marked_as_duplicate
    milestoned
    pinned
    renamed
    reopened
    transferred
    unassigned
    unlabeled
    unlocked
    unmarked_as_duplicate
    unpinned
    user_blocked
    referenced
  ) + PROJECT_EVENTS

  attr_reader :context
  attr_reader :pagination_params
  attr_reader :timeline_loader

  def initialize(issue, repository, viewer, pagination_params: {}, cap_filter: nil, cpu_timer: nil)
    @context = Issue::Adapter::Context.new(issue, repository, viewer, cap_filter: cap_filter)
    @pagination_params = pagination_params
    @cpu_timer = cpu_timer
    preload
  end

  def self.issue_node(issue, repository, viewer, pagination_params: {}, cap_filter: nil, cpu_timer: nil)
    self.issue_adapter(
      new(issue, repository, viewer, pagination_params: pagination_params, cap_filter: cap_filter, cpu_timer: cpu_timer)
    )
  end

  def self.issue_adapter(loader)
    Issue::Adapter::IssueAdapter.new(loader.context,
      timeline_loader: loader.timeline_loader,
      timeline_since: loader.pagination_params[:timeline_since],
    )
  end

  # The order of preloads and attachments matters
  # This is basically describing the dependency tree for the issues timeline
  def preload
    preload_repository
    load_timeline
    load_issue_comments
    load_issue_events
    load_memex_project_events
    load_cross_references
    load_issues
    load_pull_requests
    attach_pull_request_associations
    load_duplicate_issues
    load_projects
    load_project_cards
    load_memexes
    load_repositories
    attach_cross_reference_associations
    attach_duplicate_event_associations
    attach_connect_event_associations
    attach_events_with_referencing_issues_associations
    attach_repositories
    attach_project_card_associations
    attach_issue_associations
    attach_current_repository_associations
    load_sponsorships
    preload_reactable_attributes
    load_reaction_groups(@context.issue.reaction_groups + @context.comments.map(&:reaction_groups).flatten)
    load_commits
    preload_viewer_can_read_user_content_edits
    load_latest_user_content_edit
    load_users
    load_commit_users
    load_integrations
    load_integration_users
    attach_user_associations
    load_authors_association
    attach_performed_via_integrations
    attach_integrations
    preload_bots
    preload_primary_avatars
    load_labels
    load_milestones
    load_converted_discussions
    preload_hierarchy
    preload_issue
    preload_comments
    preload_issues
    preload_events
    preload_projects
    preload_closed_by_commit_oids
    preload_owner_settings
    preload_visible_closer_for
  end

  def preload_issue
    Issue::Loader::CurrentIssue.load_for(@context)
  end

  def preload_repository
    Issue::Loader::CurrentRepository.load_for(@context)
  end

  def load_timeline
    @timeline_loader = Issue::Loader::IssueTimeline.new(@context, @pagination_params)
    @all_visible_entries = @timeline_loader.timeline_entries

    @all_visible_entries.each do |entry|
      entry.strict_loading! if entry.is_a? ApplicationRecord::Base
    end
  end

  private

  def load_reaction_groups(reaction_groups)
    @reaction_groups = Issue::Loader::ReactionGroups.load_for(@context, reaction_groups: reaction_groups)
  end

  def load_issue_comments
    issue_comments_by_id = @all_visible_entries.select { |p| p.is_a?(IssueComment) }.index_by(&:id)
    @context.preload_attr(:comments_by_id, issue_comments_by_id)
  end

  def load_latest_user_content_edit
    models = @context.comments + [@context.issue]
    Issue::Loader::LatestUserContentEdit.load_for(@context, models: models)
  end

  def load_cross_references
    cross_references_by_id = @all_visible_entries.select { |p| p.is_a?(CrossReference) }.index_by(&:id)
    @context.preload_attr(:cross_references_by_id, cross_references_by_id)
  end

  def load_issue_events(supported_events = SUPPORTED_EVENTS)
    issue_event_entries_by_id = @all_visible_entries.
      select { |p| p.is_a?(IssueEvent) && supported_events.include?(p.event) }.
      index_by(&:id)

    @context.preload_attr(:events_by_id, issue_event_entries_by_id)
  end

  def load_memex_project_events
    project_events = @all_visible_entries.
      select { |p| p.is_a?(Timeline::Placeholder::MemexProjectEvent) }

    @context.preload_attr(:memex_project_events, project_events)
  end

  def load_labels
    label_ids = @context.events.select { |p| p.event == "labeled" || p.event == "unlabeled" }.map(&:label_id)
    labels_by_id = Issue::Loader::Labels.load_for(@context, label_ids: label_ids)
    @context.preload_attr(:labels_by_id, labels_by_id)
  end

  def load_milestones
    Issue::Loader::Milestones.load_for(@context, milestone_events: @context.milestone_events)
  end

  def load_projects
    project_ids = @context.events.select { |p| PROJECT_EVENTS.include?(p.event) }.map(&:subject_id).uniq
    projects_by_id = Issue::Loader::Projects.load_for(@context, project_ids: project_ids)
    @context.preload_attr(:projects_by_id, projects_by_id)
  end

  def load_project_cards
    project_card_ids = @context.events.select { |p| PROJECT_EVENTS.include?(p.event) }.map(&:card_id).uniq
    project_cards_by_id = Issue::Loader::ProjectCards.load_for(@context, project_card_ids: project_card_ids)
    @context.preload_attr(:project_cards_by_id, project_cards_by_id)
  end

  def load_memexes
    memex_ids = @context.memex_project_events.map(&:memex_id).uniq
    memexes_by_id = Issue::Loader::Memexes.load_for(@context, memex_ids: memex_ids)
    @context.preload_attr(:memexes_by_id, memexes_by_id)
  end

  def load_users
    user_ids = (
      [@context.repository.owner_id, @context.issue.user_id] +
      @reaction_groups.map(&:user_ids).flatten +
      @context.comments.map { |c| [c.user_id, c.latest_user_content_edit&.editor_id] }.flatten +
      @context.cross_references.map { |cr| cr.actor_id } +
      @context.issue_event_user_ids +
      @context.repositories.map(&:owner_id) +
      @context.projects_owned_by_organization.map(&:owner_id) +
      @context.projects_owned_by_users.map(&:owner_id) +
      (@context.memex_project_events || []).map(&:actor_id) + # Timeline is not loaded for the CommentLoader
      @context.memexes.map(&:owner_id)
    ).compact.uniq

    Issue::Loader::Users.load_for(@context, user_ids: user_ids)
  end

  def load_integration_users
    known_user_ids = @context.users_by_id.keys
    integration_owner_ids = @context.integrations.map(&:owner_id)
    integration_bot_ids = @context.integrations.map(&:bot_id)
    user_ids_to_load = (integration_owner_ids + integration_bot_ids).uniq - known_user_ids

    return unless user_ids_to_load.any?

    users_by_id = Issue::Loader::Users.load_users(user_ids_to_load)
    users_by_id.each { |id, user| @context.users_by_id[id] = user }

    Issue::Loader::Users.new(@context).preload_primary_avatars_for_users(@context.integrations, "integrations")
  end

  def preload_primary_avatars
    user_ids = (
      [@context.issue.user&.id] +
      @context.comments.map(&:user_id) +
      @context.integrations.map(&:owner_id) +
      @context.issue_event_user_ids
    ).compact.uniq

    users = user_ids.map { |user_id| @context.users_by_id[user_id] }
    users += @context.commit_visible_authors if @context.commit_visible_authors.present?
    Issue::Loader::Users.new(@context).preload_primary_avatars_for_users(users, "users")
  end

  def load_issues
    issue_ids = (
      @context.cross_references.map { |cr| [cr.source_id, cr.target_id] }.flatten +
      @context.duplicate_event_issue_ids +
      @context.connect_events.select { |e| e.subject_type == "Issue" }.map { |e| e.subject_id } +
      @context.events_with_referencing_issues.map { |e| e.referencing_issue_id }
    ).compact.uniq

    Issue::Loader::Issues.load_for(@context, issue_ids: issue_ids)
  end

  def load_pull_requests
    pull_request_ids = (
      @context.cross_references.map do |cross_reference|
        [cross_reference.source_id, cross_reference.target_id].map do |issue_id|
          @context.issues_by_id[issue_id]&.pull_request_id
        end
      end.flatten +
      @context.connect_events_pull_request_ids +
      @context.duplicate_event_pull_request_ids +
      @context.events_with_referencing_issues.map do |e|
        @context.issues_by_id[e.referencing_issue_id]&.pull_request_id
      end
    ).compact.uniq
    Issue::Loader::PullRequests.load_for(@context, pull_request_ids: pull_request_ids)
  end

  def load_duplicate_issues
    canonical_and_issue_ids = @context.duplicate_events.map do |event|
      [event.issue_event_detail.subject_id, event.issue_id]
    end

    duplicate_issues_by_id = Issue::Loader::DuplicateIssues.load_for(@context, canonical_and_issue_ids: canonical_and_issue_ids)
    @context.preload_attr(:duplicate_issues_by_id, duplicate_issues_by_id)
  end

  def load_repositories
    repository_ids = (
      @context.cross_references.map do |cross_reference|
        [cross_reference.source_id, cross_reference.target_id].map do |issue_id|
          issue = @context.issues_by_id[issue_id]
          if issue.pull_request_id
            @context.pull_requests_by_id[issue.pull_request_id]&.repository_id
          else
            issue.repository_id
          end
        end
      end.flatten +
      @context.projects_owned_by_repositories.map(&:owner_id) +
      @context.issue_event_repository_ids +
      @context.connect_events_pull_request_ids.map do |pull_request_id|
        @context.pull_requests_by_id[pull_request_id]&.repository_id
      end +
      @context.duplicate_event_issue_ids.map do |issue_id|
        issue = @context.issues_by_id[issue_id]
        issue.repository_id
      end +
      @context.duplicate_issues.map(&:repository_id) +
      @context.events_with_commits.map do |event|
        [event.commit_repository_id, event.repository_id]
      end.flatten +
      @context.connect_events.map(&:repository_id) +
      @context.connect_events_issue_repository_ids +
      @context.comments.map(&:repository_id) +
      @context.events_with_referencing_issues.map do |event|
        event.repository_id
      end.flatten
    ).compact.uniq

    Issue::Loader::Repositories.load_for(@context, repository_ids: repository_ids)
  end

  def load_commits
    with_database_error_fallback do
      Issue::Loader::Commits.load_for(@context, events: @context.events_with_commits)
    end
  end

  def load_commit_users
    with_database_error_fallback do
      commit_visible_authors = Issue::Loader::Commits.preload_commit_users(@context, events: @context.events_with_commits)

      @context.preload_attr(:commit_visible_authors, commit_visible_authors)
    end
  end

  def attach_user_associations
    prefill_from_exhaustive_available_records(@context.issue, :user, available_records: @context.users)
    prefill_from_exhaustive_available_records(@context.repository, :owner, available_records: @context.users)

    prefill_from_exhaustive_available_records(@context.comments, :user, available_records: @context.users)
    latest_user_content_edits = @context.comments.map(&:latest_user_content_edit)
    prefill_from_exhaustive_available_records(latest_user_content_edits, :editor, available_records: @context.users)
    prefill_from_exhaustive_available_records(@context.cross_references, :actor, available_records: @context.users)
    prefill_from_exhaustive_available_records(@context.events, :actor, available_records: @context.users)
    issue_event_details = @context.user_subject_events.map(&:issue_event_detail)
    prefill_from_exhaustive_available_records(issue_event_details, :subject, available_records: @context.users)
    prefill_from_exhaustive_available_records(@context.integrations, :owner, available_records: @context.users)
    prefill_from_exhaustive_available_records(@context.repositories, :owner, available_records: @context.users)
    prefill_from_exhaustive_available_records(@context.projects_owned_by_organization, :owner, available_records: @context.users)
    prefill_from_exhaustive_available_records(@context.projects_owned_by_users, :owner, available_records: @context.users)
    prefill_from_exhaustive_available_records(@context.memexes, :owner, available_records: @context.users)
  end

  def attach_current_repository_associations
    GitHub::PrefillAssociations.prefill_associations(@context.comments, :repository, available_records: [@context.repository])
    GitHub::PrefillAssociations.prefill_associations(@context.events, :repository, available_records: [@context.repository])
  end

  def load_sponsorships
    Issue::Loader::Sponsorships.load_for(@context, issue: @context.issue, issue_comments: @context.comments)
  end

  def preload_reactable_attributes
    Promise.all(
      [
        Issue::Loader::CurrentIssue.new(@context).preload_reactable_attributes,
        Issue::Loader::IssueComments.new(@context, issue_comment_ids: nil).preload_comments_reactable_attributes(@context.comments)]
    ).sync
  end

  def attach_issue_associations
    GitHub::PrefillAssociations.prefill_associations(@context.comments, :issue, available_records: [@context.issue])
    GitHub::PrefillAssociations.prefill_associations(@context.events, :issue, available_records: [@context.issue])
  end

  def attach_cross_reference_associations
    GitHub::PrefillAssociations.prefill_associations(@context.cross_references, [:source, :target], available_records: @context.issues)
    cross_reference_issues = @context.cross_references.map(&:source) + @context.cross_references.map(&:target)
    prefill_from_exhaustive_available_records(cross_reference_issues, :pull_request, available_records: @context.pull_requests)
    GitHub::PrefillAssociations.prefill_associations(cross_reference_issues, [:repository, { pull_request: :repository }], available_records: @context.repositories)
  end

  def attach_pull_request_associations
    prefill_from_exhaustive_available_records(@context.issues, :pull_request, available_records: @context.pull_requests)
  end

  def attach_events_with_referencing_issues_associations
    GitHub::PrefillAssociations.prefill_associations(
      @context.events_with_referencing_issues,
      [:referencing_issue, { issue: :pull_request }],
      available_records: @context.issues + @context.pull_requests
    )
  end

  def attach_repositories
    GitHub::PrefillAssociations.prefill_associations(@context.projects_owned_by_repositories, :owner, available_records: @context.repositories)
    GitHub::PrefillAssociations.prefill_associations(@context.events_with_commits, [:repository, :commit_repository], available_records: @context.repositories)

    # Can't use available_records here because the association has a scope
    @context.duplicate_issues.each do |duplicate_issue|
      repository = @context.repositories_by_id[duplicate_issue.repository_id]
      duplicate_issue.association(:repository).target = repository
    end
  end

  def attach_duplicate_event_associations
    duplicate_issue_events = @context.duplicate_events.select { |e| e.subject_type == "Issue" }
    GitHub::PrefillAssociations.prefill_associations(duplicate_issue_events, { issue_event_detail: :subject }, available_records: @context.issues)

    # TODO: We might want to use readable_repositories_by_id instead for cross-repo cases. (covered by tests, current version seems correct)
    duplicate_event_issues = @context.duplicate_event_issue_ids.map { |issue_id| @context.issues_by_id[issue_id] }
    GitHub::PrefillAssociations.prefill_associations(duplicate_event_issues, :repository, available_records: @context.repositories)

    duplicate_pr_events = @context.duplicate_events.select { |e| e.subject_type == "PullRequest" }
    GitHub::PrefillAssociations.prefill_associations(duplicate_pr_events, { event: :issue_event_detail }, available_records: @context.pull_requests)
  end

  def attach_connect_event_associations
    issue_connect_events = @context.connect_events.select { |e| e.subject_type == "Issue" }
    GitHub::PrefillAssociations.prefill_associations(issue_connect_events, { issue_event_detail: { subject: :pull_request } }, available_records: @context.issues + @context.pull_requests)

    connect_events_pull_requests = @context.connect_events_pull_request_ids.map { |pull_request_id| @context.pull_requests_by_id[pull_request_id] }
    GitHub::PrefillAssociations.prefill_associations(connect_events_pull_requests, [:repository, { issue: :repository }], available_records: @context.repositories)
  end

  def attach_project_card_associations
    GitHub::PrefillAssociations.prefill_associations(@context.project_cards, :project, available_records: @context.projects)
  end

  def load_authors_association
    if @cpu_timer
      @cpu_timer.track do
        Issue::Loader::CommentAuthorAssociations.load_for(@context, associables: @context.comments + [@context.issue])
      end
    else
      Issue::Loader::CommentAuthorAssociations.load_for(@context, associables: @context.comments + [@context.issue])
    end
  end

  def load_integrations
    performed_via_integration_ids = (
      [@context.issue] + @context.comments + @context.events
    ).map(&:performed_by_integration_id).compact.uniq
    Issue::Loader::Integrations.load_for(@context, integration_ids: performed_via_integration_ids)

    # bots do not know their integration id
    bots = @context.users_by_id.values.select { |user| user.is_a?(Bot) }
    known_bot_ids = @context.integrations.map(&:bot_id)
    bot_ids_to_load = (bots.map(&:id) - known_bot_ids).compact
    if bot_ids_to_load.any?
      Issue::Loader::Integrations.load_for_bots(@context, bot_ids: bot_ids_to_load)
    end
  end

  def attach_performed_via_integrations
    models = [@context.issue] + @context.comments + @context.events
    Issue::Loader::Integrations.attach_performed_via_integration(@context, models)
  end

  def attach_integrations
    bots = @context.users_by_id.values.select { |user| user.is_a?(Bot) }
    Issue::Loader::Integrations.attach_integrations_to_bots(@context, bots)
  end

  def preload_events
    Issue::Loader::IssueEvents.preload_issue_events_for(@context)
  end

  def preload_comments
    comment_loader = Issue::Loader::IssueComments.new(@context, issue_comment_ids: nil)
    comment_loader.preload(@context.comments_by_id.values)
  end

  def preload_issues
    issues = @context.cross_references.map { |cr| [cr.source, cr.target] }.flatten.compact.uniq
    Issue::Loader::Issues.preload_for(@context, issues: issues)
  end

  def preload_bots
    bots = @context.users_by_id.values.select { |user| user.is_a?(Bot) }
    return unless bots.any?
    Issue::Loader::Users.preload_bots_for(@context, bots: bots)
  end

  def preload_projects
    Issue::Loader::Projects.preload_for(@context, projects: @context.projects)
    Issue::Loader::ProjectCards.preload_for(@context, project_cards: @context.project_cards)
  end

  def preload_closed_by_commit_oids
    if @context.events_with_commits.size > 0
      GitHub::PrefillAssociations.prefill_batch_method(@context.issue, :closed_by_commit_oids)
    end
  end

  def preload_visible_closer_for
    auto_close_events = @context.events.select { |p| p.event == "closed" && p.performed_by_project_workflow_action_id? && p.column_name? }
    GitHub::PrefillAssociations.prefill_batch_method(auto_close_events, :visible_closer_for, @context.viewer)
  end

  def preload_viewer_can_read_user_content_edits
    Promise.all([
      Issue::Loader::CurrentIssue.preload_viewer_can_read_user_content_edits_for(@context),
      Issue::Loader::IssueComments.preload_viewer_can_read_user_content_edits_for(@context, @context.comments)
    ]).sync
  end

  def load_converted_discussions
    Issue::Loader::Discussions.load_for(
      @context,
      conversion_events: @context.converted_to_discussion_events,
    )
  end

  def preload_owner_settings
    GitHub::PrefillAssociations.prefill_associations([@context.repository.owner], :user_settings_record)
  end

  def preload_hierarchy
    HierarchyCommands::Preload.new(
      issue: @context.issue,
      repository: @context.repository,
      owner: @context.repository.owner,
      viewer: @context.viewer
    ).call

    # Temporary as we look to replace the issues graph dependency file
    @context.issue.instance_variable_set(:@hierarchy_state, @context.issue.hierarchy_raw.data)
  end
end
