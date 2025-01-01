# typed: strict
# frozen_string_literal: true

class SyncSponsorsPatreonUserJob < ApplicationJob
  extend T::Sig
  queue_as :patreon

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  # How many minutes should we wait before allowing another job with the same arguments to be run again?
  LOCKOUT_IN_MINUTES = 5

  locked_by timeout: LOCKOUT_IN_MINUTES.minutes, key: DEFAULT_LOCK_PROC

  sig do
    params(
      sponsors_patreon_user: SponsorsPatreonUser,
      actor: T.nilable(User),
    ).void
  end
  def perform(sponsors_patreon_user, actor: nil)
    if actor
      GitHub.context.push(actor_id: actor.id)
    elsif GitHub.context[:actor_id].present?
      actor = User.find_by(id: GitHub.context[:actor_id])
    end

    ActiveRecord::Base.connected_to(role: :writing) do
      SyncSponsorsPatreonUser.call(sponsors_patreon_user: sponsors_patreon_user)
    end

    if sponsors_patreon_user.subscribe_to_webhooks?
      ActiveRecord::Base.connected_to(role: :writing) do
        SyncSponsorsPatreonWebhooks.call(sponsors_patreon_user: sponsors_patreon_user)
      end
    end
  end
end
