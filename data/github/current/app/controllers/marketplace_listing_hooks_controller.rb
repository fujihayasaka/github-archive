# typed: true
# frozen_string_literal: true

class MarketplaceListingHooksController < ApplicationController
  before_action :ensure_listing_admin
  before_action :marketplace_required
  before_action :sudo_filter
  before_action :this_marketplace_listing_required

  layout "layouts/marketplace"
  stylesheet_bundle :marketplace

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    return render_404 unless this_marketplace_listing.allowed_to_edit?(current_user)
    hook = marketplace_listing.webhook || marketplace_listing.build_webhook(active: true)

    render "marketplace_listing_hooks/show", locals: {
      hook: hook,
      listing_slug: this_marketplace_listing.slug,
      marketplace_listing: this_marketplace_listing
    }
  end

  def create
    hook = marketplace_listing.build_webhook(active: true)
    hook.track_creator(current_user)

    if hook.update(hook_params)
      flash[:notice] = "Okay, that hook was successfully created. We sent a ping payload to test it out! Read more about it at #{GitHub.developer_help_url}/webhooks/#ping-event."
    else
      unless hook.errors[:url].present?
        flash[:error] = "There was an error setting up your hook: #{hook.errors.full_messages.to_sentence}"
      end
    end

    render "marketplace_listing_hooks/show", locals: {
      hook: hook,
      listing_slug: this_marketplace_listing.slug,
      marketplace_listing: this_marketplace_listing
    }
  end

  def update
    hook = marketplace_listing.webhook
    hook.assign_attributes(hook_params)

    if hook.save
      flash[:notice] = "Okay, the hook was successfully updated."
    else
      unless hook.errors[:url].present?
        flash[:error] = "There was an error updating your hook: #{hook.errors.full_messages.to_sentence}"
      end
    end

    render "marketplace_listing_hooks/show", locals: {
      hook: hook,
      listing_slug: this_marketplace_listing.slug,
      marketplace_listing: this_marketplace_listing
    }
  end

  private

  def hook_params
    params.require(:hook).permit :active,
                                 :content_type,
                                 { events: [] },
                                 :insecure_ssl,
                                 :secret,
                                 :url
  end

  memoize def marketplace_listing
    Marketplace::Listing.find_by(slug: params[:listing_slug])
  end

  def ensure_listing_admin
    return if current_user&.biztools_user? || current_user&.site_admin?
    return if marketplace_listing && marketplace_listing.adminable_by?(current_user)
    render_404
  end

  def target_for_conditional_access
    # target for market place listing hooks is the owner of the listing
    # if no listing is found, return :no_target_for_conditional_access and render 404
    return :no_target_for_conditional_access unless this_marketplace_listing # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    this_marketplace_listing.owner
  end

  memoize def this_marketplace_listing
    Marketplace::Listing.find_by(slug: params[:listing_slug])
  end

  def this_marketplace_listing_required
    render_404 unless this_marketplace_listing
  end
end
