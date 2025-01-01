# typed: true
# frozen_string_literal: true

class ContributionsTrackPushJob < ApplicationJob
  queue_as :contributions_track_push

  locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC

  resolve_tenant_context do |push, args|
    if args[:repository]
      Repositories::Public.resolve_tenant(id: args[:repository]&.id)
    elsif push
      Repositories::Public.resolve_tenant(id: push.repository&.id)
    end
  end

  def perform(push, repository: nil, before: nil, after: nil, ref: nil, pusher: nil)
    if push.nil?
      push = Repositories::RefUpdate.new(repository:, before:, after:, ref:, pusher:)
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
