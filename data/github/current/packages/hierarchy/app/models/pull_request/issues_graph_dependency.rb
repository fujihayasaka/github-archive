# typed: true
# frozen_string_literal: true

# methods to be mixed into the Issue model
module PullRequest::IssuesGraphDependency
  extend ActiveSupport::Concern
  include HierarchyHelper
  extend T::Sig
  extend T::Helpers
  requires_ancestor { PullRequest }

  ITEM_TYPE = "PULL_REQUEST"

  # Private: if the Issues Graph API is enabled, queue a job to sync the data
  # for a given issue to the Issues Graph data store.
  #
  # Returns nothing.
  private def sync_issues_graph_data
    return unless GitHub.issues_graph_api_enabled?(user)
    return unless GitHub.flipper[:tasklist_block].enabled?(repository&.owner)
    return unless hierarchy_model = self.to_hierarchy_model

    SyncIssueToIssuesGraphJob.perform_later(hierarchy_model)
  end

  # Public: convert a given PullRequest / Issue pair into a hash that the issues-graph service
  # accepts as the "key" of an issue on the graph.
  #
  # Returns a Hash.
  def to_hierarchy_model_key
    return unless GitHub.flipper[:tasklist_block].enabled?(repository&.owner)
    self.issue&.to_hierarchy_model_key
  end

  # Public: convert a given issue from a PullRequest / Issue pair
  # into a hash that the issues-graph service accepts
  # as a representation of an issue on the graph.
  #
  # Returns nil if issue is not present, otherwise returns a Hash.
  sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def to_hierarchy_model
    return unless GitHub.flipper[:tasklist_block].enabled?(repository&.owner)
    issue = self.issue
    return unless issue

    repo = repository

    unless repo.present?
      GitHub.logger.info(
        "PullRequest#to_hierarchy_model returned nil due to missing repository",
        "code.namespace": "PullRequest::IssuesGraphDependency",
        "code.function": "to_hierarchy_model",
        "gh.pull_request.id": self.id,
      )
      return nil
    end

    nwo = repo.name_with_display_owner.split("/")
    {
      key: issue.to_hierarchy_model_key,
      title: issue.title,
      url: url,
      # A closed PR can have `draft?` true so we check `state` as well
      # to confirm it is a draft PR before storing `draft` state in issues-graph
      state: draft? && state == :open ? :draft : state,
      stateReason: issue.state_reason,
      userName: nwo[0],
      repoName: nwo[1],
      number:   number,
      repoId: repository_id,
      assignees: issue.assignees.map(&:to_hierarchy_model),
      labels: issue.labels.map(&:to_hierarchy_model),
      itemType: ITEM_TYPE,
    }
  end
end
