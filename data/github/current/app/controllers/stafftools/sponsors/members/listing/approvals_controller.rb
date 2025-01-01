# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::Listing::ApprovalsController < Stafftools::SponsorsController
  def create
    result = Sponsors::ApproveSponsorsListing.call(sponsors_listing: this_listing,
      actor: current_user)

    if result.success?
      flash[:notice] = "Approved #{this_sponsorable}'s GitHub Sponsors profile!"
    else
      flash[:error] = result.errors.to_sentence
    end

    redirect_to stafftools_sponsors_member_path(this_sponsorable)
  end

  def destroy
    if this_listing.can_unpublish?
      this_listing.actor = current_user
      this_listing.unpublish!

      flash[:notice] = "Unpublished #{this_sponsorable}'s GitHub Sponsors profile!"
    else
      flash[:error] = "#{this_sponsorable}'s GitHub Sponsors profile cannot be unpublished."
    end

    redirect_to stafftools_sponsors_member_path(this_sponsorable)
  end
end
