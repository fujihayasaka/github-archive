# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::IgnoresController < Stafftools::SponsorsController
  def create
    this_listing.ignore!(actor: current_user) unless this_listing.ignored?
    flash[:notice] = "Ignored Sponsors profile for #{this_sponsorable.login}."
    redirect_to stafftools_sponsors_member_path(this_sponsorable)
  end

  def destroy
    this_listing.unignore!(actor: current_user) if this_listing.ignored?
    flash[:notice] = "Un-ignored Sponsors profile for #{this_sponsorable.login}."
    redirect_to stafftools_sponsors_member_path(this_sponsorable)
  end
end
