# typed: strict
# frozen_string_literal: true

class HydroRepositoryHooksOnPushJob < Repositories::PushHydroMessageJob

  queue_as :hydro_repository_hooks_on_push

  sig { returns(T.nilable(T::Array[Repositories::RefUpdate])) }
  def perform
    ref_updates.each do |ref_update|
      if ref_update.created?
        Hook::Event::CreateEvent.queue(
          repository_id: repository_id,
          ref: ref_update.ref,
          pusher_id: pusher.id,
          triggered_at: Time.now,
        )
      end

      if ref_update.deleted?
        Hook::Event::DeleteEvent.queue(
          repository_id: repository_id,
          ref: ref_update.ref,
          pusher_id: pusher.id,
          triggered_at: Time.now,
        )
      end
    end
  end
end
