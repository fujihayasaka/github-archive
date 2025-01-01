# typed: strict
# frozen_string_literal: true

# Public: A Plain Old Ruby Object (PORO) used to support one-click unsubscribe per RFC 8058
class Sponsors::OneClickUnsubscribe
  NEWSLETTER_UNSUBSCRIBE_SCOPE = "sponsors_newsletter_unsubscribe"
  private_constant :NEWSLETTER_UNSUBSCRIBE_SCOPE
  SPONSORABLE_ID_KEY = "m_id"

  sig { params(sponsor: GitHubSponsors::Types::Sponsor, sponsorable: GitHubSponsors::Types::Sponsorable).void }
  def initialize(sponsor:, sponsorable:)
    @sponsor = sponsor
    @sponsorable = sponsorable
  end

  # Public: Opt the sponsor out of receiving future newsletters from the maintainer
  sig { params(token: String).void }
  def self.process_token(token)
    res = GitHub::Authentication::SignedAuthToken.verify(token: token, scope: NEWSLETTER_UNSUBSCRIBE_SCOPE)
    return unless res.valid?
    sponsor = res.user
    sponsorable_id = res.data[SPONSORABLE_ID_KEY]
    sponsorship = Sponsorship.find_by(sponsor: sponsor, sponsorable_id: sponsorable_id)
    return unless sponsorship
    # There's no logged-in viewer in this case, since this token can be submitted by anyone who receives the email.
    # Using the sponsor means we'll see an org as the actor for e.g. org sponsorship preference change events.
    Sponsors::UpdateSponsorshipPreferences.call(sponsorship, viewer: sponsor, email_opt_in: false)
  end

  # Public: Get a Hash of RFC 8058-compliant headers
  sig { returns T::Hash[String, String] }
  def headers
    {
      "List-Unsubscribe" => "<#{unsubscribe_url}>",
      "List-Unsubscribe-Post" => "List-Unsubscribe=One-Click"
    }
  end

  private

  sig { returns GitHubSponsors::Types::Sponsor }
  attr_reader :sponsor

  sig { returns GitHubSponsors::Types::Sponsorable }
  attr_reader :sponsorable

  sig { returns String }
  def token
    GitHub::Authentication::SignedAuthToken.generate(
      user: sponsor,
      scope: NEWSLETTER_UNSUBSCRIBE_SCOPE,
      expires: 10.years.from_now,
      data: { SPONSORABLE_ID_KEY => sponsorable.id }
    )
  end

  sig { returns String }
  def unsubscribe_url
    T.unsafe(GitHub::Application).routes.url_helpers.sponsors_one_click_unsubscribe_url(
      host: GitHub.host_name,
      protocol: "https",
      token: token
    )
  end
end
