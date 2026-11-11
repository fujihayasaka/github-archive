# typed: true
# frozen_string_literal: true

class Biztools::MarketplaceListingSubscriptionsController < BiztoolsController

  depends_on_clusters ApplicationRecord::Mysql1,
  ApplicationRecord::Collab,
  ApplicationRecord::Mysql2,
  ApplicationRecord::NotificationsEntries,
  ApplicationRecord::Mysql5,
  ApplicationRecord::IamAbilities,
  ApplicationRecord::Repositories,
  ApplicationRecord::Billing,
  only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
  only: [:index], optional: true

  before_action :marketplace_required
  before_action :marketplace_listing_required

  def index
    # We have to use includes here to avoid N+1 queries when generating the CSV report
    listing = Marketplace::Listing.includes(
      subscription_items: [
        { plan_subscription: { user: :primary_user_email } },
        :subscribable
      ]
    ).find_by(id: params[:listing_id])

    report = Biztools::SubscriptionsReport.new(listing: listing)
    send_data(report.as_csv, type: "text/csv", filename: report.filename)
  end

  private

  memoize def this_marketplace_listing
    Marketplace::Listing.find_by(id: params[:listing_id])
  end

  def marketplace_listing_required
    render_404 unless this_marketplace_listing
  end

  def target_for_conditional_access
    # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    return :no_target_for_conditional_access unless this_marketplace_listing
    this_marketplace_listing.owner
  end
end
