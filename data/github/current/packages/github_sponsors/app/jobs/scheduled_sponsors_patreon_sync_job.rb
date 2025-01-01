# typed: strict
# frozen_string_literal: true

# This is a temporary hack until we get the webhooks working for syncing our data
# https://github.com/github/sponsors/issues/5302
class ScheduledSponsorsPatreonSyncJob < ApplicationJob
  extend T::Sig
  queue_as :patreon

  retry_on_dirty_exit

  sig { void }
  def perform
    return unless GitHub.sponsors_enabled?

    sponsors_patreon_users = SponsorsPatreonUser.enabled_as_sponsorable.includes(:user)
    GitHub::PrefillAssociations.prefill_batch_method(sponsors_patreon_users.map(&:user), :sponsorable?)

    sponsors_patreon_users.each(&:sync_sponsors_patreon_user)
  end
end
