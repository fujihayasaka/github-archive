# typed: true
# frozen_string_literal: true

class PullRequests::Orchestrations::ResolveConflicts < PullRequestOrchestration
  include PullRequests::Orchestrations::DataAttributes

  data :user, User
  data :new_head_ref, String, required: false
  data :conflict_resolution_sha, String, required: false
  data :base_oid, String
  data :expected_head_oid, String
  data :resolve_conflicts, Hash, persisted: false

  step :validate_user_has_permissions do
    return unless pull_request = self.pull_request

    return if pull_request.head_ref_pushable_by?(user)
    if !pull_request.head_repository
      [:failed, "head repository does not exist"]
    else
      [:failed, "user doesn't have permission to update head repository"]
    end
  end

  # This step is only executed when we need to create a new head ref because writing
  # to the existing one would violate branch protection rules. This is an expensive
  # step as it creates a new git ref and calls synchronize! inline but this shouldn't happen often.
  step :create_new_head_ref do
    return unless new_head_ref

    return unless pull_request = self.pull_request
    return unless head_repository = pull_request.head_repository

    unless head_repository.writable_by?(user)
      return [:failed, "Head repository not writable by user"]
    end

    ref = head_repository.heads.create(new_head_ref, expected_head_oid, user)
    pull_request.update!(head_ref: new_head_ref)

    self.expected_head_oid = ref.target_oid
    pull_request.synchronize!(user: user, repo: T.must(pull_request.repository))
    pull_request.reload
  end

  # For performance reasons we perform the update in two steps: we build the commit and then write the commit.
  # This does the relatively cheap operation of building the merge commit synchronously for the resolved conflicts but it DOES NOT persist the merge commit.
  step :generate_merge_commit do
    return unless pull_request = self.pull_request

    # TODO(dzader): is this still necessary if we are no longer passing these params via the job queue
    conflict_resolutions = resolve_conflicts.transform_keys { CGI.unescape(_1) }

    mergeable, merge_commit_sha = PullRequest::Prepare.new(pull: pull_request, base_oid:, skip_rebase: true).perform(conflict_resolutions:)

    if !mergeable
      return [:skipped, "merge conflict not fully resolved"]
    end

    self.conflict_resolution_sha = merge_commit_sha
  rescue GitHub::UIError => e
    [:skipped, e.ui_message]
  rescue Git::Ref::RepositoryRuleViolationError => e
    [:failed, e.detailed_message]
  end

  job_start

  # This step asynchronously persists the merge commit sha that was generated in the previous steps.
  step :persist_merge_commit do
    return unless pull_request = self.pull_request

    update = PullRequest::Update.new(
      pull: pull_request,
      actor: user,
      author_email: user.default_author_email(pull_request.repository, pull_request.head_sha),
      expected_head_oid: expected_head_oid
    )

    update.persist_merge_commit(merge_commit_sha: conflict_resolution_sha, has_resolved_conflicts: true)
  rescue GitHub::UIError => e
    [:skipped, e.ui_message]
  rescue Git::Ref::RepositoryRuleViolationError => e
    [:failed, e.detailed_message]
  end
end
