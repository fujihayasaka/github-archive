# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::RequestApprovalsController < Stafftools::SponsorsController
  def destroy
    if this_listing.can_cancel_approval_request?
      this_listing.cancel_approval_request!
      flash[:notice] = "Okay, the approval request for #{this_sponsorable} has been canceled."
    else
      flash[:error] = "An approval request for #{this_sponsorable} could not be canceled."
    end

    redirect_to stafftools_sponsors_member_path(this_sponsorable)
  end
end
