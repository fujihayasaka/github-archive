# typed: true
# frozen_string_literal: true

module Hookshot
  class Delivery

    attr_reader :attributes

    # TODO can clean this up, right?
    def self.load(hookshot_response)
      if hookshot_response.is_a? Array
        hookshot_response.map { |item| load item }
      elsif hookshot_response.is_a? Hash
        new hookshot_response
      else
        raise ArgumentError
      end
    end

    # TODO probably need more of these because different codes for ruby vs.
    # go... or maybe just don't need this at all
    def self.status_code_to_label(status_code)
      case status_code.to_i
      when 0 then :unused
      when 200..299 then :active
      when 404, 410 then :missing
      when 422 then :misconfigured
      when 500 then :hookshot_error
      when 502 then :connection_error
      when 503 then :external_service_offline
      when 504 then :timeout
      end
    end

    def self.status_class(status_label)
      case status_label
      when :active
        "success"
      when :unused
        "pending"
      else
        "failure"
      end
    end

    def self.status_code_to_class(status_code)
      status_class status_code_to_label(status_code)
    end

    def initialize(attributes)
      @attributes = attributes
    end

    def event
      attributes["event"]
    end

    def action
      attributes["action"]
    end

    def delivered_at
      attributes["delivered_at"]
    end

    def redelivery?
      attributes["redelivery"]
    end

    def delivery_guid
      attributes["guid"]
    end

    def id
      attributes["id"]
    end

    # "OK" or an error message
    def hook_response
      attributes["status"]
    end

    def payload
      @payload ||= GitHub::JSON.encode(attributes.dig("request", "payload") || {}, pretty: true)
    end

    def payload_empty?
      (attributes.dig("request", "payload") || {}) == {}
    end

    # status code
    def hook_status
      attributes["status_code"]
    end

    # TODO don't actually need this, just to help remove some confusion - using
    # this where remote call status code was previously used
    def status_code
      attributes["status_code"]
    end

    def hook_status_label
      Hookshot::Delivery.status_code_to_label attributes["status_code"]
    end

    # Returns a float
    def duration
      @duration ||= attributes["duration"].to_f
    end

    def request_headers
      attributes.dig("request", "headers")
    end

    def response_headers
      attributes.dig("response", "headers")
    end

    def response_body
      attributes.dig("response", "payload")
    end

    def url
      attributes["url"].to_s
    end
  end
end
