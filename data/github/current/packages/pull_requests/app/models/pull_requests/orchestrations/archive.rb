# typed: true
# frozen_string_literal: true

class PullRequests::Orchestrations::Archive < PullRequestOrchestration
  include GitHub::Memoizer

  observability_feature_name :archive

  validate :can_archive?, on: :create

  def can_archive?
    pr = pull_request
    return errors.add(:base, :invalid, message: "Pull request not found") unless pr
    errors.add(:base, :invalid, message: "Cannot archive a merged pull request") if pr.merged?
    errors.add(:base, :invalid, message: "Pull request is already archived") if pr.archived?
  end

  step :close_and_lock do
    pr = T.must(pull_request)
    issue = T.must(pr.issue) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    close_success = Issues.domain.update_state(issue, Issues::State::Closed, actor)
    return [:failed, "Failed to close pull request while archiving"] unless close_success

    lock_success = Issues.domain.update_state(issue, Issues::State::Locked, actor)
    return [:failed, "Failed to lock pull request while archiving"] unless lock_success
  end

  step :mark_archived do
    pr = T.must(pull_request)
    PullRequests::KV.for_repository(T.must(pr.repository)).set(archive_key, "true")
  end

  job_start

  step :update_search_index do
    pr = T.must(pull_request)
    next unless FeatureFlag.vexi.enabled?(:archive_pull_request_search_sync, T.must(pr.repository), default: false)

    Search.add_to_search_index("pull_request", T.must(pull_request_id))
  end

  sig { returns(User) }
  memoize def actor
    User.find(data[:actor_id])
  end

  private

  sig { returns(String) }
  def archive_key
    "#{PullRequest::ArchiveDependency::KV_KEY_PREFIX}#{pull_request_id}"
  end
end
