# typed: strict
# frozen_string_literal: true

class Sponsors::FiscalHost::OrgsExportsController < ApplicationController
  extend T::Sig
  include Sponsors::AdminableControllerValidations

  before_action :non_waitlisted_sponsors_listing_required
  before_action :require_acceptance_into_sponsors_program
  before_action :fiscal_host_sponsors_listing_required

  sig { void }
  def create
    export = SponsorsListing::FiscalHostOrgsExport.new(sponsors_listing: sponsorable_sponsors_listing,
      viewer: current_user)
    return render_404 unless export.valid?

    send_data export.as_csv, type: "text/csv", disposition: "attachment; filename=\"#{export.filename}\""
  end

  private

  sig { returns T.any(Symbol, GitHubSponsors::Types::Sponsorable) }
  def target_for_conditional_access
    sponsorable || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
