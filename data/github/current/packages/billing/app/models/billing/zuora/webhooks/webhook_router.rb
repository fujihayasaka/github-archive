# typed: strict
# frozen_string_literal: true

class Billing::Zuora::Webhooks::WebhookRouter
  extend T::Sig


  sig { params(payload: T::Hash[String, T.untyped]).void }
  def self.route_creation(payload)
    # Note, this is currently just a pass through method.
    # We will eventually introduce routing logic based on the `Subscription.stamp` value in the payload.

    # something like:
    # stamp = payload.delete("stamp")
    # if stamp.empty? || stamp == "dotcom"
    #   Billing::ZuoraWebhook.receive(payload)
    # else
    #   # route to the correct tenant
    #   client = Billing::ZuoraWebhook::Client.new(stamp)
    #   client.send_webhook(payload)
    # end

    Billing::ZuoraWebhook.receive(payload)
  end
end
