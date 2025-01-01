# typed: true
# frozen_string_literal: true

class SponsorsAddOneTimePaymentsJob < ApplicationJob
  extend T::Sig

  queue_as :sponsors_add_one_time_payments

  sig do
    params(
      amounts_by_sponsorable_login: T::Hash[String, T.any(String, Integer, Billing::Money)],
      sponsor: GitHubSponsors::Types::Sponsor,
      actor: User,
      privacy_level: T.any(String, Symbol),
      receive_email: T::Boolean,
    ).void
  end
  def perform(amounts_by_sponsorable_login:, sponsor:, actor:, privacy_level:, receive_email:)
    return unless GitHub.sponsors_enabled?

    Failbot.push(user: actor.login, user_id: actor.id) if actor
    Failbot.push(sponsor: sponsor.login, sponsor_id: sponsor.id) if sponsor
    result = T.let(nil, T.nilable(Sponsors::AddOneTimePayments::Result))
    successful_logins = T.let(Set.new, T::Set[String])

    Sponsorship.throttle_writes_with_retry do
      Billing::SubscriptionItem.throttle_writes_with_retry do
        result = Sponsors::AddOneTimePayments.call(
          sponsor: sponsor,
          actor: actor,
          amounts_by_sponsorable_login: amounts_by_sponsorable_login,
          privacy_level: privacy_level,
          receive_email: receive_email,
          after_payment_hook: ->(sponsorable_login) { successful_logins << sponsorable_login.downcase }
        )
      end
    end
  rescue Aqueduct::Worker::JobKilled, *Resiliency::Response::UnavailableExceptions => err
    sponsorable_logins = amounts_by_sponsorable_login.keys.map(&:downcase).to_set
    logins_to_retry = successful_logins ? sponsorable_logins - successful_logins : sponsorable_logins

    self.class.perform_later(
      sponsor: sponsor,
      actor: actor,
      amounts_by_sponsorable_login: amounts_by_sponsorable_login
        .select { |login, _| logins_to_retry.include?(login.downcase) },
      privacy_level: privacy_level,
      receive_email: receive_email,
    )
  end
end
