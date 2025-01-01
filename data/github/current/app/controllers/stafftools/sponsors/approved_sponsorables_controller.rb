# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::ApprovedSponsorablesController < StafftoolsController
  before_action :sponsors_required

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  # Returns rendered HTML list items used for autocompletion support
  def index
    approved_sponsors_listings = SponsorsListing.with_approved_state
      .includes(sponsorable: :profile)
      .matches_sponsorable_login(params[:q])
      .ordered_by_sponsorable_login
      .limit(10)
    render "stafftools/sponsors/approved_sponsorables/index", formats: :html, layout: false, locals: {
      approved_sponsors_listings: approved_sponsors_listings,
    }
  end
end
