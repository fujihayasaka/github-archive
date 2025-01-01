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
    if GitHub.flipper[:log_commit_event_attribution].enabled? && ref_update.repository.owner&.display_login == "github"
      GitHub.logger.info(
        "HydroIssuesOnPushJob triggered",
        "gh.ref": ref_update.ref,
        "gh.ref.commits.count": commits.count,
        "gh.ref.commits.oid": commits.map(&:oid).join(", ")
      )
    end

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

      issue_readable_by_pusher = issue_readable_by?(pusher, issue)

      # Log for the GitHub repo specifically
      if issue&.repository&.owner&.feature_enabled?(:log_commit_event_attribution_for_repo_owner)
        if issue.locked? || issue.closed? || !issue_readable_by_pusher
          GitHub.logger.info(
            "HydroIssuesOnPushJob will not create a reference",
            "gh.commit.oid": commit.oid,
            "gh.commit.author.is_pusher": commit.author_actors.include?(pusher),
            "gh.commit.repository.id": commit.repository.id,
            "gh.commit.in_merge_queue": issue.repository.merge_queue_commits_include?(commit.oid),
            "gh.issue.id": issue.id,
            "gh.issue.repository.id": issue.repository.id,
            "gh.issue.locked": issue.locked?,
            "gh.issue.closed": issue.closed?,
            "gh.issue.readable": issue_readable_by_pusher,
            "gh.reference_exists": issue.events.where(commit_id: commit.oid, event: "referenced").exists?,
            "gh.pusher_lacks_api_context": pusher_lacks_api_context,
            "gh.pusher.is_user": pusher.is_a?(User),
            "gh.pusher.ip_address": GitHub.context[:actor_ip].to_s,
            "gh.pusher.name": pusher.display_login,
          )
        end
      end

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
      elsif issue_readable_by_pusher && !pr_issue_with_merge_commit?(issue, commit)
        event = issue.reference_from_commit(pusher, commit.oid, repository)
        if issue&.repository&.owner&.feature_enabled?(:log_commit_event_attribution_for_repo_owner)
          if event.present?
            # If the commit author and the pusher don't match
            GitHub.logger.info(
              "HydroIssuesOnPushJob not triggered by the commit author",
              "gh.commit.author.is_pusher": commit.author_actors.include?(pusher),
              "gh.commit.oid": commit.oid,
              "gh.commit.repository.id": commit.repository.id,
              "gh.issue.repository.id": commit.repository.id,
              "gh.pusher.name": pusher.display_login,

            ) unless commit.author_actors.include?(pusher)
          else
            # If reference_from_commit failed log the early exit reasons
            GitHub.logger.info(
              "HydroIssuesOnPushJob failed calling issue.reference_from_commit",
              "gh.commit.author.is_pusher": commit.author_actors.include?(pusher),
              "gh.commit.in_merge_queue": issue.repository.merge_queue_commits_include?(commit.oid),
              "gh.commit.oid": commit.oid,
              "gh.commit.repository.id": commit.repository.id,
              "gh.issue.repository.id": commit.repository.id,
              "gh.reference_exists": issue.events.where(commit_id: commit.oid, event: "referenced").exists?,
              "gh.pusher.name": pusher.display_login,
            )
          end
        end

        event
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
      context[:ip] = GitHub.context[:actor_ip]
      @env = {}
      super
    end

    def graphql_request?
      false
    end
  end
end
