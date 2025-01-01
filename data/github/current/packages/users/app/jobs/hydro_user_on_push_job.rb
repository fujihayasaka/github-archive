# typed: true
# frozen_string_literal: true

class HydroUserOnPushJob < Repositories::PushHydroMessageJob
  extend T::Sig

  queue_as :hydro_user_on_push

  sig { void }
  def perform
    # Interaction.enabled? is only true for GHES, and thus this job only runs in GHES.
    # There is no bridge config for this job in place for dotcom, so it shouldn't ever be queued there.
    return unless Interaction.enabled?

    ref_updates.each do |ref_update|
      next unless ref_update.recordable?

      Interaction.track_push(pusher)
    end
  end
end
