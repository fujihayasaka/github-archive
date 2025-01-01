# typed: true
# frozen_string_literal: true

class Sponsors::SponsorablesController < ApplicationController
  extend T::Sig
  include Sponsors::SharedControllerMethods

  before_action :sponsorable_required
  before_action :non_banned_sponsors_listing_required
  before_action :non_waitlisted_sponsors_listing_required
  before_action :non_spammy_user_required
  before_action :verify_visible_to_viewer
  before_action :ensure_sponsorable_metadata_is_valid
  before_action :add_csp_exceptions, only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::Ballast,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  SPONSORS_PER_PAGE = 54
  INACTIVE_SPONSORS_PER_PAGE = 18

  # For editing billing information within a modal and sharing sponsorship to Twitter
  CSP_EXCEPTIONS = {
    img_src: [GitHub.paypal_checkout_url].freeze,
    connect_src: [GitHub.braintreegateway_url, GitHub.braintree_analytics_url].freeze,
    frame_src: [GitHub.zuora_payment_page_server].freeze,
    form_action: Sponsors::ShareButtonComponent::SHARE_URL_BY_SOCIAL.values.freeze,
  }.freeze

  stylesheet_bundle :sponsors

  def show
    instrument_view

    render "sponsors/sponsorables/show", locals: {
      sponsorable: sponsorable,
      listing: sponsorable_sponsors_listing,
      current_tier: sponsorship&.tier,
      custom_amount: prefilled_custom_amount,
      sponsoring: sponsorship.present?,
      sponsorships: sponsorships_for_sponsors_listing,
      featured_sponsorships: featured_sponsorships_for_sponsors_listing,
      active_sponsorships: active_sponsorships_for_sponsors_listing,
      inactive_sponsorships: inactive_sponsorships_for_sponsors_listing,
      is_new_sponsorship: params[:success] == "true",
      previewing: previewing?,
      featured_users: featured_users,
      tier_frequency: tier_frequency,
      sponsorship: sponsorship,
      sponsor: sponsor,
      editing: false,
      goal: sponsorable_sponsors_listing&.active_goal,
      sponsorable_metadata: sponsorable_metadata_from_params,
      show_sponsorship_tabs_on_sponsors_listing: show_sponsorship_tabs_on_sponsors_listing?,
    }
  end

  private

  sig { returns Symbol }
  def tier_frequency
    # Show one_time tiers to add if they are already a recurring sponsor
    return :one_time if sponsorship&.recurring_payment? && !sponsorship&.patreon?

    # Default to Patreon if that is the current sponsorship
    return :patreon if frequency_param.nil? && sponsorship&.patreon?

    # Respect requested Patreon frequency:
    return :patreon if frequency_param == "patreon" && patreon_enabled_for_sponsorable?

    # Respect requested one-time frequency:
    return :one_time if frequency_param == "one-time"

    # Respect requested recurring frequency:
    return :recurring if frequency_param == "recurring"

    # Default to recurring tiers if only custom amounts are available
    return :recurring if published_tiers.empty?

    # Default to one-time tiers if there are no recurring tiers
    published_recurring_tiers.any? ? :recurring : :one_time
  end

  sig { returns T.nilable(T::Boolean) }
  def patreon_enabled_for_sponsorable?
    sponsorable&.sponsors_patreon_user&.sponsorable_via_patreon?
  end

  sig { returns T.nilable(GitHubSponsors::Types::Sponsor) }
  memoize def sponsor
    return unless logged_in?
    return current_user unless params[:sponsor]
    sponsor_from_params = User.find_by_login(params[:sponsor])
    if current_user_can_select_sponsor?(sponsor_from_params)
      sponsor_from_params
    else
      current_user
    end
  end

  sig { params(potential_sponsor: T.nilable(GitHubSponsors::Types::Sponsor)).returns(T::Boolean) }
  def current_user_can_select_sponsor?(potential_sponsor)
    return false if potential_sponsor.blank?
    return true if current_user == potential_sponsor
    return false unless potential_sponsor.organization?

    org = T.cast(potential_sponsor, Organization)
    return true if org.billing_manageable_by?(current_user)
    org.member?(current_user)
  end

  sig { returns Symbol }
  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  sig { returns T.nilable(Sponsorship) }
  memoize def sponsorship
    return unless logged_in?
    potential_sponsorship = T.must_because(sponsor) { "#sponsor returns non-nil when #logged_in? is true" }
      .sponsorship_as_sponsor_for(sponsorable)
    potential_sponsorship if potential_sponsorship&.active?
  end

  sig { void }
  def instrument_view
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

  sig { returns T::Boolean }
  def previewing?
    return true if params[:preview] == "true"
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#non_banned_sponsors_listing_required ensures non-nil"
    end
    return true unless listing.approved?

    sponsor == sponsorable
  end

  sig { returns ActiveRecord::Relation }
  def published_recurring_tiers
    T.unsafe(published_tiers).with_recurrence(true)
  end

  sig { returns ActiveRecord::Relation }
  memoize def published_tiers
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#non_banned_sponsors_listing_required ensures non-nil"
    end
    listing.published_sponsors_tiers
  end
end
