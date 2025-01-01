# typed: strict
# frozen_string_literal: true

class Sponsors::UpdatesController < ApplicationController
  extend T::Sig
  include Sponsors::AdminableControllerValidations
  include TextHelper

  before_action :non_waitlisted_sponsors_listing_required
  before_action :non_banned_sponsors_listing_required
  before_action :draft_newsletter_required, only: [:edit, :update]

  layout "layouts/sponsors"

  stylesheet_bundle :sponsors

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :new, :edit],
    optional: true

  sig { void }
  def index
    sponsorable = T.must_because(self.sponsorable) { "#sponsorable_required ensures non-nil" }
    newsletters = sponsorable.sponsorship_newsletters
      .paginate(page: current_page, per_page: SponsorshipNewsletter::PER_PAGE)
      .includes(sponsors_tiers: [:subscription_items])
      .preload(:author)
      .order("created_at DESC")

    render "sponsors/updates/index", locals: {
      sponsors_listing: sponsorable_sponsors_listing,
      newsletters: newsletters,
    }
  end

  sig { void }
  def new
    sponsorable = T.must_because(self.sponsorable) { "#sponsorable_required ensures non-nil" }
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#non_waitlisted_sponsors_listing_required ensures non-nil"
    end
    published_tiers = listing.published_sponsors_tiers.to_a
    retired_tiers = listing.retired_sponsors_tiers.with_active_sponsorships.to_a
    custom_tiers = listing.unique_custom_tiers.preload(:active_subscription_items).to_a
    tier_subscription_counts = sponsorable.tier_subscription_counts(
      custom_tier_ids: custom_tiers&.map(&:id)
    )

    render "sponsors/updates/new", locals: {
      sponsorable: sponsorable,
      sponsors_listing: listing,
      published_tiers: published_tiers,
      retired_tiers: retired_tiers,
      custom_tiers: custom_tiers,
      selected_tier_ids: Array.wrap(params[:tier_id]),
      tier_subscription_counts: tier_subscription_counts
    }
  end

  sig { void }
  def create
    Sponsors::CreateSponsorshipNewsletter.call(
      sponsorable: sponsorable,
      author: current_user,
      draft: newsletter_params[:draft] == "1",
      body: newsletter_params[:body].presence,
      subject: newsletter_params[:subject].presence,
      tier_ids: newsletter_params[:tier_ids],
    )
    redirect_to sponsorable_dashboard_updates_path(sponsorable)
  rescue Sponsors::CreateSponsorshipNewsletter::UnprocessableError,
         Sponsors::CreateSponsorshipNewsletter::ForbiddenError => err
    flash[:error] = err.message
    redirect_to :back
  end

  sig { void }
  def edit
    sponsorable = T.must_because(self.sponsorable) { "#sponsorable_required ensures non-nil" }
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#non_waitlisted_sponsors_listing_required ensures non-nil"
    end
    published_tiers = listing.published_sponsors_tiers.to_a
    retired_tiers = listing.retired_sponsors_tiers.with_active_sponsorships.to_a
    custom_tiers = listing.unique_custom_tiers.preload(:active_subscription_items).to_a
    tier_subscription_counts = sponsorable.tier_subscription_counts(
      custom_tier_ids: custom_tiers&.map(&:id)
    )

    render "sponsors/updates/edit", locals: {
      sponsorable: sponsorable,
      newsletter: newsletter,
      sponsors_listing: listing,
      published_tiers: published_tiers,
      retired_tiers: retired_tiers,
      selected_tiers: newsletter.sponsors_tiers,
      custom_tiers: custom_tiers,
      tier_subscription_counts: tier_subscription_counts
    }
  end

  sig { void }
  def update
    result = Sponsors::UpdateSponsorshipNewsletter.call(
      newsletter: newsletter,
      subject: newsletter_params[:subject].presence,
      body: newsletter_params[:body].presence,
      draft: newsletter_params[:draft] == "1",
      tier_ids: newsletter_params[:tier_ids],
    )

    if result.success?
      if T.must(result.newsletter).published?
        flash[:notice] = "Your update has been published"
        return redirect_to sponsorable_dashboard_updates_path(sponsorable, newsletter)
      else
        flash[:notice] = "Your update has been saved"
        return redirect_to sponsorable_dashboard_updates_path(sponsorable)
      end
    end

    flash[:error] = T.must(result.error).message
    redirect_to :back
  end

  protected

  sig { returns ActionController::Parameters }
  def newsletter_params
    params.require(:newsletter).permit(:subject, :body, :draft, tier_ids: [])
  end

  sig { void }
  def draft_newsletter_required
    if newsletter.published?
      flash[:error] = "You can't update a published email update."
      redirect_to sponsorable_dashboard_updates_path(current_user)
    end
  end

  sig { returns SponsorshipNewsletter }
  memoize def newsletter
    sponsorable = T.must_because(self.sponsorable) { "#sponsorable_required ensures non-nil" }
    sponsorable.sponsorship_newsletters.find(params[:id])
  end

  private

  sig { returns T.any(Symbol, GitHubSponsors::Types::Sponsorable) }
  def target_for_conditional_access
    return :no_target_for_conditional_access unless sponsorable # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    T.must(sponsorable)
  end
end
