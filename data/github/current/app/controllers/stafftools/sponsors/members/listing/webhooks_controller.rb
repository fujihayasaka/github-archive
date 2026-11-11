# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::Listing::WebhooksController < Stafftools::SponsorsController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    render "stafftools/sponsors/members/listing/webhooks/show",
      layout: "application",
      locals: {
        hook: hook,
        sponsors_listing: this_listing,
        hook_deliveries_query: params[:deliveries_q],
      }
  end

  def toggle_active_status # rubocop:todo GitHub/UseRestfulActions
    hook.toggle_active_status_from_stafftools(disable_reason: params[:disable_reason])
    flash[:notice] = "Okay, the webhook was successfully #{hook_active_status}."
    redirect_to :back
  end

  private

  def hook
    hook_id = params[:webhook_id] || params[:id]
    return unless hook_id.present?
    @hook ||= this_listing.hooks.find(hook_id)
  end

  def hook_active_status
    hook.active? ? "enabled" : "disabled"
  end
end
