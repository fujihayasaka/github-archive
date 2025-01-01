# typed: true
# frozen_string_literal: true

# Public: Note if you're adding an HTML email, you probably want to add it to `SponsorsPrimerMailer`
# instead, to make use of Primer components for a more consistent appearance without having tons
# of ugly email-friendly HTML in your view.
class SponsorsMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include ApplicationHelper
  helper :avatar

  self.mailer_name = "mailers/sponsors"

  def newsletter(sponsorable:, sponsors:, subject:, text_body:, html_body:)
    sponsorable_email = user_email(sponsorable, allow_private: false) if sponsorable.user?
    sponsorable_email ||= github_noreply(sponsorable)

    # For org sponsors, only those who have set OrganizationProfile#sponsors_update_email will receive a newsletter:
    newsletter_bcc = sponsors.map { |sponsor| user_email(sponsor, sponsor.sponsors_update_email) }

    mail(from: github_noreply(sponsorable),
         reply_to: sponsorable_email,
         to: github_noreply,
         bcc: newsletter_bcc,
         subject: "[@#{sponsorable.display_login} GitHub Sponsors Update] #{subject}") do |format|
      format.text { text_body }
      format.html { html_body }
    end
  end

  def one_click_unsubscribe_newsletter(sponsorable:, sponsor:, subject:, text_body:, html_body:)
    sponsorable_email = user_email(sponsorable, allow_private: false) if sponsorable.user?
    sponsorable_email ||= github_noreply(sponsorable)

    # For org sponsors, only those who have set OrganizationProfile#sponsors_update_email will receive a newsletter:
    sponsor_email = user_email(sponsor, sponsor.sponsors_update_email)

    mail(
      from: github_noreply(sponsorable),
      reply_to: sponsorable_email,
      to: sponsor_email,
      subject: "[@#{sponsorable.display_login} GitHub Sponsors Update] #{subject}",
      **Sponsors::OneClickUnsubscribe.new(sponsor: sponsor, sponsorable: sponsorable).headers,
    ) do |format|
      format.text { text_body }
      format.html { html_body }
    end
  end
end
