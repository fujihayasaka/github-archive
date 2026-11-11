# typed: true
# frozen_string_literal: true

class PullRequests::Orchestrations::Unarchive < PullRequestOrchestration
  include GitHub::Memoizer

  observability_feature_name :unarchive

  validate :can_unarchive?, on: :create

  def can_unarchive?
    pr = pull_request
    return errors.add(:base, :invalid, message: "Pull request not found") unless pr
    errors.add(:base, :invalid, message: "Cannot unarchive a merged pull request") if pr.merged?
    errors.add(:base, :invalid, message: "Pull request is not archived") unless pr.archived?
  end

  step :remove_archived do
    pr = T.must(pull_request)
    PullRequests::KV.for_repository(T.must(pr.repository)).del(archive_key)
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
