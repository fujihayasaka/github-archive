# typed: strict
# frozen_string_literal: true

class CreateAndUpdatePatreonSponsorships
  include GitHub::Memoizer

  DATADOG_PREFIX = CancelPatreonSponsorships::DATADOG_PREFIX

  class UnprocessableError < StandardError; end

  # Public: Create and update Sponsorship records where the given account represents the maintainer being sponsored.
  #
  # sponsors_patreon_user - a SponsorsPatreonUser instance for the sponsorable
  # actor - the User who is authenticated
  #
  # Raises a CreateAndUpdatePatreonSponsorships::UnprocessableError if something goes wrong.
  sig do
    params(
      sponsors_patreon_user: SponsorsPatreonUser,
      data: SponsorsPatreonSponsorshipLoader::Result,
      actor: T.nilable(User),
    ).void
  end
  def self.call(sponsors_patreon_user:, data:, actor: nil)
    new(sponsors_patreon_user: sponsors_patreon_user, data: data, actor: actor).call
  end

  sig do
    params(
      sponsors_patreon_user: SponsorsPatreonUser,
      data: SponsorsPatreonSponsorshipLoader::Result,
      actor: T.nilable(User),
    ).void
  end
  def initialize(sponsors_patreon_user:, data:, actor: nil)
    @sponsors_patreon_user = sponsors_patreon_user
    @data = data
    @actor = actor
    @errors = T.let([], T::Array[String])
  end

  sig { void }
  def call
    validate

    GitHub.dogstats.time("#{DATADOG_PREFIX}.update_sponsorships") do
      update_sponsorships
    end
    GitHub.dogstats.time("#{DATADOG_PREFIX}.create_sponsorships") do
      create_sponsorships
    end

    raise UnprocessableError.new(errors.to_sentence) if errors.present?
  end

  private

  sig { returns SponsorsPatreonUser }
  attr_reader :sponsors_patreon_user

  sig { returns T::Array[String] }
  attr_reader :errors

  sig { returns SponsorsPatreonSponsorshipLoader::Result }
  attr_reader :data

  sig { returns User }
  def actor
    @actor || User.staff_user
  end

  sig { void }
  def validate
    raise UnprocessableError.new("GitHub Sponsors is not enabled") unless GitHub.sponsors_enabled?
    unless sponsors_patreon_user.approved_sponsors_listing?
      raise UnprocessableError.new("Given account cannot be sponsored on GitHub Sponsors")
    end
  end

  sig { void }
  def update_sponsorships
    sponsorships_to_update.each do |sponsorship|
      sponsor = sponsorship.sponsor
      unless sponsor
        errors << "Could not update sponsorship of @#{sponsorable.display_login} because the sponsor no " \
          "longer exists."
        next
      end

      target_cents = target_sponsorship_cents_by_sponsor_id[sponsorship.sponsor_id]
      next unless target_cents

      new_tier_or_tier_error = existing_tier_or_new_custom_tier_for(target_cents, creator: sponsor)
      unless new_tier_or_tier_error.is_a?(SponsorsTier)
        errors << "Could not update @#{sponsorship.sponsor_login}'s sponsorship of @#{sponsorable.display_login}: " \
          "#{new_tier_or_tier_error}"
        next
      end

      begin
        ActiveRecord::Base.connected_to(role: :writing) do
          Sponsors::UpdateSponsorshipTier.call(sponsorship,
            new_tier: new_tier_or_tier_error,
            viewer: actor,
          )
        end
      rescue Sponsors::UpdateSponsorship::UnprocessableError => error
        errors << "Could not update @#{sponsorship.sponsor_login}'s sponsorship of @#{sponsorable.display_login}: " \
          "#{error.message}"
        next
      end
    end
  end

  sig { returns T::Array[Integer] }
  def new_sponsor_ids
    target_sponsorship_cents_by_sponsor_id.keys - sponsorships_to_update.map(&:sponsor_id)
  end

  sig { void }
  def create_sponsorships
    new_sponsor_ids.each do |sponsor_id|
      sponsor = sponsors_by_id[sponsor_id]
      next unless sponsor
      next if sponsor.has_any_trade_restrictions?

      target_cents = target_sponsorship_cents_by_sponsor_id[sponsor_id]
      next unless target_cents

      new_tier_or_tier_error = existing_tier_or_new_custom_tier_for(target_cents, creator: sponsor)
      unless new_tier_or_tier_error.is_a?(SponsorsTier)
        errors << "Could not create tier for @#{sponsor.display_login}'s sponsorship of " \
          "@#{sponsorable.display_login}: #{new_tier_or_tier_error}"
        next
      end

      begin
        ActiveRecord::Base.connected_to(role: :writing) do
          Sponsors::CreateRecurringSponsorship.call(
            tier: new_tier_or_tier_error,
            sponsor: sponsor,
            sponsorable: sponsors_listing.sponsorable,
            viewer: actor,
            is_public: true,
            email_opt_in: false,
            pay_prorated: false,
            sponsorable_metadata: nil,
            end_date: nil,
            payment_source: :patreon,
          )
        end
      rescue Sponsors::CreateSponsorship::UnprocessableError,
          Sponsors::CreateSponsorship::ForbiddenError => err
        errors << "Could not create @#{sponsor.display_login}'s sponsorship of @#{sponsorable.display_login}: " \
          "#{err.message}"
      end
    end
  end

  sig { returns(T::Hash[Integer, SponsorsTier]) }
  memoize def published_recurring_tiers_by_monthly_price_in_cents
    sponsors_listing.published_sponsors_tiers.recurring.index_by(&:monthly_price_in_cents)
  end

  sig { returns(T::Hash[Integer, User]) }
  memoize def sponsors_by_id
    sponsor_ids = target_sponsorship_cents_by_sponsor_id.keys
    User.where(id: sponsor_ids).index_by(&:id)
  end

  sig { params(target_amount_in_cents: Integer, creator: User).returns(T.any(SponsorsTier, String)) }
  def existing_tier_or_new_custom_tier_for(target_amount_in_cents, creator:)
    chosen_tier = published_recurring_tiers_by_monthly_price_in_cents[target_amount_in_cents]

    unless chosen_tier
      chosen_tier = SponsorsTier.new(
        monthly_price_in_cents: target_amount_in_cents,
        yearly_price_in_cents: target_amount_in_cents * 12,
        creator: creator,
        state: :custom,
        sponsors_listing: sponsors_listing,
        frequency: :recurring,
        description: "Patreon membership",
      )

      if creator.feature_enabled?(:sponsors_patreon_parent_tiers)
        parent_tier = chosen_tier.closest_lesser_value_tier
        chosen_tier.parent_tier_id = parent_tier&.id
      end

      chosen_tier.name = chosen_tier.generate_name

      success = ActiveRecord::Base.connected_to(role: :writing) { chosen_tier.save }
      unless success
        error = chosen_tier.errors.full_messages.to_sentence
        return "Could not create custom tier #{chosen_tier.name}: #{error}"
      end
    end

    chosen_tier
  end

  sig { returns GitHubSponsors::Types::Sponsorable }
  memoize def sponsorable
    T.must_because(sponsors_patreon_user.user) { "#validate ensures non-nil" }
  end

  sig { returns T::Set[Sponsorship] }
  def sponsorships_to_update
    data.sponsorships_to_update
  end

  sig { returns T::Hash[Integer, Integer] }
  def target_sponsorship_cents_by_sponsor_id
    data.target_sponsorship_cents_by_sponsor_id
  end

  sig { returns SponsorsListing }
  memoize def sponsors_listing
    T.must_because(sponsors_patreon_user.sponsors_listing) { "#validate ensures non-nil" }
  end
end
