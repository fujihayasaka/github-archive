# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::BansController < Stafftools::SponsorsController
  def create
    this_listing.actor = current_user
    success = this_listing.banned? || this_listing.ban!(banned_reason: params[:banned_reason])

    if success
      flash[:notice] = "Successfully banned #{this_sponsorable} from the Sponsors program"
    else
      reason = this_listing&.halted_because
      flash[:error] = "Could not ban #{this_sponsorable} from the Sponsors program: #{reason}"
    end

    redirect_to stafftools_sponsors_member_path(this_sponsorable)
  end

  def destroy
    this_listing.actor = current_user
    success = !this_listing.banned? || this_listing.un_ban!

    if success
      flash[:notice] = "Successfully un-banned #{this_sponsorable} from the Sponsors program"
    else
      reason = this_listing&.halted_because
      flash[:error] = "Could not unban #{this_sponsorable} from the Sponsors program: #{reason}"
    end

    redirect_to stafftools_sponsors_member_path(this_sponsorable)
  end
end
