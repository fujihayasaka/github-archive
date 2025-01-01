# typed: true
# frozen_string_literal: true
module Notifyd
  class Scientist
    def self.explicit_recipient_batch_size
      250
    end

    def self.notifyd_enabled?
      return false if GitHub.enterprise?
      return false unless GitHub.flipper[:publish_events_to_notifyd].enabled?
      true
    end
  end
end
