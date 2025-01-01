# typed: strict
# frozen_string_literal: true

class SyncPatreonSponsorshipsJob < ApplicationJob
  extend T::Sig
  queue_as :patreon_sponsorships

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  # How many minutes should we wait before allowing another job with the same arguments to be run again?
  LOCKOUT_IN_MINUTES = SyncSponsorsPatreonUserJob::LOCKOUT_IN_MINUTES

  locked_by timeout: LOCKOUT_IN_MINUTES.minutes, key: DEFAULT_LOCK_PROC

  DATADOG_PREFIX = CancelPatreonSponsorships::DATADOG_PREFIX

  sig do
    params(
      sponsors_patreon_user: SponsorsPatreonUser,
      actor: T.nilable(User),
      membership_page_cursors_by_campaign_id: T::Hash[String, String],
      max_membership_pages: T.nilable(Integer),
      target_sponsorship_cents_by_sponsor_id: T::Hash[String, Integer]
    ).void
  end
  def perform(sponsors_patreon_user, actor: nil, membership_page_cursors_by_campaign_id: {}, max_membership_pages: nil, target_sponsorship_cents_by_sponsor_id: {})
    if actor
      GitHub.context.push(actor_id: actor.id)
    elsif GitHub.context[:actor_id].present?
      actor = User.find_by(id: GitHub.context[:actor_id])
    end

    # CreateAndUpdatePatreonSponsorships#call will raise an exception if given a SponsorsPatreonUser for a
    # non-sponsorable account. Nothing to be done, and we don't need to clutter Sentry with errors about jobs enqueued
    # before a SponsorsListing changed away from state=approved.
    return unless sponsors_patreon_user.approved_sponsors_listing?

    sponsorable = sponsors_patreon_user.user
    is_later_batch = membership_page_cursors_by_campaign_id.present?


    if is_later_batch
      GitHub.dogstats.increment("#{DATADOG_PREFIX}.multiple_membership_batches")
      GitHub.logger.info("Processing later batch of Patreon sponsorships",
        "gh.catalog_service": "github/github_sponsors",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "sponsorable.id": sponsors_patreon_user.user_id,
        "actor.id": actor&.id,
        "patreon.membership_page_cursors_by_campaign_id": membership_page_cursors_by_campaign_id,
        "patreon.target_sponsorship_cents_by_sponsor_id": target_sponsorship_cents_by_sponsor_id,
      )
    end

    max_membership_pages ||= 20

    data = SponsorsPatreonSponsorshipLoader.call(
      sponsors_patreon_user: sponsors_patreon_user,
      membership_page_cursors_by_campaign_id: membership_page_cursors_by_campaign_id,
      max_membership_pages: max_membership_pages,
      # Have to take String keys for the job in order for the hash parameter to be serializable, but the service model
      # expects Integer keys:
      target_sponsorship_cents_by_sponsor_id: target_sponsorship_cents_by_sponsor_id
        .map { |sponsor_id, cents| [sponsor_id.to_i, cents] }.to_h,
    )

    ActiveRecord::Base.connected_to(role: :writing) do
      CreateAndUpdatePatreonSponsorships.call(sponsors_patreon_user: sponsors_patreon_user, data: data, actor: actor)
    end

    if data.sponsorships_to_cancel.present?
      write_mode = (!data.has_another_page_of_memberships?) &&  # there are no more pages of memberships to process or
        !is_later_batch                                         # this is the first batch of memberships

      ActiveRecord::Base.connected_to(role: :writing) do
        CancelPatreonSponsorships.call(sponsors_patreon_user: sponsors_patreon_user,
          sponsorships_to_cancel: data.sponsorships_to_cancel, actor: actor, write_mode: write_mode)
      end
    end

    if data.has_another_page_of_memberships?
      # Enqueue the job to process the next batch of memberships:
      self.class.perform_later(sponsors_patreon_user,
        actor: actor,
        membership_page_cursors_by_campaign_id: data.membership_next_page_cursors_by_campaign_id,
        max_membership_pages: max_membership_pages,
        target_sponsorship_cents_by_sponsor_id: target_sponsorship_cents_by_sponsor_id.merge(
          data.target_sponsorship_cents_by_sponsor_id
            .map { |sponsor_id, cents| [sponsor_id.to_s, cents] } # job requires String keys for hash args
            .to_h,
        ),
      )
    end
  end
end
