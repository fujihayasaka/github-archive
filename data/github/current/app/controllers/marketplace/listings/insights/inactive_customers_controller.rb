# typed: true
# frozen_string_literal: true

class Marketplace::Listings::Insights::InactiveCustomersController < ApplicationController

  before_action :login_required
  before_action :marketplace_required
  before_action :permission_to_edit_listing_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    respond_to do |format|
      format.csv do
        report = Marketplace::InactiveCustomersReport.new(listing: listing)
        send_data(report.as_csv, type: "text/csv", filename: report.filename)
      end

      format.all { render_404 }
    end
  end

  private

  def permission_to_edit_listing_required
    render_404 unless listing.allowed_to_edit?(current_user)
  end

  memoize def listing
    Marketplace::Listing.find_by(slug: params[:listing_slug])
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless listing # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    listing.owner
  end
end
