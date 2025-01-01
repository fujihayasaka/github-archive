# typed: true
# frozen_string_literal: true

class HydroIssuesOnPushJob < Repositories::PushHydroMessageJob
  use_primaries ApplicationRecord::IssuesPullRequests, # issue_events
                ApplicationRecord::Mysql2 # notification_thread_subscriptions

  queue_as :hydro_issues_on_push

  def perform
    return if large_push? # skip large pushes

    ref_updates.each do |ref_update|
      next if ref_update.large_push?

      valid_deleted_branch_ref = ref_update.deleted? && ref_update.ref.start_with?("refs/heads/") && ref_update.branch_name.length > 0
      current_user = User.find_by_login(GitHub.context[:actor])

      if valid_deleted_branch_ref
        BranchIssueReference.destroy_in_background(repository: repository, branch_name: ref_update.branch_name)
      end

      integrate_issues(ref_update)
    end
  end

  def integrate_issues(ref_update)
    commits = ref_update.commits_pushed
    commits.each do |commit|
      close_or_reference_issue(commit, ref_update)
    end
  end

  def issue_readable_by?(pusher, issue)
    # Fall back to naive permission check if pusher lacks API context.
    return issue.readable_by?(pusher) if pusher_lacks_api_context

    ActiveRecord::Base.connected_to(role: :reading) do
      Platform::Security::RepositoryAccess.with_viewer(pusher) do
        AccessControl.new(viewer: pusher).can_access?(issue)
      end.sync
    end
  rescue Platform::Errors::Forbidden
    false
  rescue Platform::Errors::NotFound
    false
  end

  def issue_closable_by?(pusher, issue)
    # Fall back to naive permission check if pusher lacks API context.
    return issue.repository.pushable_by?(pusher) if pusher_lacks_api_context

    ActiveRecord::Base.connected_to(role: :reading) do
      Platform::Security::RepositoryAccess.with_viewer(pusher) do
        AccessControl.new(viewer: pusher).typed_can_modify?("CloseIssue", issue: issue)
      end.sync
    end
  rescue Platform::Errors::Forbidden
    false
  rescue Platform::Errors::NotFound
    false
  end

  def commit_is_year_older?(issue, commit)
    seconds = issue.created_at - commit.created_at
    seconds > 1.year
  end

  def close_or_reference_issue(commit, ref_update)
    commit.context_user(pusher)

    commit.issue_references.each do |reference|
      issue = reference.issue

      # The pusher is the only actor we can trust to reference issues.
      # We used to allow the commit author/committer but those can be
      # trivially spoofed.
      next if pusher.nil? || pusher.ghost?

      # ignore commits that are a year older than the referenced issue
      next if commit_is_year_older?(issue, commit)

      # Locked issues shouldn't be spammed by commit references, unless they are closing the issue
      next if issue.locked? && !reference.close?

      # closing references only count when they're for issues the
      # pusher has write access to (and not on a parent of this repo)
      # and the commit is on the default or gh-pages branch.
      #
      # otherwise, these are just considered normal references.
      if (ref_update.default_branch? || ref_update.pages_branch?) &&
          !issue.closed? && reference.close? &&
          issue_closable_by?(pusher, issue) &&
          !repository.parents.include?(issue.repository)
        ActiveRecord::Base.connected_to(role: :writing) do
          issue.close(pusher, attributes: { commit: { id: commit.oid, repository: repository } })
        end
      # Only create a 'referenced' event if the issue is readable by the pusher and
      # the commit is not a merge commit of the (pull request) issue. The 'referenced' event is already
      # created in a PullRequests::Orchestrations::Merge step.
      elsif issue_readable_by?(pusher, issue) && !pr_issue_with_merge_commit?(issue, commit)
        issue.reference_from_commit(pusher, commit.oid, repository)
      end
    end
  end

  def pr_issue_with_merge_commit?(issue, commit)
    issue.pull_request? && issue.pull_request.merge_commit_sha == commit.oid
  end

  class AccessControl < Platform::Authorization::Permission
    attr_reader :env

    def initialize(context)
      context[:origin] = Platform::ORIGIN_API
      context[:response] = Sinatra::Response.new
      @env = {}
      super
    end

    def graphql_request?
      false
    end
  end
end
