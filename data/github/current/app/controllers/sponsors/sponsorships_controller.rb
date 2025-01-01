# typed: strict
# frozen_string_literal: true

class Sponsors::SponsorshipsController < ApplicationController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  allow_verified_fetch only: [:update]

  include Sponsors::SharedControllerMethods
  include TradeControlsControllerMethods

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:edit],
    optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  SPONSORSHIPS_TO_DISPLAY = 22

  before_action :sponsorable_required
  before_action :set_return_url, only: [:show]
  before_action :login_required
  before_action :non_banned_sponsors_listing_required, only: [:edit]
  before_action :non_waitlisted_sponsors_listing_required
  before_action :verify_visible_to_viewer
  before_action :non_spammy_user_required
  before_action :ensure_sponsorable_metadata_is_valid
  before_action :valid_sponsor_required, only: [:create, :update, :destroy]
  before_action :valid_tier_required_to_exist_or_amount_given, only: :show
  before_action :valid_tier_required_to_exist_or_to_be_created, only: [:create, :update]
  before_action :ensure_prorated_pay_is_allowed, :ensure_full_amount_pay_is_allowed, only: :create
  before_action :ensure_sponsorship_unlocked_for_different_custom_amount, only: :show
  before_action :add_csp_exceptions, only: [:show, :edit]
  before_action :ensure_editing_allowed, only: [:edit]
  before_action :require_sponsorship, only: [:update, :destroy]
  before_action :ensure_user_has_verified_email, only: [:show]
  before_action :ensure_last_one_time_payment_has_processed, only: [:show]

  before_action only: [:show] do
    T.bind(self, Sponsors::SponsorshipsController)
    check_trade_compliance(target: sponsor, redirect_url: sponsorable_path(sponsorable))
  end

  before_action only: [:create, :update] do
    T.bind(self, Sponsors::SponsorshipsController)
    check_trade_compliance(target: sponsor, redirect_url: sponsorable_path(sponsorable), sdn_redirect: true)
  end

  javascript_bundle :billing
  stylesheet_bundle :sponsors

  # For editing billing information within a modal and sharing sponsorship to Twitter
  CSP_EXCEPTIONS = T.let({
    img_src: [GitHub.paypal_checkout_url].freeze,
    connect_src: [GitHub.braintreegateway_url, GitHub.braintree_analytics_url].freeze,
    frame_src: [GitHub.zuora_payment_page_server].freeze,
  }.freeze, T::Hash[Symbol, T::Array[T.nilable(String)]])

  sig { void }
  def show
    opt_into_email = sponsorship&.is_sponsor_opted_in_to_email ||
      (params[:email_opt_in].present? && params[:email_opt_in] != "off")
    privacy_level = sponsorship&.privacy_level
    privacy_level ||= if Sponsorship.privacy_levels.key?(params[:privacy_level])
      params[:privacy_level]
    else
      "public"
    end

    tier = selected_tier_or_unsaved_custom_tier
    parent_tier = tier.closest_lesser_value_tier if tier.custom?
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#non_waitlisted_sponsors_listing_required ensures non-nil"
    end

    # We only render goal-related UI for brand new recurring sponsorships
    goal = listing.active_goal if sponsorship.blank? && tier.recurring?
    sponsorships_for_goal = if goal
      T.unsafe(sponsorships_as_sponsorable).active.recurring.paginate(page: 1, per_page: SPONSORSHIPS_TO_DISPLAY)
    else
      Sponsorship.none
    end

    instrument_billing_form_loaded(flow: "SPONSORSHIPS")
    listing.instrument_sponsorship_checkout_viewed(
      actor: current_user,
      sponsor: T.must_because(sponsor) { "#login_required ensures #sponsor is non-nil" },
      tier: tier,
    ) unless current_user == sponsorable

    render "sponsors/sponsorships/show", locals: {
      sponsor: sponsor,
      listing: listing,
      selected_tier: tier,
      parent_tier: parent_tier,
      sponsorable: sponsorable,
      sponsorship: sponsorship,
      goal: goal,
      sponsorships_for_goal: sponsorships_for_goal,
      opted_in_to_email: opt_into_email,
      privacy_level: privacy_level,
      pay_prorated: pay_prorated?,
      sponsorable_metadata: sponsorable_metadata_from_params,
      active_on: active_on,
    }
  end

  sig { void }
  def edit
    instrument_profile_view
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#non_waitlisted_sponsors_listing_required ensures non-nil"
    end
    sponsorship = T.must_because(self.sponsorship) { "#ensure_editing_allowed ensures non-nil" }

    render "sponsors/sponsorables/show", locals: {
      sponsorable: sponsorable,
      listing: listing,
      current_tier: sponsorship.tier,
      custom_amount: prefilled_custom_amount,
      sponsorships: sponsorships_for_sponsors_listing,
      featured_sponsorships: featured_sponsorships_for_sponsors_listing,
      active_sponsorships: active_sponsorships_for_sponsors_listing,
      inactive_sponsorships: inactive_sponsorships_for_sponsors_listing,
      featured_users: featured_users,
      sponsorship: sponsorship,
      sponsor: sponsor,
      is_new_sponsorship: false,
      tier_frequency: :recurring,
      editing: true,
      previewing: false,
      goal: listing.active_goal,
      sponsorable_metadata: sponsorable_metadata_from_params,
      show_sponsorship_tabs_on_sponsors_listing: show_sponsorship_tabs_on_sponsors_listing?,
    }
  end

  sig { void }
  def create
    maybe_save_sponsors_business_tax_identifier
    create_sponsorship
    set_sponsorship_created_success_message

    redirect_to_sponsors_listing(redirect_params: { success: "true" })
  rescue Sponsors::SaveSponsorsBusinessTaxIdentifier::UnprocessableError,
         Sponsors::CreateSponsorship::ForbiddenError,
         Sponsors::CreateSponsorship::UnprocessableError => err
    flash[:error] = err.message
    redirect_to_sponsorships
  end

  sig { void }
  def update
    maybe_save_sponsors_business_tax_identifier
    maybe_update_sponsorship_preferences
    maybe_update_sponsorship_tier
    sponsor = T.must_because(self.sponsor) { "#valid_sponsor_required ensures non-nil" }
    sponsorable = T.must_because(self.sponsorable) { "#sponsorable_required ensures non-nil" }

    handle_update_successful(sponsor, sponsorable)

  rescue Sponsors::SaveSponsorsBusinessTaxIdentifier::UnprocessableError,
         Sponsors::UpdateSponsorship::UnprocessableError => error
    handle_update_unprocessable(error)

  rescue Sponsors::UpdateSponsorship::ForbiddenError
    render_404
  end

  sig { void }
  def destroy
    sponsorship = T.must_because(self.sponsorship) { "#require_sponsorship ensures non-nil" }
    unless sponsorship.adminable_by?(current_user)
      flash[:error] = "You cannot cancel #{sponsor}'s sponsorship of #{sponsorable}."
      return after_destroy_redirect
    end

    tier = sponsorship.tier
    subscription_item = sponsorship.subscription_item

    result = sponsorship.cancel(actor: current_user, reason: :SPONSOR_INITIATED)

    if !result.success
      error_message = result.errors.to_sentence
      flash[:error] = "Could not cancel sponsorship: #{error_message}"
    else
      whose_sponsorship = sponsor == current_user ? "your" : "#{sponsor}'s"
      notice = "You've cancelled #{whose_sponsorship} sponsorship of #{sponsorable}"
      notice += if tier
        " for #{tier.name}."
      else
        "."
      end

      if sponsorship.active? # sponsorship still being active means the cancellation was scheduled for a later date
        whose_payment = sponsor == current_user ? "your" : "#{sponsorship.billable_entity}'s"
        notice += " The sponsorship will be active until #{whose_payment} next billing cycle"
        next_billing_date = sponsorship.next_billing_date&.to_formatted_s(:date)
        notice += if next_billing_date
          " on #{next_billing_date}."
        else
          "."
        end
      end

      flash[:notice] = notice
    end

    after_destroy_redirect
  end

  private

  sig { params(sponsor: User, sponsorable: User).void }
  def handle_update_successful(sponsor, sponsorable)
    respond_to do |format|
      format.html do
        flash[:notice] = Sponsors::UpdateSponsorship.success_message(viewer: current_user, sponsor: sponsor,
          sponsorable: sponsorable)
        redirect_to_sponsors_listing
      end
      format.json { head :ok }
    end
  end

  sig { params(error: StandardError).void }
  def handle_update_unprocessable(error)
    respond_to do |format|
      format.html do
        flash[:error] = error.message
        redirect_to :back
      end
      format.json { render json: { error: error.message }, status: :bad_request }
    end
  end

  sig { params(default: T.nilable(T::Boolean)).returns(T::Boolean) }
  def is_public(default: false)
    return !!default unless params[:privacy_level]
    params[:privacy_level] == "public"
  end

  sig { params(default: T.nilable(T::Boolean)).returns(T::Boolean) }
  def email_opt_in(default: false)
    return !!default unless params[:email_opt_in]
    params[:email_opt_in] == "on"
  end

  sig { returns T.nilable(Date) }
  def end_date
    return unless params[:set_expires_at] == "1"
    year = end_date_params[:year].to_i
    month = end_date_params[:month].to_i
    Date.new(year, month, 1).end_of_month
  end

  sig { returns ActionController::Parameters }
  memoize def end_date_params
    params.require(:end_date).permit(:month, :year)
  end

  sig { void }
  def after_destroy_redirect
    if params[:redirect_to_sponsors_listing] == "1"
      redirect_to_sponsors_listing
    else
      fallback_location = sponsorable_sponsorships_path(sponsorable, sponsor: params[:sponsor])
      redirect_back(fallback_location: fallback_location)
    end
  end

  sig { void }
  def maybe_save_sponsors_business_tax_identifier
    return unless should_save_sponsors_business_tax_identifier?

    Sponsors::SaveSponsorsBusinessTaxIdentifier.call(
      user: sponsor,
      country: sponsors_business_tax_identifier_params[:country],
      region: sponsors_business_tax_identifier_params[:region],
      vat_code: sponsors_business_tax_identifier_params[:vat_code],
    )
  end

  sig { void }
  def maybe_update_sponsorship_preferences
    updated_privacy = is_public(default: nil)
    updated_email_opt_in = email_opt_in(default: nil)
    return unless [updated_privacy, updated_email_opt_in, end_date].compact.present?

    Sponsors::UpdateSponsorshipPreferences.call(
      sponsorship,
      viewer: current_user,
      is_public: updated_privacy,
      email_opt_in: updated_email_opt_in,
      end_date: end_date,
    )
  end

  sig { void }
  def maybe_update_sponsorship_tier
    new_tier = selected_tier_with_created_custom_tier_fallback
    return unless new_tier

    sponsorship = T.must_because(self.sponsorship) { "#require_sponsorship ensures non-nil" }
    return if sponsorship.tier == new_tier

    Sponsors::UpdateSponsorshipTier.call(sponsorship,
      new_tier: new_tier,
      viewer: current_user,
      sponsorable_metadata: sponsorable_metadata_from_params)
  end

  sig { returns T::Boolean }
  def should_save_sponsors_business_tax_identifier?
    params[:sponsors_business_tax_identifier].present?
  end

  sig { returns ActionController::Parameters }
  def sponsors_business_tax_identifier_params
    params.require(:sponsors_business_tax_identifier).permit(:country, :region, :vat_code)
  end

  sig { returns T.any(Sponsorship, Billing::SubscriptionItem) }
  def create_sponsorship
    tier = T.must_because(selected_tier_with_created_custom_tier_fallback) do
      "#valid_tier_required_to_exist_or_to_be_created ensures non-nil"
    end
    sponsor = T.must_because(self.sponsor) { "#valid_sponsor_required ensures non-nil" }
    if tier.recurring?
      Sponsors::CreateRecurringSponsorship.call(
        tier: tier,
        sponsor: sponsor,
        sponsorable: sponsorable,
        viewer: current_user,
        is_public: is_public,
        email_opt_in: email_opt_in,
        pay_prorated: pay_prorated?,
        sponsorable_metadata: sponsorable_metadata_from_params,
        end_date: end_date,
        active_on: active_on,
      )
    else
      Sponsors::AddOneTimePayment.call(
        tier: tier,
        sponsor: sponsor,
        sponsorable: sponsorable,
        viewer: current_user,
        is_public: is_public,
        email_opt_in: email_opt_in,
        sponsorable_metadata: sponsorable_metadata_from_params,
      )
    end
  end

  sig { void }
  def set_sponsorship_created_success_message
    who_is_sponsoring = if sponsor&.organization?
      "@#{sponsor}"
    else
      "You"
    end
    tier = T.must_because(selected_tier_with_created_custom_tier_fallback) do
      "#valid_tier_required_to_exist_or_to_be_created ensures non-nil"
    end
    verb = if tier.recurring?
      sponsor&.organization? ? " is now sponsoring" : "'re now sponsoring"
    else
      " sponsored"
    end
    who_is_being_sponsored = "@#{sponsorable}"
    amount = tier.formatted_price_per_cycle(sponsor: sponsor)

    flash[:notice] = "🎉 #{who_is_sponsoring}#{verb} #{who_is_being_sponsored} for #{amount}"
  end

  sig { void }
  def set_return_url
    params[:return_to] = request.url
  end

  sig { void }
  def ensure_sponsorship_unlocked_for_different_custom_amount
    return if selected_tier # Fine to look at your currently chosen tier

    return unless sponsorship&.locked? # If locked, must be a one-time sponsorship

    current_amount = sponsorship&.monthly_price_in_dollars.to_i
    return if current_amount == custom_amount

    sponsor_description = if sponsor == current_user
      "your"
    else
      "@#{sponsor}'s"
    end
    include_frequency = !one_time_payment?

    flash[:error] = "Cannot change #{sponsor_description} sponsorship from " \
      "$#{current_amount}#{include_frequency ? " one time" : nil} to " \
      "$#{custom_amount}#{include_frequency ? " a month" : nil} while your last payment " \
      "is processing."
    redirect_to_sponsors_listing
  end

  sig { params(redirect_params: T.any(T::Hash[T.untyped, T.untyped], ActionController::Parameters)).void }
  def redirect_to_sponsors_listing(redirect_params: {})
    if sponsor != current_user
      redirect_params[:sponsor] = sponsor&.login
    end

    redirect_to sponsorable_with_metadata_path(redirect_params)
  end

  sig { params(tier: SponsorsTier).void }
  def redirect_to_published_tier(tier)
    options = {
      tier_id: tier.id,
      sponsor: sponsor&.login,
    }
    options.merge!(**sponsorable_metadata_from_params) if sponsorable_metadata_from_params.present?
    redirect_to sponsorable_sponsorships_path(sponsorable, **options)
  end

  sig { returns T.any(Symbol, GitHubSponsors::Types::Sponsor) }
  def target_for_conditional_access
    # This method is called via application controller :perform_conditional_access_checks
    # before any of the before actions defined in this controller
    parse_json_params
    sponsor || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  sig { override.returns(GitHubSponsors::Types::Sponsor) }
  def target
    T.must_because(sponsor) { "#valid_sponsor_required ensures non-nil" }
  end

  sig { void }
  def instrument_profile_view
    tracking_params = Sponsors::TrackingParameters.from_params(params)

    GlobalInstrumenter.instrument("sponsors.profile_viewed", {
      actor: current_user,
      sponsorable: sponsorable,
      source: tracking_params.source,
      referring_account: tracking_params.referring_account,
      sponsor: sponsor,
      origin: tracking_params.origin,
    })
  end

  sig { returns T.nilable(SponsorsTier) }
  memoize def selected_tier
    return if params[:tier_id].blank?

    listing = sponsorable_sponsors_listing
    return unless listing

    tier = listing.sponsors_tiers.find_by(id: params[:tier_id])
    tier if tier&.readable_by?(current_user)
  end

  sig { returns SponsorsTier }
  def selected_tier_or_unsaved_custom_tier
    return T.must(selected_tier) if selected_tier

    yearly_price_in_cents = if one_time_payment?
      custom_amount * 100
    else
      custom_amount * 100 * 12
    end

    custom_tier = SponsorsTier.new(
      monthly_price_in_cents: custom_amount * 100,
      yearly_price_in_cents: yearly_price_in_cents,
      creator: current_user,
      state: :custom,
      sponsors_listing: sponsorable_sponsors_listing,
      frequency: new_tier_frequency,
    )
    custom_tier.name = custom_tier.generate_name
    custom_tier
  end

  sig { returns T.nilable(SponsorsTier) }
  memoize def selected_tier_with_created_custom_tier_fallback
    return selected_tier if selected_tier

    listing = sponsorable_sponsors_listing
    return unless listing

    if custom_amount.nonzero?
      Sponsors::CreateSponsorsTier.find_published_or_create_custom_tier(
        sponsors_listing: listing,
        amount: custom_amount,
        viewer: current_user,
        sponsor: sponsor,
        is_recurring: !one_time_payment?,
        parent_tier_id: params[:parent_tier_id],
      )
    end
  end

  sig { returns T.nilable(SponsorsTier) }
  memoize def colliding_published_tier
    listing = sponsorable_sponsors_listing
    return unless listing

    listing.published_sponsors_tiers.find_by(
      monthly_price_in_cents: custom_amount * 100,
      frequency: new_tier_frequency,
    )
  end

  sig { returns Integer }
  memoize def custom_amount
    params[:amount].to_i
  end

  sig { returns T::Boolean }
  memoize def one_time_payment?
    !!(selected_tier&.one_time? || frequency_param == "one-time")
  end

  sig { returns Symbol }
  def new_tier_frequency
    one_time_payment? ? :one_time : :recurring
  end

  sig { void }
  def valid_tier_required_to_exist_or_amount_given
    if selected_tier.nil?
      return render_404 if custom_amount.zero?

      if custom_amount.negative?
        flash[:error] = "Invalid custom sponsorship amount given."
        return redirect_to_sponsors_listing
      end

      if custom_amount > SponsorsTier::MAX_SPONSORSHIP_AMOUNT_IN_DOLLARS
        flash[:error] = "Custom sponsorship amount cannot be greater than #{SponsorsTier::MAX_SPONSORSHIP_AMOUNT_HUMAN}."
        return redirect_to_sponsors_listing
      end

      redirect_to_published_tier(T.must(colliding_published_tier)) if colliding_published_tier
    end
  end

  sig { void }
  def valid_tier_required_to_exist_or_to_be_created
    tier = selected_tier_with_created_custom_tier_fallback
    if tier.nil?
      return render_404 if params[:tier_id] # tier was passed, but it wasn't valid
      render_404 unless sponsorship # tier is required if a sponsorship doesn't exist
    end
  rescue Sponsors::CreateSponsorsTier::ForbiddenError
    render_404
  rescue Sponsors::CreateSponsorsTier::UnprocessableError => error
    flash[:error] = error.message
    redirect_to_sponsorships
  end

  sig { void }
  def redirect_to_sponsorships
    redirect_to sponsorable_sponsorships_path(sponsorable,
      email_opt_in: params[:email_opt_in],
      tier_id: params[:tier_id],
      sponsor: params[:sponsor],
      privacy_level: params[:privacy_level],
      amount: params[:amount],
      frequency: frequency_param,
    )
  end

  sig { returns T.nilable(Sponsorship) }
  memoize def sponsorship
    sponsorship = sponsor&.sponsorship_as_sponsor_for(sponsorable)
    # we support updating the privacy level of inactive sponsorships, as past sponsorships can be displayed
    if action_name == "update"
      sponsorship
    else
      sponsorship if sponsorship&.active?
    end
  end

  sig { void }
  def require_sponsorship
    render_404 unless sponsorship
  end

  sig { void }
  def ensure_user_has_verified_email
    if current_user.no_verified_emails?
      flash[:error] = "You need a verified email address in order to sponsor anyone."
      redirect_to_sponsors_listing
    end
  end

  sig { void }
  def ensure_last_one_time_payment_has_processed
    if one_time_payment? && sponsor&.processing_one_time_payment_to?(sponsorable)
      whose_payment = T.must(sponsor).user? ? "your" : "@#{sponsor}'s"
      error = "Cannot make another one-time payment to @#{sponsorable} while #{whose_payment} previous one-time payment is still processing."
      flash[:error] = error
      redirect_to_sponsors_listing
    end
  end

  sig { void }
  def ensure_editing_allowed
    unless sponsorship
      return redirect_to sponsorable_with_metadata_path
    end

    if sponsorship&.locked?
      flash[:error] = "You cannot change tiers while your previous payment is processing."
      redirect_to sponsorable_with_metadata_path
    end
  end

  sig { void }
  def ensure_prorated_pay_is_allowed
    return unless params[:pay_prorated] == "true"

    if one_time_payment?
      flash[:error] = "You cannot pay a prorated amount for a one-time sponsorship."
      redirect_to_sponsorships
    end
  end

  sig { void }
  def ensure_full_amount_pay_is_allowed
    return if one_time_payment?
    return unless params[:pay_prorated] == "false"

    if sponsor.nil? || !T.must(sponsor).can_skip_sponsorship_proration?
      flash[:error] = "You cannot pay the full amount for a sponsorship."
      redirect_to_sponsorships
    end
  end

  sig { returns T::Boolean }
  memoize def pay_prorated?
    return false if one_time_payment?
    return true unless T.must(sponsor).can_skip_sponsorship_proration?

    if params[:pay_prorated]
      params[:pay_prorated] == "true"
    else
      T.must(sponsor).sponsors_prorated_by_default?
    end
  end

  sig { returns T.nilable(Date) }
  memoize def active_on
    return unless sponsor&.can_schedule_sponsorships?

    begin
      Date.iso8601(params[:active_on])
    rescue Date::Error
      nil
    end
  end

  sig { params(params: T.any(T::Hash[T.untyped, T.untyped], ActionController::Parameters)).returns(String) }
  def sponsorable_with_metadata_path(params = {})
    sponsorable_path(sponsorable, sponsorable_metadata_from_params.merge(params.to_h))
  end
end
