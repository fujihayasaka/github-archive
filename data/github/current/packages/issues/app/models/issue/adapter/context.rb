# typed: true
# frozen_string_literal: true

class Issue::Adapter::Context
  include PreloadableAttributes

  attr_reader :cap_filter,
    :comments_by_id,
    :converted_discussions_by_event_id,
    :cross_references_by_id,
    :duplicate_issues_by_id,
    :events_by_id,
    :integrations_by_id,
    :integrations_by_model,
    :issue,
    :issues_by_id,
    :memexes_by_id,
    :milestones_by_event_id,
    :labels_by_id,
    :projects_by_id,
    :project_cards_by_id,
    :pull_requests_by_id,
    :readable_repositories_by_id,
    :repositories_by_id,
    :repository,
    :author_to_repo_owner_sponsorships_by_author_id,
    :users_by_id,
    :commit_visible_authors,
    :viewer,
    :hovercard_context_involvements,
    :tracked_in_issues,
    :memex_project_events,
    :disable_issues_graph

  attr_preloadable :comments_by_id,
    :converted_discussions_by_event_id,
    :cross_references_by_id,
    :duplicate_issues_by_id,
    :events_by_id,
    :integrations_by_id,
    :integrations_by_model,
    :memexes_by_id,
    :milestones_by_event_id,
    :issues_by_id,
    :labels_by_id,
    :projects_by_id,
    :project_cards_by_id,
    :pull_requests_by_id,
    :repositories_by_id,
    :readable_repositories_by_id,
    :author_to_repo_owner_sponsorships_by_author_id,
    :commit_visible_authors,
    :users_by_id,
    :hovercard_context_involvements,
    :tracked_in_issues,
    :memex_project_events

  def initialize(issue, repository, viewer, cap_filter: nil, disable_issues_graph: false)
    @issue = issue
    @repository = repository
    @viewer = viewer
    @cap_filter = cap_filter
    @disable_issues_graph = disable_issues_graph
  end

  def repository_adapter
    return @repository_adapter if defined?(@repository_adapter)
    @repository_adapter = Issue::Adapter::RepositoryAdapter.new(self, repository: self.repository)
  end

  def comments
    return @comments if defined?(@comments)
    @comments = comments_by_id.values
  end

  def connect_events
    return @connect_events if defined?(@connect_events)
    @connect_events = events.select { |e| %w(connected disconnected).include?(e.event) }
  end

  def connect_events_pull_request_ids
    return @connect_events_pull_request_ids if defined?(@connect_events_pull_request_ids)
    @connect_events_pull_request_ids = connect_events.map { |e| @issues_by_id[e.subject_id]&.pull_request_id.presence }.compact
  end

  def connect_events_issue_repository_ids
    return @connect_events_repository_ids if defined?(@connect_events_repository_ids)
    @connect_events_repository_ids = connect_events.map { |e| @issues_by_id[e.subject_id]&.repository_id.presence }.compact
  end

  def cross_references
    return @cross_references if defined?(@cross_references)
    @cross_references = cross_references_by_id.values
  end

  def events
    return @events if defined?(@events)
    @events = events_by_id.values
  end

  def events_with_commits
    return @events_with_commits if defined?(@events_with_commits)
    @events_with_commits = events.select { |e| %w(closed referenced).include?(e.event) && e.commit? }
  end

  def events_with_referencing_issues
    return @events_with_referencing_issues if defined?(@events_with_referencing_issues)
    @events_with_referencing_issues = events.select { |e| %w(closed).include?(e.event) && e.referencing_issue_id }
  end

  def memex_events_without_project_url
    return @memex_events_without_project_url if defined?(@memex_events_without_project_url)
    @memex_events_without_project_url = memex_project_events.reject { |event| event.memex_resource_path.present? }
  end

  def milestone_events
    return @milestone_events if defined? @milestone_events
    @milestone_events = events.select { |p| p.event == "milestoned" || p.event == "demilestoned"  }
  end

  def integrations
    integrations_by_id.values
  end

  def issues
    return @issues if defined?(@issues)
    @issues = issues_by_id.values
  end

  def projects
    return @projects if defined?(@projects)
    @projects = projects_by_id.values
  end

  def projects_owned_by_repositories
    return @projects_owned_by_repositories if defined?(@projects_owned_by_repositories)
    @projects_owned_by_repositories = projects.select { |project| project.owner_type == "Repository" }
  end

  def projects_owned_by_organization
    return @projects_owned_by_organization if defined?(@projects_owned_by_organization)
    @projects_owned_by_organization = projects.select { |project| project.owner_type == "Organization" }
  end

  def projects_owned_by_users
    return @projects_owned_by_users if defined?(@projects_owned_by_users)
    @projects_owned_by_users = projects.select { |project| project.owner_type == "User" }
  end

  def project_cards
    return @project_cards if defined?(@project_cards)
    @project_cards = project_cards_by_id.values
  end

  def memexes
    return @memexes if defined?(@memexes)
    @memexes = (memexes_by_id || {}).values
  end

  def pull_requests
    return @pull_requests if defined?(@pull_requests)
    @pull_requests = pull_requests_by_id.values
  end

  def repositories
    return @repositories if defined?(@repositories)
    @repositories = repositories_by_id.values
  end

  def user_subject_events
    return @user_subject_events if defined? @user_subject_events
    @user_subject_events = events.select do |e|
      %w(
        assigned
        comment_deleted
        unassigned
        user_blocked
      ).include?(e.event)
    end
  end

  def users
    return @users if defined?(@users)
    @users = users_by_id.values
  end

  def bots
    return @bots if defined?(@bots)
    @bots = if users
      users.select { |user| user.is_a?(Bot) }
    else
      []
    end
  end

  def duplicate_events
    return @duplicate_events if defined?(@duplicate_events)
    @duplicate_events = events.select { |e| %w(marked_as_duplicate unmarked_as_duplicate).include?(e.event) }
  end

  def duplicate_event_issue_ids
    return @duplicate_event_issue_ids if defined?(@duplicate_event_issue_ids)
    @duplicate_event_issue_ids = (
      duplicate_events.select { |e| e.subject_type == "Issue" }.map { |e| e.subject_id } +
      duplicate_events.map { |e| e.issue_id }
    ).uniq
  end

  def duplicate_event_pull_request_ids
    return @duplicate_event_pull_request_ids if defined? @duplicate_event_pull_request_ids
    @duplicate_event_pull_request_ids = duplicate_events.select { |e| e.subject_type == "PullRequest" }.map { |e| e.subject_id }
  end

  def duplicate_issues
    return @duplicate_issues if defined?(@duplicate_issues)
    @duplicate_issues = duplicate_issues_by_id.values
  end

  def issue_event_user_ids
    return @issue_event_user_ids if defined? @issue_event_user_ids
    @issue_event_user_ids = events.map(&:actor_id) + user_subject_events.map { |e| e.subject_id }
  end

  def issue_event_repository_ids
    return @issue_event_repository_ids if defined? @issue_event_repository_ids
    @issue_event_repository_ids = events.
      select do |e|
        %w(
          transferred
        ).include?(e.event)
      end.
      map { |e| e.subject_id }
  end

  def raise_on_missing_timeline_adapter
    Rails.env.development? || Rails.env.test?
  end

  def converted_to_discussion_events
    return @converted_to_discussion_events if defined? @converted_to_discussion_events
    @converted_to_discussion_events = events.select { |p| p.event == "converted_to_discussion" }
  end
end
