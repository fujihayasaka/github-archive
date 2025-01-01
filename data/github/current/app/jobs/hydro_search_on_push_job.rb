# typed: true
# frozen_string_literal: true

class HydroSearchOnPushJob < Repositories::PushHydroMessageJob

  queue_as :hydro_search_on_push

  sig { void }
  def perform
    ref_updates.each do |ref_update|
      if ref_update.default_branch?
        payload = {
          change: :PUSHED,
          repository: repository,
          ref: ref_update.ref,
          updated_at: Time.now.utc,
          actor: pusher
        }
        GlobalInstrumenter.instrument("search_indexing.repository_changed", payload)
        GitHub.dogstats.increment("geyser.repo_changed_event.published", tags: ["change_type:pushed"])
      end
    end
  end
end
