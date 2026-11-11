# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::Listing::RequireAdditionalReviewsController < Stafftools::SponsorsController
  def create
    if this_listing.can_require_additional_review?
      this_listing.require_additional_review!
      flash[:notice] = "Okay, #{this_sponsorable}'s GitHub Sponsors listing has been marked for additional review."
    else
      flash[:error] = "#{this_sponsorable}'s Sponsors listing cannot be marked for additional review."
    end

    redirect_to stafftools_sponsors_member_path(this_sponsorable)
  end
end
