# typed: true
# frozen_string_literal: true

require "gibbon"

module GitHub
  module Config
    class Mailchimp
      class << self
        # This key is a shared key used to allow MailChimp to POST webhooks
        # to the GitHub API via basic auth:
        # https://us11.admin.mailchimp.com/lists/tools/webhooks?id=257769
        attr_accessor :webhook_key
      end
    end
  end
end

# Set the API key globally for all Gibbon requests
Gibbon::Request.api_key = ENV["MAILCHIMP_API_KEY"]

# This key is a shared key used to allow MailChimp to POST webhooks
# to the GitHub API via basic auth:
# https://us11.admin.mailchimp.com/lists/tools/webhooks?id=257769
GitHub::Config::Mailchimp.webhook_key = ENV["MAILCHIMP_WEBHOOK_KEY"]
