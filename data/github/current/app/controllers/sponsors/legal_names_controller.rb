# typed: strict
# frozen_string_literal: true

class Sponsors::LegalNamesController < ApplicationController
  include Sponsors::AdminableControllerValidations

  before_action :require_acceptance_into_sponsors_program

  sig { void }
  def update
    legal_name = params[:legal_name]
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#require_acceptance_into_sponsors_program ensures non-nil"
    end

    if listing.update(legal_name: legal_name)
      adjective = listing.for_user? ? "legal" : "organization"
      flash[:notice] = "Updated #{adjective} name to #{legal_name}"
    else
      errors = listing.errors.full_messages
      flash[:error] = errors.to_sentence
    end

    redirect_to sponsorable_dashboard_settings_path(sponsorable)
  end

  private

  sig { returns T.any(Symbol, GitHubSponsors::Types::Sponsorable) }
  def target_for_conditional_access
    sponsorable || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
