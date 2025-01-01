# typed: strict
# frozen_string_literal: true

class SponsorsTransactionReversalNotificationJob < ApplicationJob
  extend T::Sig

  queue_as :billing

  locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC

  sig do
    params(
      sponsor: GitHubSponsors::Types::Sponsor,
      sponsorable: GitHubSponsors::Types::Sponsorable,
      stripe_account: Billing::StripeConnect::Account
    ).returns(T.nilable(ApplicationDeliveryJob))
  end
  def perform(sponsor:, sponsorable:, stripe_account:)
    return unless GitHub.sponsors_enabled?
    return unless stripe_account.belongs_to?(sponsorable)

    SponsorsPrimerMailer.transaction_reversal(
      sponsor: sponsor,
      sponsorable: sponsorable,
      stripe_account: stripe_account,
    ).deliver_later
  end
end
