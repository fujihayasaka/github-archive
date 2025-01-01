# typed: true
# frozen_string_literal: true

# This module is diffing and reconciling the tracked issues from the task items
# extracted from issue body via MarkdownPipeline
module ChecklistReconciliation
  extend T::Helpers
  extend ActiveSupport::Concern
  include GitHub::IssueReferenceResolution
  include GitHub::Timer

  requires_ancestor { Issue }

  def reconcile_checklist(backfill = false)
    timer = Timer.start

    resolved_issues = resolve_tracked_issues
    diff = diff_tracked_issues(resolved_issues)
    author = body_context_user || User.ghost

    reconcile_tracked_issues(diff, author, backfill)
    total_number = diff[:create].size + diff[:delete].size
    unless backfill
      GitHub.dogstats.distribution(
        "checklist.reconcile.total.dist",
        timer.elapsed_ms,
        tags: ["total_number:#{total_number}"])
    end
    total_number
  end

  def has_checklist_items?
    body_changed_after_commit? && (body_result.tracked_issue_anchors.any? || has_tracked_issues?)
  end

  # Updates the checkbox state of a tracked_issue in the parent_issue's comment body to match the tracked_issue's state
  def resolve_checkbox_state(parent_issue, tracked_issue)
    timer = Timer.start
    result = []

    parent_issue.reload

    matching_anchors = parent_issue.body_result.tracked_issue_anchors.reduce(result) do |result, anchor|
      resolved_issue = resolve_issue_reference(anchor.title, repository)
      if resolved_issue && resolved_issue == tracked_issue
        if resolved_issue.state != anchor.state
          result << anchor
        end
      end
      result
    end

    return if matching_anchors.empty?

    update_checklist_items(parent_issue, matching_anchors)

    GitHub.dogstats.distribution(
      "checklist.sync_checklist_state.dist",
      timer.elapsed_ms,
      tags: [
        "action:update",
        "number:#{matching_anchors.count}"
      ])
  end

  # Internal: turns tracked issue anchors (references) parsed from markdown task list into actual issue objects
  def resolve_tracked_issues
    timer = Timer.start
    refs = body_result.tracked_issue_anchors.map { |anchor| anchor.title }
    issues = batch_resolve_issue_references(refs, repository)

    result = issues.reduce({ parsed: [] }) do |memo, tracked_issue|
      if tracked_issue && tracked_issue != self && tracked_issue.pull_request_id.nil?
        memo[:parsed] << tracked_issue
      end
      memo
    end

    GitHub.dogstats.distribution(
      "checklist.reconcile.dist",
      timer.elapsed_ms,
      tags: [
        "action:resolve",
        "parsed:#{result[:parsed].size}"
      ])

    result
  end

  # Calculates the difference between task list data extracted from markdown body and existing tracked_issues
  def diff_tracked_issues(resolved_issues)
    timer = Timer.start
    candidate_list = resolved_issues[:parsed]
    candidate_set = Set.new(candidate_list)
    tracked_issues_set = tracked_issues.to_set # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    diff = {
      # reorder is used to guarantee that diff[:create] is ordered the same way as extracted task items
      create: reorder(candidate_set - tracked_issues_set, candidate_list),
      delete: tracked_issues_set - candidate_set
    }

    GitHub.dogstats.distribution(
      "checklist.reconcile.dist",
      timer.elapsed_ms,
      tags: [
        "action:diff",
        "candidate_set:#{candidate_set.size}",
        "tracked_issues_set:#{tracked_issues_set.size}"
      ])

    diff
  end

  # convert a set to an ordered list, using base_list as the source of the ordering information
  def reorder(set, base_list)
    base_list.reduce([]) do |acc, item|
      if set.include?(item)
        acc << item
      end
      acc
    end
  end

  private

  # Apply tracked issues diff changes by creating/deleting/updating the corresponding tracked_issue relationships
  def reconcile_tracked_issues(diff, actor, backfill = false)
    start_tracking_issues(diff[:create], actor, backfill)
    stop_tracking_issues(diff[:delete], actor)

    notify_socket_subscribers
  end

  def start_tracking_issues(diff_to_create, actor, backfill = false)
    timer = Timer.start
    track_issues_batch(diff_to_create, actor, backfill)

    GitHub.dogstats.distribution(
      "checklist.reconcile.dist",
      timer.elapsed_ms,
      tags: [
        "action:create_batch",
        "number:#{diff_to_create.size}"
      ])
  end

  def stop_tracking_issues(diff_to_delete, actor)
    timer = Timer.start
    stop_tracking_batch(diff_to_delete, actor)

    GitHub.dogstats.distribution(
      "checklist.reconcile.dist",
      timer.elapsed_ms,
      tags: [
        "action:delete_batch",
        "number:#{diff_to_delete.size}"
      ])
  end

end
