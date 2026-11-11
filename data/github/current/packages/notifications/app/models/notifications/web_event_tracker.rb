# typed: true
# frozen_string_literal: true

module Notifications
  # Small utility class used to track what event types are triggering
  # web notifications. The idea is to track them only once since one event
  # can create many notification entries.
  class WebEventTracker
    def initialize
      @register = Set.new
    end

    def track(event)
      # NOTE: commits respond to #oid
      key = "#{event.class.name}:#{event.try(:id) || event.try(:oid)}"
      return if @register.include?(key)

      GitHub.dogstats.increment("notifications.web.event_refs", tags: ["event:#{event.class.name}"])

      @register.add(key)
    end
  end
end
