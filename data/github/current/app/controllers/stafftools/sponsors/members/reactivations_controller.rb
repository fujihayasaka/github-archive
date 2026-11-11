# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::ReactivationsController < Stafftools::SponsorsController
  def create
    if this_listing.draft?
      flash[:notice] = "#{this_sponsorable}'s Sponsors listing is already in draft state."
    elsif !this_listing.can_reactivate?
      flash[:error] = "Cannot move Sponsors listing in state #{this_listing.current_state_name} " \
        "to draft."
    elsif this_listing.reactivate!
      flash[:notice] = "#{this_sponsorable}'s Sponsors listing is now in draft state."
    else
      flash[:error] = "Could not move Sponsors listing for #{this_sponsorable} to draft state."
    end

    redirect_to(stafftools_sponsors_member_path(this_sponsorable))
  end
end
