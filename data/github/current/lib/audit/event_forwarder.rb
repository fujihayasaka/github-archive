# typed: true
# frozen_string_literal: true

require "audit/event_forwarder/dotcom_service_publisher"
require "audit/event_forwarder/hydro_publisher"

module Audit
  class EventForwarder
    class SubscribeError < StandardError; end

    # Attach a new forwarder instance to event_source option or GitHub.instrumentation_service.
    #
    # See the initialize method for possible options.
    #
    # Returns a new subscribed instance of this class.
    def self.attach!(**options)
      new(**options).tap { |f| f.subscribe! }
    end

    # Initialize an EventForwarder.
    #
    # event_source - An ActiveSupport::Notifications notifier (default: GitHub.instrumentation_service).
    # subscription_keys - An Array of event names to subscribe to (default: Audit::ACTIONS).
    def initialize(event_source: nil, subscription_keys: nil)
      @event_source = event_source || GitHub.instrumentation_service
      @subscription_keys = subscription_keys || Audit::ACTIONS
    end

    # Iterate through each subscription keys and assign this class as a subscriber.
    # When an event is instrumented the Audit::EventForwarder#call method is called.
    def subscribe!
      Array.wrap(@subscription_keys).each do |sub_key|
        @event_source.subscribe(sub_key, self)
      end
    end

    # Called when an event is received from a subscription. Immediately calls the
    # Audit::EventForwader#forward_to_publishers method.
    def call(action, _, _, _, payload)
      forward_to_publishers(action, payload)
    end

    # Fans out event publishing to each publisher instance.
    def forward_to_publishers(action, payload)
      # Very important step, assigns timestamps, document_id, location values, category values, etc
      expanded_payload = GitHub.audit.build_payload(action, payload)
      # This checks the types of a few special id fields in the payload - will raise in dev and test
      expanded_payload = Audit::TypeChecker.check_payload(expanded_payload)

      # Remove primary_resource
      # NOTE: This is a temporary fix to prevent the primary_resource from being forwarded to Elasticsearch. The primary_resource
      # is an optimization that was added to improve the efficiency of webhook event processing. Due to the fact that Webhook events
      # and AuditLog events subscribe to the same ActiveSupport::Notifications instrumenter, the primary_resource attribute was
      # polluting the payload going to Elasticsearch. This change is a bandaid that fixes the immediate problem. The long term
      # solution is to move Webhooks to GlobalInstumenter.instrument instead of GitHub.instrument.
      # More information on primary_resource can be found here: https://github.com/github/ecosystem-events/issues/1587
      if expanded_payload.key?(:primary_resource)
        expanded_payload.delete(:primary_resource)
      end

      publishers.each do |publisher|
        begin
          publisher.publish(action, expanded_payload)
        rescue StandardError => e # rubocop:todo Lint/RescueException
          message = "Failed to publish #{action} audit event #{expanded_payload[:_document_id]} to #{publisher.class.name}: #{e.message}"

          if Rails.env.production? || Rails.env.staging?
            # Obfuscated error for Failbot, the real error is logged to the structured
            # logging of GitHub::Logger.
            Failbot.report(SubscribeError.new(message))
            GitHub.logger.error(e)
          else
            Failbot.report(e)
            puts message unless Rails.env.development?
          end
        end
      end
    end

    def publishers
      @publishers ||=
        if GitHub.audit_log_test_env?
          [DotcomServicePublisher.new]
        elsif GitHub.single_business_environment?
          [DotcomServicePublisher.new, HydroPublisher.new]
        else
          [HydroPublisher.new]
        end
    end
  end
end
