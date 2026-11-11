# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::BulkBansController < StafftoolsController
  before_action :sponsors_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    sponsors_listings = SponsorsListing.without_banned_state.includes(sponsorable: :profile)
      .matches_sponsorable_login(params[:q])
    render "stafftools/sponsors/bulk_bans/index", formats: :html, layout: false, locals: {
      sponsors_listings: sponsors_listings,
    }
  end

  def create
    result = Stafftools::Sponsors::BanSponsorsListings.call(
      sponsorable_logins: sponsorable_logins,
      actor: current_user,
      ban_reason: allowed_params[:banned_reason],
    )

    if result.success?
      flash[:notice] = result.message
    else
      flash[:error] = result.message
    end

    redirect_to stafftools_sponsors_members_path(redirect_params)
  end

  private

  memoize def allowed_params
    params.permit(:authenticity_token, :sponsorables_autocomplete, :banned_reason, :query, :order,
      sponsorable_logins: [], filter: Stafftools::Sponsors::MembersController::PERMITTED_FILTER_PARAMS)
  end

  memoize def sponsorable_logins
    (allowed_params[:sponsorable_logins] || []).select(&:present?).uniq
  end

  def redirect_params
    allowed_params.slice(:query, :order, :filter)
  end
end
