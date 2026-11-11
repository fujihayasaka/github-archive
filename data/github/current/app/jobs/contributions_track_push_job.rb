# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class ContributionsTrackPushJob < ApplicationJob
  queue_as :contributions_track_push

  locked_by timeout: 1.hour, key: ->(job) {
    push = job.arguments[0]
    keyword_args = job.arguments[1]
    repository = keyword_args&.is_a?(Hash) ? keyword_args[:repository] : nil

    # Extract repository from either call pattern
    repo = repository || push&.repository

    # Use repository-only locking when feature flag is enabled
    if repo && FeatureFlag.vexi.enabled?(:contributions_track_push_lock_by_repository, repo, default: false)
      repo.id
    else
      # Fall back to default behavior (lock on all arguments)
      DEFAULT_LOCK_PROC.call(job)
    end
  }

  resolve_tenant_context do |push, args|
    if args[:repository]
      Repositories::Public.resolve_tenant(id: args[:repository]&.id)
    elsif push
      Repositories::Public.resolve_tenant(id: push.repository&.id)
    end
  end

  def perform(push, repository: nil, before: nil, after: nil, ref: nil, pusher: nil)
    if push.nil?
      push = Repositories::RefUpdate.from_args(repository:, before:, after:, ref:, pusher:)
    end

    Failbot.push(
      repo_id: push.repository&.id,
      before: push.before,
      after: push.after,
    )

    with_write do
      CommitContribution.throttle { CommitContribution.track_push!(push) }
    end
  end
end
