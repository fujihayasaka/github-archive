# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::SponsorsPatreonUsersController < StafftoolsController
  before_action :sponsors_required

  def update
    spu = this_user.sponsors_patreon_user

    if spu
      spu.actor = current_user
      spu.sync_sponsors_patreon_user(include_sponsorships: spu.enabled_as_sponsorable?)
      flash[:notice] = "Successfully triggered a Patreon sync for this user."
    else
      flash[:error] = "Unable to find a sponsors Patreon account details for this user."
    end

    redirect_back(fallback_location: stafftools_user_path(this_user))
  end
end
