# typed: true
# frozen_string_literal: true

require "notifyd-client"

module Notifyd
  # Publish notifyd message
  #
  # Notifyd messages are expected to be published by calling Notifyd::NotifyPublisher
  # This job was created primarily to allow publishing a notifyd message asynchronously
  # and allow other processes to be run before publishing the message. E.g hamzo to check spaminess.
  class PublishNotifyMessageV2Job < ApplicationJob
    queue_as :notifyd_publish

    retry_on_dirty_exit
    retry_on_recoverable_exceptions wait: :polynomially_longer, attempts: 20
    retry_on ::Aqueduct::Client::ClientError, wait: :polynomially_longer, attempts: 20
    retry_on Notifyd::Aqueduct::UnavailableError, wait: :polynomially_longer, attempts: 20

    def perform(event_parameters)
      event = NewIntegrator::Event.from_h(event_parameters)
      actor = User.find_by(id: event.actor.id)

      if Notifyd::Publishing::ActorValidation.new(actor: actor).validate.invalid?
        GitHub.dogstats.increment("notifyd.delivery", tags: %w[type:notify status:skipped reason:invalid_actor])
        return
      end

      message = event.to_message

      if message.nil?
        # This is the same as the current reason:adapter_missing tag
        GitHub.dogstats.increment("notifyd.delivery", tags: %w[type:notify status:skipped reason:missing_message])
        return
      end

      Notifyd::NotifyPublisher.new.publish_message(message.to_h)
    end

    def stats_tags
      super + ["subject:#{arguments.first[:subject][:type].underscore}"]
    end
  end
end
