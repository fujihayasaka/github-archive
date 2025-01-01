# frozen_string_literal: true

require "stripe"

if GitHub.billing_enabled?
  background_job = GitHub.role.to_s.include?("worker")
  Stripe.api_key = GitHub.stripe_api_key
  Stripe.client_id = GitHub.stripe_client_id
  Stripe.max_network_retries = 2
  Stripe.open_timeout = (background_job ? 60 : 5)
  Stripe.read_timeout = (background_job ? 60 : 5)
end
