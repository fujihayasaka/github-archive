# typed: true
# frozen_string_literal: true

class HydroReleasesOnPushJob < Repositories::PushHydroMessageJob
  use_primaries ApplicationRecord::Repositories # needed for updating releases

  queue_as :hydro_releases_on_push

  sig { void }
  def perform
    ref_updates.each do |ref_update|
      handle_tag_update(ref_update) if ref_update.ref_is_tag?
    end
  end

  private

  sig { params(ref_update: Repositories::RefUpdate).void }
  def handle_tag_update(ref_update)
    return unless ref_update.ref_is_tag?
    return unless rel = repository.releases.find_by(tag_name: ref_update.tag_name)
    rel.state = :draft if ref_update.deleted?
    rel.save
  end
end
