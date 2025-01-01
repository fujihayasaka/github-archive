# typed: strict
# frozen_string_literal: true

class BanSponsorsListingJob < ApplicationJob
  class BanError < StandardError; end
  extend T::Sig

  queue_as :sponsors_application_processing

  retry_on_dirty_exit

  sig do
    params(
      sponsors_listing: T.nilable(SponsorsListing),
      actor: T.nilable(User),
      ban_reason: T.nilable(String),
      automated: T::Boolean,
    ).void
  end
  def perform(sponsors_listing:, actor:, ban_reason:, automated: false)
    return unless GitHub.sponsors_enabled?
    return unless sponsors_listing && actor && ban_reason.present?
    return if sponsors_listing.banned?

    sponsors_listing.actor = actor

    SponsorsListing.throttle_writes_with_retry do
      # The Tapioca DSL compiler for Workflow doesn't support events with parameters (yet?)
      T.unsafe(sponsors_listing).ban!(banned_reason: ban_reason, automated: automated)
    end
  end
end
