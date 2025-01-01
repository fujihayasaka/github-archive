# typed: strict
# frozen_string_literal: true

class HydroSponsorsOnPushJob < Repositories::PushHydroMessageJob
  extend T::Sig

  queue_as :hydro_sponsors_on_push

  sig { void }
  def perform
    ref_updates.each do |ref_update|
      next unless ref_update.recordable?
      next unless ref_update.default_branch?
      next unless repository.repository_funding_links_enabled?
      next unless ref_update.funding_file_changed?


      repository.instrument_repo_funding_links_file_action(
        actor: pusher,
        funding_change_type: ref_update.funding_change_type
      )
    end
  end
end
