# typed: strict
# frozen_string_literal: true

class Sponsors::YourSponsors::ExportsController < ApplicationController
  extend T::Sig
  include Sponsors::AdminableControllerValidations
  include GitHub::RateLimitedRequest

  before_action :require_acceptance_into_sponsors_program
  before_action :non_waitlisted_sponsors_listing_required

  rate_limit_requests key: :rate_limit_key, max: 10, ttl: 1.hour, at_limit: :rate_limit_render

  sig { void }
  def create
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#non_waitlisted_sponsors_listing_required ensures non-nil"
    end
    export = SponsorsListing::SponsorshipsExport.new(
      sponsors_listing: listing,
      timeframe: timeframe,
      format: export_params[:format],
      year: year,
      month: export_params[:month],
    )

    if export.valid?
      export.start_export_job(actor: current_user)

      flash[:notice] = "You've started an export of your sponsors! " \
        "You'll receive an email at #{export.contact_email} shortly with the export attached."
    else
      flash[:error] = "There was an error starting the export: " \
        "#{export.errors.full_messages.to_sentence}"
    end

    redirect_to sponsorable_dashboard_activities_path(sponsorable)
  end

  private

  sig { returns String }
  memoize def timeframe
    params[:timeframe] || "month"
  end

  sig { returns T.nilable(T.any(String, Integer)) }
  memoize def year
    if timeframe == "month"
      export_params[:year]
    else
      export_params[:full_year]
    end
  end

  sig { returns ActionController::Parameters }
  memoize def export_params
    params.require(:export).permit(:year, :month, :format, :full_year)
  end

  sig { returns T.any(Symbol, GitHubSponsors::Types::Sponsorable) }
  def target_for_conditional_access
    sponsorable || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  sig { returns String }
  def rate_limit_key
    sponsorable = T.must_because(self.sponsorable) { "#sponsorable_required ensures non-nil" }
    "#{self.class.to_s.underscore}.#{sponsorable.login}"
  end

  sig { void }
  def rate_limit_render
    flash[:error] = "This Sponsors account has exceeded the export rate limit. " \
      "Please wait one hour before requesting another export."

    redirect_to sponsorable_dashboard_activities_path(sponsorable)
  end
end
