# typed: strict
# frozen_string_literal: true

class Sponsors::FiscalHostsController < ApplicationController
  extend T::Sig
  include Sponsors::AdminableControllerValidations

  before_action :non_waitlisted_sponsors_listing_required
  before_action :require_acceptance_into_sponsors_program
  before_action :fiscal_host_sponsors_listing_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  CHILD_LISTINGS_PER_PAGE = 20

  layout "layouts/sponsors"

  stylesheet_bundle :sponsors

  sig { void }
  def show
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#non_waitlisted_sponsors_listing_required ensures non-nil"
    end
    child_listings = listing
      .child_listings
      .with_approved_state
      .preload(sponsorable: :profile)
      # Include `filter_spam_for` as the last scope since it will run queries itself on the already-scoped
      # query, so we want that set of sponsorships to be as small as possible:
      .filter_spam_for(current_user)
      .ordered_by_sponsorable_login
      .paginate(page: current_page, per_page: CHILD_LISTINGS_PER_PAGE)
    child_listing_sponsor_counts = Sponsorship
      .sponsor_counts_by_listing_id(child_listings.map(&:id), viewer: current_user)

    if pjax?
      render partial: "sponsors/fiscal_hosts/child_listings", locals: {
        child_listings: child_listings,
        sponsor_counts: child_listing_sponsor_counts,
      }, layout: false
    else
      render "sponsors/fiscal_hosts/show", locals: {
        sponsorable: sponsorable,
        sponsors_listing: listing,
        child_listings: child_listings,
        child_listing_sponsor_counts: child_listing_sponsor_counts,
      }
    end
  end

  private

  sig { returns T.any(Symbol, GitHubSponsors::Types::Sponsorable) }
  def target_for_conditional_access
    sponsorable || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
