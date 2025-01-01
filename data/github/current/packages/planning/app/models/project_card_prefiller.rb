# typed: true
# frozen_string_literal: true

class ProjectCardPrefiller
  def initialize(project, cards, prefill_pull_requests: true, prefill_references: true, viewer: nil)
    @project = project
    @cards = cards
    @prefill_pull_requests = prefill_pull_requests
    @prefill_references = prefill_references
    @viewer = viewer
  end

  def cards
    not_redacted = @cards.reject { |c| c.redacted? }

    GitHub::PrefillAssociations.prefill_associations(not_redacted, [:creator, :project], available_records: [@project])
    GitHub::PrefillAssociations.prefill_associations(projects, :owner)
    prefill_issues
    prefill_pull_requests
    prefill_discussions

    @cards
  end

  private

  def notes
    @notes ||= @cards.select(&:is_note?)
  end

  def issues
    @issues ||= @cards.map(&:content).compact + referenced_issues
  end

  def pull_requests
    @pull_requests ||= issues.map(&:pull_request).compact
  end

  def projects
    [@project].concat(referenced_projects)
  end

  def referenced_issues
    return [] unless @prefill_references
    notes.each_with_object([]) do |card, issues|
      issues.concat(card.references(viewer: @viewer).issues)
    end
  end

  def referenced_projects
    return [] unless @prefill_references
    notes.each_with_object([]) do |card, projects|
      projects.concat(card.references(viewer: @viewer).projects)
    end
  end

  def referenced_discussions
    return [] unless @prefill_references
    notes.each_with_object([]) do |card, discussions|
      discussions.concat(card.references(viewer: @viewer).discussions)
    end
  end

  def prefill_discussions
    discussions = referenced_discussions
    GitHub::PrefillAssociations.prefill_associations(discussions, [:team, :user])
  end

  def prefill_issues
    IssuePrefiller.prefill(issues,
      only_prefill: [:labels, :assignees, :assignments, :pull_request, :close_issue_references])
    GitHub::PrefillAssociations.prefill_associations(issues.map(&:repository), [:owner, :organization])
  end

  def prefill_pull_requests
    return unless @prefill_pull_requests

    GitHub::PrefillAssociations.prefill_associations(pull_requests,
      [:base_repository, :base_user, :head_repository, :head_user, :user],
      available_records: [issues, issues.map(&:repository)]
    )

    # Needed to render review state on cards
    pull_request_repos = [pull_requests.map(&:base_repository), pull_requests.map(&:head_repository)].flatten.compact
    GitHub::PrefillAssociations.prefill_associations pull_request_repos, [:network, :organization, :owner]

    # Needed to render review state and build status on cards
    GitHub::PrefillAssociations.prefill_batch_method(pull_requests, :base_branch_rule_evaluator)

    pull_requests.group_by(&:repository).each do |repo, repo_pull_requests|
      # Needed to render build status on cards
      PullRequest.attach_statuses(repo, repo_pull_requests)
    end
  end
end
