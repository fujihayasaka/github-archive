# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::Listing::DisablesController < Stafftools::SponsorsController
  def create
    if this_listing.can_disable?
      this_listing.actor = current_user
      this_listing.disable!
      flash[:notice] = "Okay, #{this_sponsorable}'s GitHub Sponsors listing has been disabled."
    else
      flash[:error] = "#{this_sponsorable}'s Sponsors listing cannot be disabled."
    end

    redirect_to stafftools_sponsors_member_path(this_sponsorable)
  end
end
