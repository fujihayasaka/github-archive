# typed: true
# frozen_string_literal: true

require "actions_data_stream/event_forwarder/hydro_publisher"

module ActionsDataStream
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
    # subscription_keys - An Array of event names to subscribe to
    def initialize(event_source: nil, subscription_keys: nil)
      @event_source = event_source || GitHub.instrumentation_service
      @subscription_keys = subscription_keys
    end

    # Iterate through each subscription keys and assign this class as a subscriber.
    # When an event is instrumented the ActionsDataStream::EventForwarder#call method is called.
    def subscribe!
      Array.wrap(@subscription_keys).each do |sub_key|
        @event_source.subscribe(sub_key, self)
      end
    end

    # Called when an event is received from a subscription. Immediately calls the
    # ActionsDataStream::EventForwarder#forward_to_publishers method.
    def call(action, _, _, _, payload)
      forward_to_publishers(action, payload)
    end

    # Fans out event publishing to each publisher instance.
    def forward_to_publishers(action, payload)
      return unless FeatureFlag.vexi.enabled?(:actions_data_stream_forward_to_publishers, default: false)

      data = payload.symbolize_keys

      now = Time.current
      event_timestamp = if data[:@timestamp].present?
        ActionsDataStream.milliseconds_to_time(data[:@timestamp]) || now
      else
        now
      end

      org_id = data[:org_id] || data[:organization_id] || data[:org]&.id
      org_id ||= data[:user]&.id if data[:user].is_a?(Organization)
      business = resolve_business(org_id, data[:business_id])

      serializable_data = data.deep_transform_values do |v|
        v.is_a?(ActiveRecord::Base) ? v.attributes : v.dup
      end
      serializable_data = serializable_data.deep_symbolize_keys

      event_payload = {
        organization_id: org_id,
        enterprise_id: business&.id,
        event_type: action,
        event_data: GitHub::JSON.encode(serializable_data),
        event_timestamp: event_timestamp,
        event_uuid: SecureRandom.uuid,
      }

      publishers.each do |publisher|
        begin
          publisher.publish(action, event_payload)
        rescue StandardError => e
          message = "Failed to publish #{action} data stream event to #{publisher.class.name}: #{e.message}"

          # Obfuscated error for Failbot, the real error is logged to the structured
          # logging of GitHub::Logger.
          Failbot.report(SubscribeError.new(message))
          GitHub.logger.error(e)
        end
      end
    end

    def publishers
      @publishers ||= [HydroPublisher.new]
    end

    private

    # Resolve the owning Business for the event.
    #
    # org_id      - Integer organization ID (may be nil).
    # business_id - Integer business ID (may be nil).
    #
    # Returns a Business or nil.
    def resolve_business(org_id, business_id)
      if business_id
        Business.find_by(id: business_id)
      elsif org_id
        Business.from_org_id(org_id)
      end
    end
  end
end
