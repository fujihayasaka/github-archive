# typed: true
# frozen_string_literal: true

class EmailSubscriptionsMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers

  self.mailer_name = "mailers/email_subscriptions"

  layout "layouts/primer_layout"
  SUBJECT = "Link to update your email preferences"

  sig { params(email: String, link: String).returns(String) }
  def preferences_center_access_link(email, link)
    @link = link

    premail(
      from: github_noreply,
      to: email,
      subject: SUBJECT,
    )
  end

  # Only sent in development & test environments.
  sig { params(email: String, query_string: String, topics_available: Array).returns(String) }
  def opt_in_and_unsubscribe_links(email, query_string, topics_available)
    @unsubscribe_links = []
    @opt_in_links = []

    topics_available.map do |topic|
      @opt_in_links << {
        title: topic[:name],
        url: "#{GitHub.url}#{opt_in_settings_email_subscriptions_path}?#{query_string}&TID=#{topic[:id]}"
      }

      @unsubscribe_links << {
        title: topic[:name],
        url: "#{GitHub.url}#{unsubscribe_settings_email_subscriptions_path}?#{query_string}&TID=#{topic[:id]}"
      }
    end

    premail(
      from: github_noreply,
      to: github_noreply,
      subject: "Email Subscription Elections Email",
    )
  end
end
