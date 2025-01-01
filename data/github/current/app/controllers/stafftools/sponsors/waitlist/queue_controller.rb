# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Waitlist::QueueController < StafftoolsController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    after = params[:after]

    listings = SponsorsListing
    listings = listings.after_listing(after) if after
    listings = listings.waitlist_queue # load last since it grabs sponsorable_ids from scoped query
      .includes(:sponsorable).paginate(page: current_page, per_page: 1)
    listing = listings.first

    manual_criteria = if listing
      scope = SponsorsMembershipsCriterion.manual.includes(:sponsors_criterion)
        .where(sponsors_listing_id: listing)
    end

    render "stafftools/sponsors/waitlist/queue/index", layout: "application", locals: {
      listing: listing,
      listings: listings,
      manual_criteria: manual_criteria,
    }
  end
end
