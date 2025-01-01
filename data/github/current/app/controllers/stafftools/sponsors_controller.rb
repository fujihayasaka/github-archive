# typed: true
# frozen_string_literal: true

class Stafftools::SponsorsController < StafftoolsController
  before_action :sponsors_required
  before_action :sponsors_listing_required

  protected

  memoize def sponsorable_login_param
    params[:member_id] || params[:id]
  end

  memoize def this_listing
    this_sponsorable&.sponsors_listing
  end

  memoize def this_sponsorable
    User.find_by(login: sponsorable_login_param) if sponsorable_login_param
  end

  def sponsors_listing_required
    render_404 unless this_listing
  end

  def stripe_connect_account_required
    render_404 unless this_listing&.stripe_transfers_enabled?
  end
end
