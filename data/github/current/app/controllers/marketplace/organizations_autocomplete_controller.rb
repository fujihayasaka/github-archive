# typed: true
#frozen_string_literal: true

class Marketplace::OrganizationsAutocompleteController < ApplicationController
  before_action :login_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    only: [:index]

  def index
    query = params[:q] || ""

    organizations = current_user.owned_organizations.preload(:plan_subscription)
    listing = Marketplace::Listing.find(params[:listing_id])

    subscription_items_by_org = organizations.each_with_object({}) do |org, hash|
      hash[org] = if org.business.present? && org.business.self_serve_payment?
        org.business.subscription_item_for_marketplace_listing(listing, organization: org)
      else
        org.subscription_item_for_marketplace_listing(listing)
      end
    end

    un_billed_orgs = if logged_in?
      organizations.map do |org|
        item = subscription_items_by_org[org]
        plan = item ? item.subscribable : nil
        org unless plan
      end.compact
    else
      []
    end

    org_ids = un_billed_orgs.pluck(:id)

    results = if query.present?
      User.where("login LIKE ?", "%#{query}%").where(id: org_ids)
    else
      []
    end

    render "organizations_autocomplete/index", formats: :html, layout: false, locals: {
      results: results,
      user: current_user,
      error_message: nil,
    }
  end

  private

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
