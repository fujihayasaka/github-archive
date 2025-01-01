# typed: strict
# frozen_string_literal: true

class Sponsors::TierSuggestionsController < ApplicationController
  include Sponsors::AdminableControllerValidations

  before_action :non_waitlisted_sponsors_listing_required
  before_action :non_banned_sponsors_listing_required

  rescue_from Sponsors::CreateSponsorsTier::UnprocessableError do |error|
    T.bind(self, Sponsors::TierSuggestionsController)
    flash[:error] = error.message
    redirect_to :back
  end

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  stylesheet_bundle :sponsors

  sig { void }
  def show
    SponsorsListing.instrument_view_tier_builder(actor: current_user)
    render "sponsors/tier_suggestions/index",
      locals: {
        sponsorable: sponsorable,
        sponsors_listing: sponsorable_sponsors_listing,
        tiers: Sponsors::TierSuggestion.all,
      }
  end

  sig { void }
  def create
    SponsorsListing.instrument_submit_tier_builder_suggestions(
      actor: current_user,
      submitted_actions: tier_builder_interactions
    )
    Sponsors::CreateTiersFromSuggestions.call(input_ids: tier_ids, listing: sponsorable_sponsors_listing,
      creator: current_user)
    redirect_to sponsorable_dashboard_tiers_path
  end

  private

  sig { returns T::Array[T::Hash[T.any(Symbol, String), T.untyped]] }
  def tier_builder_interactions
    actions = params.dig(:tier_builder, :actions)
    return [] if actions.nil? || actions.empty?
    JSON.parse(actions)
  end

  sig { returns T::Array[T.any(String, Integer)] }
  def tier_ids
    params.select { |_, value| value == "on" }.keys
  end

  sig { returns T.any(Symbol, GitHubSponsors::Types::Sponsorable) }
  def target_for_conditional_access
    sponsorable || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
