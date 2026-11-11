# typed: strict
# frozen_string_literal: true

class Sponsors::TiersController < ApplicationController
  include Sponsors::AdminableControllerValidations

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :new, :edit],
    optional: true

  SEND_TEST_EMAIL_INPUT_NAME = "send_test_email"

  before_action :non_waitlisted_sponsors_listing_required
  before_action :non_banned_sponsors_listing_required
  before_action :require_non_custom_tier, only: [:edit, :update, :destroy]
  before_action :validate_amount, only: [:create, :update]
  before_action :validate_published_tier_count, only: [:create]
  before_action :show_tier_suggestions_if_appropriate, only: [:index]

  stylesheet_bundle :sponsors

  rescue_from Sponsors::CreateSponsorsTier::ForbiddenError,
              Sponsors::UpdateSponsorsTier::ForbiddenError,
              Sponsors::PublishSponsorsTier::ForbiddenError,
              Sponsors::DeleteSponsorsTier::ForbiddenError,
              with: :render_404

  sig { void }
  def index
    SponsorsListing.instrument_skip_tier_builder(actor: current_user) if params["skip-suggestions"]
    tiers_in_frequency = tiers.where(frequency: frequency)
    tier_ids_for_hydro = T.unsafe(tiers).sponsorable_defined.pluck(:id)
    any_published_tiers = recurring_published_count > 0 || one_time_published_count > 0
    active_tiers = tiers_in_frequency.with_states(:draft, :published).includes(:repository)
    retired_tiers = tiers_in_frequency.with_retired_state.with_active_sponsorships.includes(:repository)
    sponsorable = T.must_because(self.sponsorable) { "#non_waitlisted_sponsors_listing_required ensures non-nil" }

    render "sponsors/tiers/index", locals: {
      active_tiers: active_tiers,
      retired_tiers: retired_tiers,
      any_published_tiers: any_published_tiers,
      published_tier_count_in_frequency: published_tier_count_in_frequency,
      recurring_published_count: recurring_published_count,
      one_time_published_count: one_time_published_count,
      draft_tier_count_in_frequency: tiers_in_frequency.with_draft_state.count,
      remaining_tier_count: remaining_tier_count,
      sponsorable: sponsorable,
      sponsors_listing: sponsorable_sponsors_listing,
      tier_ids_for_hydro: tier_ids_for_hydro,
      tier_subscription_counts: sponsorable.tier_subscription_counts,
    }
  end

  sig { void }
  def new
    render_new_form
  end

  sig { void }
  def edit
    render_edit_form
  end

  sig { void }
  def create
    if current_user_wants_test_email?
      send_test_email
      return render_new_form
    end

    tier = Sponsors::CreateSponsorsTier.call(
      custom: false,
      sponsors_listing: sponsorable_sponsors_listing,
      description: params[:description],
      amount: amount,
      viewer: current_user,
      is_recurring: frequency_param != "one-time",
      welcome_message: welcome_message_param,
      repository_id: repository_id_param,
      require_repository: include_repository_access?,
    )

    if publish_tier?
      params[:id] = tier.id
      return publish_tier_and_redirect(tier)
    end

    flash[:notice] = if reached_maximum_tier_count?
      "You've created a draft tier!"
    else
      "You've created a draft tier! When you're ready, you can edit " \
        'the tier and click the "Publish" button.'
    end

    redirect_to sponsorable_dashboard_tiers_path(frequency: frequency_param)
  rescue Sponsors::CreateSponsorsTier::UnprocessableError, Sponsors::PublishSponsorsTier::UnprocessableError => error
    flash[:error] = error.message
    render_new_form
  end

  sig { void }
  def update
    if current_user_wants_test_email?
      send_test_email
      return render_edit_form
    end

    tier = T.must_because(self.tier) { "#require_non_custom_tier ensures non-nil" }
    Sponsors::UpdateSponsorsTier.call(
      tier: tier,
      description: params[:description],
      amount: amount,
      viewer: current_user,
      welcome_message: welcome_message_param,
      require_repository: include_repository_access?,
      repository_id: repository_id_param,
    )

    return publish_tier_and_redirect(tier) if publish_tier?

    flash[:notice] = "You've updated a tier."

    if tier.one_time?
      redirect_to sponsorable_dashboard_tiers_path(frequency: "one-time")
    else
      redirect_to sponsorable_dashboard_tiers_path
    end
  rescue Sponsors::UpdateSponsorsTier::UnprocessableError => error
    flash[:error] = error.message
    render_edit_form
  end

  sig { void }
  def destroy
    tier = T.must_because(self.tier) { "#require_non_custom_tier ensures non-nil" }
    frequency_param = tier.one_time? ? "one-time" : nil
    Sponsors::DeleteSponsorsTier.call(tier: tier, viewer: current_user)
    redirect_to sponsorable_dashboard_tiers_path(frequency: frequency_param)
  rescue Sponsors::DeleteSponsorsTier::UnprocessableError => e
    flash[:error] = e.message
    redirect_to sponsorable_dashboard_tiers_path
  end

  protected

  sig { returns T.nilable(SponsorsTier) }
  memoize def tier
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#non_waitlisted_sponsors_listing_required ensures non-nil"
    end
    listing.sponsors_tiers.find_by(id: params[:id])
  end

  sig { void }
  def require_non_custom_tier
    return render_404 unless tier
    render_404 if T.must(tier).custom?
  end

  sig { returns T::Boolean }
  def publish_tier?
    params[:submit] == "publish_tier"
  end

  sig { returns Integer }
  memoize def amount
    if params[:amount]
      params[:amount].to_i.abs
    elsif tier
      T.must(tier).monthly_price_in_dollars.to_i
    else
      0
    end
  end

  sig { void }
  def validate_amount
    if amount.zero?
      flash[:error] = "Tier amount should be at least $1."
      return redirect_to :back
    end

    if amount > SponsorsTier::MAX_SPONSORSHIP_AMOUNT_IN_DOLLARS
      flash[:error] = "Tier amounts can't be greater than " \
        "#{SponsorsTier::MAX_SPONSORSHIP_AMOUNT_HUMAN}."
      redirect_to :back
    end
  end

  sig { void }
  def validate_published_tier_count
    return unless publish_tier?

    if reached_maximum_tier_count?
      frequency_name = one_time_frequency? ? "one-time" : "monthly"
      flash[:error] = "Max number of published, #{frequency_name} tiers reached."
      render_new_form
    end
  end

  private

  sig { returns T.nilable(Integer) }
  memoize def repository_id_param
    return unless include_repository_access?
    params[:repository_id] ? params[:repository_id].to_i : nil
  end

  sig { returns T::Boolean }
  def include_repository_access?
    params[:include_repo_access].to_s == "on"
  end

  sig { returns T.nilable(String) }
  def welcome_message_param
    params[:welcome_message] if params[:include_welcome_message]
  end

  sig { returns T::Boolean }
  def current_user_wants_test_email?
    params[SEND_TEST_EMAIL_INPUT_NAME].present?
  end

  sig { void }
  def send_test_email
    SendSponsorsPreviewEmailJob.perform_later(
      actor: current_user,
      sponsors_listing: sponsorable_sponsors_listing,
      frequency: frequency,
      welcome_message: params[:welcome_message],
      repository_id: repository_id_param,
    )
    flash[:notice] = "We sent a preview email to #{current_user.email}"
  end

  sig { void }
  def render_new_form
    new_tier = SponsorsTier.new(
      state: :draft,
      frequency: frequency,
      sponsors_listing: sponsorable_sponsors_listing
    )
    render "sponsors/tiers/new", locals: {
      tier: new_tier,
      sponsorable: sponsorable,
      sponsors_listing: sponsorable_sponsors_listing,
    }
  end

  sig { void }
  def render_edit_form
    render "sponsors/tiers/edit", locals: {
      tier: tier,
      sponsorable: sponsorable,
      sponsors_listing: sponsorable_sponsors_listing,
    }
  end

  sig { void }
  def show_tier_suggestions_if_appropriate
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#non_waitlisted_sponsors_listing_required ensures non-nil"
    end
    return if listing.disabled?
    return if listing.sponsors_tiers.any?
    return if params["skip-suggestions"].present?

    redirect_to sponsorable_dashboard_tier_suggestions_path(sponsorable)
  end

  sig { returns T::Boolean }
  memoize def reached_maximum_tier_count?
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#non_waitlisted_sponsors_listing_required ensures non-nil"
    end
    listing.reached_maximum_tier_count?(recurring: !one_time_frequency?)
  end

  helper_method :can_publish?

  sig { returns T::Boolean }
  def can_publish?
    remaining_tier_count > 0
  end

  helper_method :frequency

  sig { returns Symbol }
  memoize def frequency
    one_time_frequency? ? :one_time : :recurring
  end

  sig { returns Integer }
  memoize def recurring_published_count
    T.unsafe(tiers).recurring.with_published_state.count
  end

  sig { returns Integer }
  memoize def one_time_published_count
    T.unsafe(tiers).one_time.with_published_state.count
  end

  sig { returns ActiveRecord::Relation }
  def tiers
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#non_waitlisted_sponsors_listing_required ensures non-nil"
    end
    listing.sponsors_tiers
  end

  sig { returns Integer }
  memoize def published_tier_count_in_frequency
    if one_time_frequency?
      T.unsafe(tiers).one_time.with_published_state.count
    else
      T.unsafe(tiers).recurring.with_published_state.count
    end
  end

  sig { returns Integer }
  memoize def remaining_tier_count
    SponsorsTier::PUBLISHED_TIER_LIMIT_PER_FREQUENCY - published_tier_count_in_frequency
  end

  sig { params(tier_to_publish: SponsorsTier).void }
  def publish_tier_and_redirect(tier_to_publish)
    Sponsors::PublishSponsorsTier.call(
      tier: tier_to_publish,
      viewer: current_user,
    )

    flash[:notice] = "You've published a tier."

    if tier_to_publish.one_time?
      redirect_to sponsorable_dashboard_tiers_path(frequency: "one-time")
    else
      redirect_to sponsorable_dashboard_tiers_path
    end
  end

  sig { returns T.any(Symbol, GitHubSponsors::Types::Sponsorable) }
  def target_for_conditional_access
    return :no_target_for_conditional_access unless sponsorable # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    T.must(sponsorable)
  end

  sig { returns T.nilable(T::Boolean) }
  memoize def one_time_frequency?
    frequency_param == "one-time" || tier&.one_time?
  end
end
