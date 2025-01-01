# typed: strict
# frozen_string_literal: true

class Sponsors::YourSponsorsController < ApplicationController
  extend T::Sig
  include Sponsors::AdminableControllerValidations

  PER_PAGE = 16

  before_action :non_waitlisted_sponsors_listing_required
  before_action :require_acceptance_into_sponsors_program

  layout "layouts/sponsors"

  stylesheet_bundle :sponsors

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  sig { void }
  def index
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#non_waitlisted_sponsors_listing_required ensures non-nil"
    end
    published_tiers = listing.published_sponsors_tiers.to_a
    retired_tiers = listing.retired_sponsors_tiers.with_active_sponsorships.to_a
    custom_tiers = listing.unique_custom_tiers.to_a

    sponsorable = T.must_because(self.sponsorable) { "#sponsorable_required ensures non-nil" }
    tier_subscription_counts = sponsorable.tier_subscription_counts(custom_tier_ids: custom_tiers&.map(&:id))

    render "sponsors/your_sponsors/index", locals: {
      sponsorable: sponsorable,
      sponsors_listing: listing,
      sponsorships: sponsorships,
      sponsorships_total_count: sponsorships.size,
      selected_tier_ids: Array.wrap(selected_tier&.id),
      published_tiers: published_tiers,
      retired_tiers: retired_tiers,
      custom_tiers: custom_tiers,
      tier_subscription_counts: tier_subscription_counts,
    }
  end

  private

  sig { returns T.any(Symbol, GitHubSponsors::Types::Sponsorable) }
  def target_for_conditional_access
    sponsorable || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  sig { returns T::Array[Sponsorship] }
  memoize def sponsorships
    sponsorable = T.must_because(self.sponsorable) { "#sponsorable_required ensures non-nil" }
    result = Sponsorship.all_active_as_sponsorable(sponsorable: sponsorable, tier: selected_tier)
    result = T.unsafe(result).with_linked_org_preloads
      .order(subscribable_selected_at: :desc, created_at: :desc)
      .paginate(page: current_page, per_page: PER_PAGE)
      .preload(:sponsor, :tier, subscription_item: :subscribable)
      .to_a
    GitHub::PrefillAssociations.prefill_batch_method(result, :via_bulk_sponsorship?)
    result
  end

  sig { returns T.nilable(SponsorsTier) }
  memoize def selected_tier
    if params[:tier_id].present?
      listing = T.must_because(sponsorable_sponsors_listing) do
        "#non_waitlisted_sponsors_listing_required ensures non-nil"
      end
      listing.sponsors_tiers.with_states(:published, :retired, :custom).find_by(id: params[:tier_id])
    end
  end
end
