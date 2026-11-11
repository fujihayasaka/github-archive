# typed: true
# frozen_string_literal: true

# Schema for EmailLinkClick hydro event: lib/hydro/schemas/github/v1/email_link_click_pb.rb
module EmailLinkTrackingHelper

  # Public:
  # Add params to a link sent via email to be tracked in Hydro
  #
  # url - String of the url to be tracked
  # email_source - String representing what email the click originated from
  # auto_subscribed - Boolean representing if the email was auto opted into (optional)
  #
  # Returns String
  # IE: https://github.com/explore?email_source=explore&auto_subscribed=true
  def email_link_with_tracking(url:, email_source:, auto_subscribed: nil)
    url = Addressable::URI.parse(url)
    existing_query = url.query_values || {}
    existing_query["email_source"] = email_source
    existing_query["auto_subscribed"] = auto_subscribed unless auto_subscribed.nil?
    url.query_values = existing_query
    url.to_s
  end
end
