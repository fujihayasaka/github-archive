# typed: true
# frozen_string_literal: true

class SyncMemexProjectHierarchyJob < ApplicationJob
  include HierarchyHelper

  MAX_DEPTH = 10

  queue_as :sync_memex_project_hierarchy

  retry_on_dirty_exit

  locked_by timeout: 1.hour, key: ->(job) { job.arguments[0] }

  def perform(memex_project_id)
    ActiveRecord::Base.connected_to(role: :reading) do
      return unless memex_project = MemexProject.find_by(id: memex_project_id)

      issue_ids = memex_project.memex_project_items.not_archived.where(content_type: Issue.name).pluck(:content_id)
      issues = Issue.where(id: issue_ids).order(:id).to_ary
      @visited = []

      prefill_issues(issues)
      issues.each_slice(100) do |issues_slice|
        sync_project_and_relationships(memex_project, issues_slice)
      end
      recursive_sync_tracked_issues(issues)
    end
  end

  private

  def recursive_sync_tracked_issues(issues, depth = 0)
    depth += 1
    return log("max depth reached") if depth > MAX_DEPTH

    prefill_issues(issues)
    issues.each do |issue|
      next if issue.tracked_issues.empty? || @visited.include?(issue.id)

      @visited << issue.id

      recursive_sync_tracked_issues(issue.tracked_issues, depth)
    end
  end

  def prefill_issues(issues)
    GitHub::PrefillAssociations.prefill_associations(issues, :tracked_issues)

    tracked_issues = issues.flat_map(&:tracked_issues)
    all_issues = issues + tracked_issues

    GitHub::PrefillAssociations.prefill_associations(all_issues, [:repository, :user])

    all_repositories = all_issues.map(&:repository).uniq
    GitHub::PrefillAssociations.prefill_associations(all_repositories, :owner)
  end

  sig { params(project: MemexProject, issues: T::Array[Issue]).void }
  def sync_project_and_relationships(project, issues)
    model = project.to_hierarchy_model

    return unless model.present?

    GitHub
      .issues_graph_api_client
      .upsert_project_and_relationships(
        from: model,
        to: issues.map(&:to_hierarchy_model).compact,
        stat_tags: ["context:sync_memex_project_hierachy_job.sync_project_and_relationships"]
      )
  end

  def log(msg)
    GitHub::logger.info(msg, "code.namespace": self.class.name)
  end
end
