# typed: true
# frozen_string_literal: true

module Stratocaster
  class DogstatsTags
    attr_accessor :event_type, :event_action, :success

    def initialize(event = nil)
      self.event = event if event
    end

    def event=(event)
      @event_type = event.event_type
      @event_action = event.action
    end

    def all
      [event_type_tag, event_tag, status_tag].compact
    end

    def event_type_tag
      "event_type:#{formatted_event_type}" if @event_type
    end

    def event_tag
      "event:#{formatted_event_action}" if @event_type
    end

    def status_tag
      "status:#{formatted_status}" unless @success.nil?
    end

    private

    def formatted_event_type
      "stratocaster/#{@event_type}".gsub(/Event/, "").underscore.downcase
    end

    def formatted_event_action
      if @event_action
        "#{formatted_event_type}_#@event_action"
      else
        formatted_event_type
      end
    end

    def formatted_status
      @success ? "success" : "failed"
    end
  end
end
