# typed: strict
# frozen_string_literal: true

class CancelPatreonSponsorships
  extend T::Sig
  include GitHub::Memoizer

  DATADOG_PREFIX = "sponsors.patreon_sponsorships_sync"

  class UnprocessableError < StandardError; end

  # Public: Cancel Sponsorship records for no-longer-active Patreon memberships, where the given account represents
  # the maintainer who was sponsored.
  #
  # sponsors_patreon_user - a SponsorsPatreonUser instance for the sponsorable
  # actor - the User who is authenticated
  # write_mode - whether sponsorships should be cancelled versus just write a log about what would be cancelled;
  #              defaults to actually cancelling sponsorships
  #
  # Raises a CancelPatreonSponsorships::UnprocessableError if something goes wrong.
  sig do
    params(
      sponsors_patreon_user: SponsorsPatreonUser,
      sponsorships_to_cancel: T.any(T::Set[Sponsorship], T::Array[Sponsorship]),
      actor: T.nilable(User),
      write_mode: T::Boolean,
    ).void
  end
  def self.call(sponsors_patreon_user:, sponsorships_to_cancel:, actor: nil, write_mode: true)
    new(sponsors_patreon_user: sponsors_patreon_user, sponsorships_to_cancel: sponsorships_to_cancel.to_set,
      actor: actor, write_mode: write_mode).call
  end

  sig do
    params(
      sponsors_patreon_user: SponsorsPatreonUser,
      sponsorships_to_cancel: T::Set[Sponsorship],
      actor: T.nilable(User),
      write_mode: T::Boolean,
    ).void
  end
  def initialize(sponsors_patreon_user:, sponsorships_to_cancel:, actor: nil, write_mode: true)
    @sponsors_patreon_user = sponsors_patreon_user
    @sponsorships_to_cancel = sponsorships_to_cancel
    @actor = actor
    @errors = T.let([], T::Array[String])
    @write_mode = write_mode
  end

  sig { void }
  def call
    validate

    GitHub.dogstats.time("#{DATADOG_PREFIX}.cancel_sponsorships") do
      cancel_sponsorships
    end

    raise UnprocessableError.new(errors.to_sentence) if errors.present?
  end

  private

  sig { returns SponsorsPatreonUser }
  attr_reader :sponsors_patreon_user

  sig { returns T::Array[String] }
  attr_reader :errors

  sig { returns T::Set[Sponsorship] }
  attr_reader :sponsorships_to_cancel

  sig { returns T::Boolean }
  def write_mode?
    @write_mode
  end

  sig { returns User }
  def actor
    @actor || User.staff_user
  end

  sig { void }
  def validate
    raise UnprocessableError.new("GitHub Sponsors is not enabled") unless GitHub.sponsors_enabled?
    raise UnprocessableError.new("No account found") unless sponsors_patreon_user.user
    sponsorships_to_cancel.each do |sponsorship|
      unless sponsorship.sponsorable_id == sponsorable.id
        raise UnprocessableError.new("Sponsorship is not for @#{sponsorable}")
      end
      raise UnprocessableError.new("Sponsorship is not through Patreon") unless sponsorship.patreon?
    end
  end

  sig { void }
  def cancel_sponsorships
    sponsorships_to_cancel.each do |sponsorship|
      unless write_mode?
        GitHub.logger.info("Would cancel Patreon sponsorship",
          "gh.catalog_service": "github/github_sponsors",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "sponsorable.id": sponsorship.sponsorable_id,
          "sponsor.id": sponsorship.sponsor_id,
          "sponsorship.id": sponsorship.id,
          "sponsorship.tier_selected_on": sponsorship.tier_selected_date.iso8601,
          "actor.id": actor.id,
        )
        next
      end

      cancel_result = ActiveRecord::Base.connected_to(role: :writing) do
        sponsorship.cancel(actor: actor, reason: :SPONSOR_INITIATED, force: true)
      end

      unless cancel_result.success
        sponsorship_error = sponsorship.errors.full_messages.join(", ")
        errors << "Could not cancel @#{sponsorship.sponsor_login}'s sponsorship of @#{sponsorable.display_login}: " \
          "#{sponsorship_error}"
      end
    end
  end

  sig { returns GitHubSponsors::Types::Sponsorable }
  memoize def sponsorable
    T.must_because(sponsors_patreon_user.user) { "#validate ensures non-nil" }
  end
end
