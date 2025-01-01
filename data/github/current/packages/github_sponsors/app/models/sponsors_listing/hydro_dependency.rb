# typed: true
# frozen_string_literal: true

module SponsorsListing::HydroDependency
  extend ActiveSupport::Concern

  extend T::Helpers

  requires_ancestor { SponsorsListing }

  # See values in lib/hydro/schemas/github/sponsors/v1/entities/sponsors_listing_pb.rb:
  HYDRO_OTHER_FISCAL_HOST = "OTHER"
  HYDRO_NO_FISCAL_HOST = "NONE"
  HYDRO_FISCAL_HOSTS_BY_LOGIN = {
    "conservancy" => "SOFTWARE_FREEDOM_CONSERVANCY",
    "numfocus" => "NUMFOCUS",
    "Open-Collective-Foundation" => "OPEN_COLLECTIVE_FOUNDATION",
    "Open-Source-Collective" => "OPEN_SOURCE_COLLECTIVE",
    "hello-europe" => "OPEN_COLLECTIVE_EUROPE",
    "softwareunderground" => "SOFTWARE_UNDERGROUND",
    "psf" => "PYTHON_SOFTWARE_FOUNDATION",
    "SPI" => "SOFTWARE_IN_THE_PUBLIC_INTEREST",
    "hackclub" => "HACK_CLUB"
  }.freeze

  HYDRO_FEATURED_STATES = %w(featured_disabled allowed active).freeze
  HYDRO_CURRENT_STATES = %w(draft pending_verification verified unverified_and_pending_approval
    verified_and_pending_approval failed_verification approved disabled waitlisted denied
    banned pending_approval).freeze

  # The different checkout flows that lead to the Sponsorship checkout page to be rendered.
  # These values are used when triggering the "checkout viewed" event in Hydro.
  HYDRO_SPONSORSHIP_CHECKOUT_NEW = "NEW"
  HYDRO_SPONSORSHIP_CHECKOUT_REACTIVATION = "REACTIVATION"
  HYDRO_SPONSORSHIP_CHECKOUT_MANAGE = "MANAGE"
  HYDRO_SPONSORSHIP_CHECKOUT_DOWNGRADE = "DOWNGRADE"
  HYDRO_SPONSORSHIP_CHECKOUT_UPGRADE = "UPGRADE"

  # The different billing plans the sponsor can have.
  HYDRO_SPONSOR_PLAN_MONTHLY = "MONTHLY"
  HYDRO_SPONSOR_PLAN_YEARLY = "YEARLY"
  HYDRO_SPONSOR_PLAN_NONE = "NONE"

  sig { params(field: String).void }
  def increment_unknown_hydro_value_count(field)
    GitHub.dogstats.increment("sponsors_listing.unknown_hydro_value", tags: ["field:#{field}"])
  end

  sig { returns String }
  def hydro_fiscal_host
    return HYDRO_NO_FISCAL_HOST unless uses_fiscal_host?
    HYDRO_FISCAL_HOSTS_BY_LOGIN[parent_sponsorable_login] || HYDRO_OTHER_FISCAL_HOST
  end

  sig { returns String }
  def hydro_featured_state
    result = if featured_disabled?
      "featured_disabled"
    else
      featured_state.to_s
    end
    unless HYDRO_FEATURED_STATES.include?(result)
      increment_unknown_hydro_value_count("featured_state")
      return "featured_state_unknown"
    end
    result
  end

  sig { returns String }
  def hydro_current_state
    result = current_state_name.to_s
    unless HYDRO_CURRENT_STATES.include?(result)
      increment_unknown_hydro_value_count("current_state")
      return "state_unknown"
    end
    result
  end

  sig { params(actor: User, sponsor: GitHubSponsors::Types::Sponsor, tier: SponsorsTier).void }
  def instrument_sponsorship_checkout_viewed(actor:, sponsor:, tier:)
    # todo why is this scoped to user only?
    data_collection_needed = sponsor.user? &&
      !sponsor.has_saved_trade_screening_record? &&
      !sponsor.has_valid_payment_method?(check_for_stopgap_restriction: true)

    GlobalInstrumenter.instrument("sponsors.checkout_viewed", {
      actor: actor,
      sponsorable: sponsorable,
      listing: self,
      sponsor: sponsor,
      tier: tier,
      checkout_type: hydro_sponsorship_checkout_type(sponsor: sponsor, tier: tier),
      sponsor_plan_duration: hydro_sponsor_plan_duration_type(sponsor: sponsor),
      is_sponsor_payment_method_valid: sponsor.has_valid_payment_method?,
      is_first_time_sponsor: sponsor.first_time_sponsor?,
      is_data_collection_needed: data_collection_needed,
    })
  end

  private

  sig { params(sponsor: GitHubSponsors::Types::Sponsor, tier: SponsorsTier).returns(String) }
  def hydro_sponsorship_checkout_type(sponsor:, tier:)
    existing_sponsorship = sponsor.sponsorship_as_sponsor_for(sponsorable)

    return HYDRO_SPONSORSHIP_CHECKOUT_NEW unless existing_sponsorship
    return HYDRO_SPONSORSHIP_CHECKOUT_REACTIVATION unless existing_sponsorship.active?

    if existing_sponsorship.subscribable_id == tier.id
      HYDRO_SPONSORSHIP_CHECKOUT_MANAGE
    elsif existing_sponsorship.monthly_price_in_cents > tier.monthly_price_in_cents
      HYDRO_SPONSORSHIP_CHECKOUT_DOWNGRADE
    else
      HYDRO_SPONSORSHIP_CHECKOUT_UPGRADE
    end
  end

  sig { params(sponsor: GitHubSponsors::Types::Sponsor).returns(String) }
  def hydro_sponsor_plan_duration_type(sponsor:)
    case sponsor.sponsors_plan_duration
    when User::BillingDependency::MONTHLY_PLAN
      HYDRO_SPONSOR_PLAN_MONTHLY
    when User::BillingDependency::YEARLY_PLAN
      HYDRO_SPONSOR_PLAN_YEARLY
    else
      HYDRO_SPONSOR_PLAN_NONE
    end
  end

  class_methods do

    sig { params(actor: User, submitted_actions: T::Array[T::Hash[T.any(Symbol, String), T.untyped]]).void }
    def instrument_submit_tier_builder_suggestions(actor:, submitted_actions: [])
      instrument_tier_builder_interaction(actor: actor, interaction: :SUBMIT, submitted_actions: submitted_actions)
    end

    sig { params(actor: User).void }
    def instrument_skip_tier_builder(actor:)
      instrument_tier_builder_interaction(actor: actor, interaction: :SKIP)
    end

    sig { params(actor: User).void }
    def instrument_view_tier_builder(actor:)
      instrument_tier_builder_interaction(actor: actor, interaction: :VIEW)
    end

    sig do
      params(
        actor: User,
        interaction: Symbol,
        submitted_actions: T::Array[T::Hash[T.any(Symbol, String), T.untyped]]
      ).void
    end
    def instrument_tier_builder_interaction(actor:, interaction:, submitted_actions: [])
      if submitted_actions.any?
        submitted_actions.map! do |action|
          {
            frequency: action["frequency"] == "recurring" ? :MONTHLY : :ONE_TIME,
            price_in_cents: action["price_in_cents"].to_i,
            description: action["description"],
            checked: action["checked"],
          }
        end
      end

      payload = {
        actor: actor,
        interaction: interaction,
        submitted_actions: submitted_actions,
      }

      # Hydro
      GlobalInstrumenter.instrument("sponsors.tier_builder_interaction", payload)
    end
  end
end
