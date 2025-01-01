# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::Listing::MatchTogglesController < Stafftools::SponsorsController
  def create
    begin
      this_listing.actor = current_user
      this_listing.enable_sponsors_match!
      flash[:notice] = "Enabled match for #{this_sponsorable}."
    rescue ActiveRecord::RecordInvalid => error
      flash[:error] = "Failed to enable match for #{this_sponsorable}: #{error.message}"
    end

    redirect_to stafftools_sponsors_member_path(this_sponsorable)
  end

  def destroy
    begin
      this_listing.actor = current_user
      this_listing.disable_sponsors_match!(reason: params[:disable_reason])
      flash[:notice] = "Disabled match for #{this_sponsorable}."
    rescue ActiveRecord::RecordInvalid => error
      flash[:error] = "Failed to disable match for #{this_sponsorable}: #{error.message}"
    end

    redirect_to stafftools_sponsors_member_path(this_sponsorable)
  end
end
