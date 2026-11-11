# typed: strict
# frozen_string_literal: true

class Sponsors::SignupsController < ApplicationController
  include ApplicationController::VerifiedFetchDependency
  include Sponsors::SharedControllerMethods

  CSP_EXCEPTIONS = T.let({
    form_action: [
      Billing::StripeConnect::Account::STRIPE_CONNECT_URL,
    ],
  }.freeze, T::Hash[Symbol, T.untyped])

  layout "layouts/sponsors"

  stylesheet_bundle :sponsors

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  allow_verified_fetch only: [:create, :update]

  before_action :sponsorable_required
  before_action :login_required
  before_action :sudo_filter
  before_action :sponsorable_adminable_by_current_user_required
  before_action :redirect_if_approved
  before_action :sponsorable_verified_email_required
  before_action :non_banned_sponsors_listing_required_even_for_staff
  before_action :add_csp_exceptions

  # The React partial this loads fetches signup status via XHR which exposes a modal for identity confirmation. That
  # modal relies on billing javascript.
  javascript_bundle :billing

  sig { void }
  def show
    render "sponsors/signups/show", locals: {
      sponsorable: sponsorable,
      sponsors_listing: sponsors_listing,
    }
  end

  sig { void }
  def create
    listing = begin
      create_sponsors_listing
    rescue Sponsors::CreateSponsorsListing::UnprocessableError => error
      return render json: { error: error }, status: :unprocessable_entity
    end

    render(
      json: success_payload(listing),
      status: :created
    )
  end

  sig { void }
  def update
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#non_banned_sponsors_listing_required_even_for_staff ensures non-nil"
    end
    # ignore if listing belongs to an organization that chose a fiscal host
    body, status = if listing.uses_fiscal_host?
      [success_payload(listing), :ok]
    else
      if Sponsors::UpdateWaitlistedListing.call(listing, listing_update_params)
        [success_payload(listing), :ok]
      else
        [{ error: listing.errors.full_messages.join(", ") }, :unprocessable_entity]
      end
    end

    render json: body, status: status
  end

  private

  sig { void }
  def redirect_if_approved
    redirect_to sponsorable_dashboard_path(sponsorable) if sponsorable_sponsors_listing&.approved?
  end

  sig { void }
  def sponsorable_verified_email_required
    return if sponsorable&.organization?
    return if sponsorable&.verified_emails?

    flash[:notice] = "You must verify an email address for GitHub Sponsors!"
    redirect_to settings_email_preferences_path
  end

  sig { void }
  def non_banned_sponsors_listing_required_even_for_staff
    render_404 if sponsorable_sponsors_listing&.banned?
  end

  sig { returns(SponsorsListing) }
  memoize def sponsors_listing
    sponsorable_sponsors_listing || SponsorsListing.new(
      state: :waitlisted,
      sponsorable: sponsorable,
      actor: current_user,
    )
  end

  sig { params(listing: SponsorsListing).returns(T::Hash[Symbol, T.untyped]) }
  def success_payload(listing)
    {
      sponsorsListingData: listing.serialize_for_signup,
    }
  end

  sig { returns(SponsorsListing) }
  def create_sponsors_listing
    attrs = listing_params.merge(sponsorable: sponsorable, actor: current_user, survey: survey)
    if params[:fiscal_option] == Sponsors::CreateSponsorsListing::FISCAL_OPTION_HOST
      Sponsors::CreateSponsorsListing.with_fiscal_host(attrs)
    else
      Sponsors::CreateSponsorsListing.with_bank(attrs)
    end
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  memoize def listing_params
    params.require(:sponsors_listing).permit(
      :parent_listing_id, :fiscal_option, :billing_country, :country_of_residence, :contact_email_id,
      :fiscally_hosted_project_profile_url,
    ).to_h.map { |k, v| [k.to_sym, v] }.to_h
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def listing_update_params
    listing_params.slice(:country_of_residence, :contact_email_id, :billing_country)
  end

  sig { returns(Survey) }
  memoize def survey
    # TODO: see if we can remove this from one-click signup...?
    ActiveRecord::Base.connected_to(role: :writing) do
      if sponsorable&.organization?
        ::Sponsors::OrganizationWaitlistSurvey.find_or_create_survey
      else
        ::Sponsors::UserWaitlistSurvey.find_or_create_survey
      end
    end
  end

  sig { returns(T.any(Symbol, GitHubSponsors::Types::Sponsorable)) }
  def target_for_conditional_access
    sponsorable || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
