# typed: true
# frozen_string_literal: true

class Sponsors::ProfilesController < ApplicationController
  extend T::Sig
  include Sponsors::AdminableControllerValidations

  before_action :non_waitlisted_sponsors_listing_required
  before_action :require_acceptance_into_sponsors_program

  layout "layouts/sponsors"

  stylesheet_bundle :sponsors

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    render "sponsors/profiles/show", locals: {
      sponsors_listing: sponsorable_sponsors_listing,
    }
  end

  def update
    featured_state = find_featured_state
    should_execute_featured_sponsors_hydro_event = is_featured_sponsors_settings_changed? || is_featured_sponsors_selection_changed?
    sponsors_listing = Sponsors::UpdateSponsorsListing.call(
      slug: T.must(sponsorable_sponsors_listing).slug,
      short_description: update_params[:short_description],
      full_description: update_params[:full_description],
      viewer: current_user,
      featured_state: featured_state,
      hide_past_sponsorships: update_params[:hide_past_sponsorships] == "on",
      enable_featured_sponsorships: update_params[:enable_featured_sponsorships] == "enable",
      automate_featured_sponsorships: update_params[:automate_featured_sponsorships] == "automatic",
    )

    unless sponsors_listing.set_featured_users(featured_users_update_params)
      flash[:error] = sponsors_listing.errors.full_messages.join(", ")
      return show
    end

    unless sponsors_listing.set_featured_repos(featured_repos_update_ids)
      flash[:error] = sponsors_listing.errors.full_messages.join(", ")
      return show
    end

    if sponsors_listing.featured_sponsorships_settings.enabled? &&
       sponsors_listing.featured_sponsorships_settings.automatic?
      AutoUpdateFeaturedSponsorsJob.perform_now(sponsors_listing)
    else
      unless sponsors_listing.set_featured_sponsorships(featured_sponsorships_update_params)
        flash[:error] = sponsors_listing.errors.full_messages.join(", ")
        return show
      end
    end
    execute_featured_sponsors_hydro_event(sponsors_listing) if should_execute_featured_sponsors_hydro_event

    flash[:notice] = "Your profile has been updated"
    redirect_to sponsorable_dashboard_profile_path(sponsorable)
  rescue ActiveRecord::RecordNotFound, Sponsors::UpdateSponsorsListing::ForbiddenError
    render_404
  rescue Sponsors::UpdateSponsorsListing::UnprocessableError => e
    flash[:error] = e.message
    show
  end

  private

  sig { returns(T::Boolean) }
  def is_featured_sponsors_settings_changed?
    enabled_state_transition = sponsorable_sponsors_listing&.featured_sponsorships_settings&.enabled? ^
      (update_params[:enable_featured_sponsorships] == "enable")
    automatic_state_transition = sponsorable_sponsors_listing&.featured_sponsorships_settings&.automatic? ^
      (update_params[:automate_featured_sponsorships] == "automatic")

    enabled_state_transition || automatic_state_transition
  end

  sig { returns(T::Boolean) }
  def is_featured_sponsors_selection_changed?
    # update_params[:featured_sponsorships_selection] is an array of strings which we convert to integers
    # to compare with the current featured sponsorship ids
    if update_params[:featured_sponsorships_selection].present?
      new_featured_sponsorships = update_params[:featured_sponsorships_selection].reject(&:empty?).map(&:to_i).sort
      current_featured_sponsorships = sponsorable_sponsors_listing&.featured_sponsorships&.pluck(:featureable_id).sort

      featured_sponsors_change = new_featured_sponsorships != current_featured_sponsorships
    else
      featured_sponsors_change = false
    end

    featured_sponsors_change
  end

  sig { params(sponsors_listing: SponsorsListing).void }
  def execute_featured_sponsors_hydro_event(sponsors_listing)
    featured_count = sponsors_listing.featured_sponsorships_settings.enabled? ? sponsors_listing.featured_sponsorships.count : 0
    GlobalInstrumenter.instrument("sponsors.featured_sponsors", {
      maintainer: sponsors_listing.sponsorable,
      settings: sponsors_listing.featured_sponsorships_settings,
      featured_count: featured_count
    })
  end

  sig { returns ActionController::Parameters }
  memoize def update_params
    params.require(:sponsors_listing)
      .permit(:full_description, :featured_state, :short_description, :hide_past_sponsorships,
        :enable_featured_sponsorships, :automate_featured_sponsorships,
        featured_users: [:id, :featureable_id, :description], featured_users_selection: [],
        featured_repos: [:id, :featureable_id, :description], featured_repos_selection: [],
        featured_sponsorships: [:id, :featureable_id, :description], featured_sponsorships_selection: [],)
  end

  sig { returns T::Array[T.nilable(ActionController::Parameters)] }
  def featured_users_update_params
    featured_items_params(
      limit: SponsorsListingFeaturedItem::FEATURED_USERS_LIMIT_PER_LISTING,
      params_key: :featured_users,
      selection_key: :featured_users_selection,
    )
  end

  sig { returns T::Array[T.nilable(ActionController::Parameters)] }
  def featured_sponsorships_update_params
    featured_items_params(
      limit: SponsorsListingFeaturedItem::FEATURED_SPONSORSHIPS_LIMIT_PER_LISTING,
      params_key: :featured_sponsorships,
      selection_key: :featured_sponsorships_selection,
    )
  end

  sig { returns T::Array[Integer] }
  def featured_repos_update_ids
    return [] unless update_params[:featured_repos].present?
    update_params[:featured_repos].map { |repo| repo["featureable_id"] }
  end

  sig do
    params(
      params_key: T.any(String, Symbol),
      selection_key: T.any(String, Symbol),
      limit: Integer
    ).returns(T::Array[T.nilable(ActionController::Parameters)])
  end
  def featured_items_params(params_key:, selection_key:, limit: 1)
    items_params = Array(update_params[params_key]).first(limit)
    return items_params unless update_params.key?(selection_key)

    selections = Array(update_params[selection_key]).reject(&:blank?).first(limit)

    items_to_keep = items_params.select { |item| selections.include?(item[:featureable_id]) }
    items_to_remove = (items_params - items_to_keep).map { |item| item.merge(_destroy: true) }
    items_to_add = (selections - items_to_keep.map { |item| item[:featureable_id] })
      .map { |item| { featureable_id: item } }

    items_to_keep + items_to_add + items_to_remove
  end

  def find_featured_state
    if update_params[:featured_state] == "0"
      :disabled
    elsif sponsorable_sponsors_listing&.featured_active?
      :active
    elsif update_params[:featured_state]
      :allowed
    end
  end

  sig { returns T.any(Symbol, GitHubSponsors::Types::Sponsorable) }
  def target_for_conditional_access
    return :no_target_for_conditional_access unless sponsorable # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    T.must(sponsorable)
  end

  sig { returns T::Array[SponsorsListingFeaturedItem] }
  def featured_repos
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#non_waitlisted_sponsors_listing_required ensures non-nil"
    end
    listing.featured_repos.to_a
  end
end
