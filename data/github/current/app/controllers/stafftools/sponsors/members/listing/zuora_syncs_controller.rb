# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::Listing::ZuoraSyncsController < Stafftools::SponsorsController
  def create
    if this_listing.approved?
      SponsorsListingZuoraSyncJob.perform_later(this_listing)

      flash[:notice] = "Zuora sync for #{this_sponsorable}'s listing has been scheduled"
    else
      state = this_listing.current_state_name.to_s.humanize.downcase
      flash[:error] = "Not synchronizing #{this_sponsorable}'s #{state} listing"
    end

    redirect_to(stafftools_sponsors_member_path(this_sponsorable))
  end
end
