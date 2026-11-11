# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::FindListingController < Stafftools::SponsorsController
  skip_before_action :sponsors_listing_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    only: [:show]

  def show
    if listing = SponsorsListing.find_by(id: params[:id])
      redirect_to stafftools_sponsors_member_path(listing.sponsorable)
    else
      flash[:error] = "Couldn't find that Sponsors listing."
      redirect_to stafftools_sponsors_members_path
    end
  end
end
