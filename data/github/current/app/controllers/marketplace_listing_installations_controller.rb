# typed: true
# frozen_string_literal: true

class MarketplaceListingInstallationsController < ApplicationController

  before_action :marketplace_required
  before_action :login_required

  stylesheet_bundle :marketplace

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:new], optional: true

  def new
    return render_404 unless subscription_item.present?

    listing_plan = subscription_item.subscribable
    listing = listing_plan.listing
    account = subscription_item.managing_entity

    if params[:grant_oap].present? && listing.listable_is_oauth_application? && account&.organization? && account.adminable_by?(current_user)
      ActiveRecord::Base.connected_to(role: :writing) do
        account.approve_oauth_application(listing.listable, approver: current_user)
      end
    end

    if listing.listable_is_integration?
      query_params = { target_id: account.id }
      read_suggested_target_id_cookie(query_params)
      read_repository_ids_cookie(query_params)

      # Because of https://git.io/v1syX
      # we have to pass in the attributes rather than the object
      # to a special routing method.
      options = {
        app: listing.listable.slug,
        user: current_user,
        query_params: query_params,
      }
      if listing.listable.owner.is_a?(Business)
        options[:owner] = listing.listable.owner.slug
      else
        options[:owner] = listing.listable.owner.display_login
      end

      if listing.listable.is_integratable? && ProximaAppSynchronization.synchronized?(listing.listable)
        options[:external_app] = true
      end

      redirect_to gh_graphql_app_installation_permissions_path(**options)
    else
      redirect_to listing_installation_url_with_plan(listing_plan)
    end
  end

  private

  def listing_installation_url_with_plan(listing_plan)
    listing = listing_plan.listing
    uri = URI(listing.installation_url)
    existing_params = URI.decode_www_form(uri.query || "")
    existing_params.push(["marketplace_listing_plan_id", listing_plan.id])
    uri.query = URI.encode_www_form(existing_params)
    uri.to_s
  end

  def read_suggested_target_id_cookie(query_params)
    return unless cookies[:marketplace_suggested_target_id].present?

    parsed_val = JSON.parse(cookies.delete :marketplace_suggested_target_id)
    query_params[:suggested_target_id] = parsed_val
  end

  def read_repository_ids_cookie(query_params)
    return unless cookies[:marketplace_repository_ids].present?

    parsed_val = JSON.parse(cookies.delete :marketplace_repository_ids)
    query_params[:repository_ids] = parsed_val
  end

  def subscription_item
    @subscription_item = begin
      typed_object_from_id([Platform::Objects::SubscriptionItem], params[:subscription_item_id])
    rescue Platform::Errors::NotFound
      nil
    end
  end

  def target_for_conditional_access
    subscription_item&.managing_entity || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
