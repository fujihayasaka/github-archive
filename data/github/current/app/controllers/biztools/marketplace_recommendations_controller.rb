# typed: true
# frozen_string_literal: true

class Biztools::MarketplaceRecommendationsController < BiztoolsController

  before_action :marketplace_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    listings = if raw_ids = GitHub.kv.get("marketplace/recommendations").value! # rubocop:todo GitHub/DoNotUseGlobalKv
      Marketplace::Listing.where(id: JSON.parse(raw_ids)).with_state(:verified)
    else
      Marketplace::Listing.none
    end

    render "biztools/marketplace_recommendations/index", locals: { recommended_marketplace_apps: listings }
  end

  def update
    listing_ids = Marketplace::Listing
      .with_state(:verified)
      .where(slug: recommended_slug_params)
      .pluck(:id)

    GitHub.kv.set("marketplace/recommendations", listing_ids.to_json) # rubocop:todo GitHub/DoNotUseGlobalKv

    redirect_to biztools_marketplace_recommendations_path
  end

  def destroy
    listing = Marketplace::Listing.find_by(slug: params[:listing_slug])
    return render_404 unless listing && listing.allowed_to_edit?(current_user)

    raw_ids = GitHub.kv.get("marketplace/recommendations").value! # rubocop:todo GitHub/DoNotUseGlobalKv
    return render_404 unless raw_ids

    listing_ids = JSON.parse(raw_ids).reject { |id| id == listing.id }
    GitHub.kv.set("marketplace/recommendations", listing_ids.to_json) # rubocop:todo GitHub/DoNotUseGlobalKv

    redirect_to biztools_marketplace_recommendations_path
  end

  private

  def recommended_slug_params
    params.require(:marketplace_recommendations).require(:marketplace_listing_slugs)
  end
end
