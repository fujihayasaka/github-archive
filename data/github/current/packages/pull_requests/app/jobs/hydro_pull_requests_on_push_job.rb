# typed: true
# frozen_string_literal: true

class HydroPullRequestsOnPushJob < Repositories::PushHydroMessageJob
  use_primaries ApplicationRecord::IssuesPullRequests

  queue_as :hydro_pull_requests_on_push

  def perform
    ref_updates.each do |ref_update|
      next if ref_update.ref_is_tag?

      PullRequestSynchronizationJob.perform_later(repository, ref_update.ref, pusher,
        forced: ref_update.non_fast_forward?,
        before: ref_update.before,
        after: ref_update.after,
        push_options: push_options,
        excluded_pull_ids: excluded_pull_ids&.presence,
        pushed_at: pushed_at
       ) unless ref_update.created? || ref_update.deleted?

      # Explicit callsite tags are pure instrumentation (no behavior change) so Datadog can
      # attribute the remaining mysql1 primary reads under source:job-hydro_pull_requests_on_push_job
      # to specific synchronous call sites. See lib/github/mysql_instrumenter.rb.
      GitHub.context.push(callsite_location_datadog_tags: ["callsite:hydro_pr_push:update_merge_queue"]) do
        update_merge_queue(ref_update) if update_merge_queue?(ref_update)
      end

      if ref_update.created?
        GitHub.context.push(callsite_location_datadog_tags: ["callsite:hydro_pr_push:mark_head_ref_restored"]) do
          PullRequest.mark_head_ref_as(:restored, repository, ref_update.ref, ref_update.after, pusher)
        end
      end

      if ref_update.deleted?
        GitHub.context.push(callsite_location_datadog_tags: ["callsite:hydro_pr_push:after_branch_delete"]) do
          PullRequest.after_branch_delete(repository, ref_update.ref, pusher, ref_update.before)
        end
      end

      PushHandleMatchingPullRequestsJob.perform_later(repository_id, before: ref_update.before, after: ref_update.after, ref: ref_update.ref, pushed_at: pushed_at, pusher: pusher)
    end
  end

  private

  def update_merge_queue?(ref_update)
    return false unless ref_update.ref_is_branch?
    return false if GitHub.context[:from_merge_queue].present?
    return false unless repository.merge_queue_enabled_for_branch?(short_ref(ref_update.ref))
    return false if ref_update.deleted?

    true
  end

  # Update the merge queue after pushing code as it may have invalidated groups
  def update_merge_queue(ref_update)
    queue = repository.merge_queue_for(branch: short_ref(ref_update.ref))
    return if queue.blank?

    MergeQueues.execute!(repository, short_ref(ref_update.ref))
  end

  def short_ref(ref)
    ref.to_s.sub("refs/heads/", "")
  end
end
