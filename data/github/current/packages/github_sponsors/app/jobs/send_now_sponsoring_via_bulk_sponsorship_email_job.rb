# typed: true
# frozen_string_literal: true

class SendNowSponsoringViaBulkSponsorshipEmailJob < ApplicationJob
  extend T::Sig
  include GitHub::Memoizer

  queue_as :sponsors_emails

  retry_on_dirty_exit

  # Send a confirmation email to the sponsor about their recent bulk sponsorship.
  #
  # sponsor - User or Organization who acted as the sponsor
  # tiers_paid - Array of SponsorsTier that were paid for
  #
  # Returns nothing.
  sig { params(sponsor: GitHubSponsors::Types::Sponsor, tiers_paid: T::Array[SponsorsTier]).void }
  def perform(sponsor:, tiers_paid:)
    return unless tiers_paid.present?

    @sponsor = sponsor
    @tiers_paid = tiers_paid

    SponsorsPrimerMailer.now_sponsoring_via_bulk_sponsorship(
      sponsor: sponsor,
      total_amount: total_amount,
      is_recurring: recurring?,
      sponsorship_count: sponsorship_count,
      any_sponsored_users: any_sponsored_users?,
      any_sponsored_organizations: any_sponsored_organizations?,
      filename: export.filename,
      export_content: export.as_csv,
    ).deliver_later
  end

  private

  attr_reader :sponsor, :tiers_paid

  sig { returns String }
  def total_amount
    total_amount = tiers_paid.map(&:monthly_price_in_cents).sum
    Billing::Money.new(total_amount).format(no_cents_if_whole: true)
  end

  sig { returns T::Boolean }
  def recurring?
    tier_paid = tiers_paid.first # bulk sponsorships must all be the same frequency
    tier_paid.recurring?
  end

  sig { returns Integer }
  def sponsorship_count
    tiers_paid.count
  end

  sig { returns T::Boolean }
  def any_sponsored_users?
    tiers_paid.any? { |tier| tier.for_user? }
  end

  sig { returns T::Boolean }
  def any_sponsored_organizations?
    tiers_paid.any? { |tier| tier.for_organization? }
  end

  sig { returns Sponsors::BulkSponsorshipCheckoutExport }
  memoize def export
    Sponsors::BulkSponsorshipCheckoutExport.new(
      sponsor: sponsor,
      tiers_paid: tiers_paid,
    )
  end
end
