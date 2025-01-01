# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class HydroStratocasterOnPushJob < Repositories::PushHydroMessageJob
  queue_as :hydro_stratocaster_on_push

  sig { void }
  def perform
    ref_updates.each do |ref_update|
      if ref_update.created?
        GitHub.stratocaster.queue(Stratocaster::Event::CREATE_EVENT, repository_id, ref_update.ref, pusher.id)
      end

      if ref_update.deleted?
        GitHub.stratocaster.queue(Stratocaster::Event::DELETE_EVENT, repository_id, ref_update.ref, pusher.id)
      end
    end
  end
end
