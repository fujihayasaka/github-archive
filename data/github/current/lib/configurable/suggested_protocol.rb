# typed: true
# frozen_string_literal: true

module Configurable
  module SuggestedProtocol
    extend T::Helpers

    requires_ancestor { Object }
    requires_ancestor { Configurable }

    KEY = "suggested_protocol"

    # Public: Get original value of suggested_protocol.
    #
    # Returns String (or "sticky" if no value is set)
    def suggested_protocol
      config.get(KEY) || "sticky"
    end

    # Public: Set the suggested protocol for helper dialogs (cloning / populating)
    #
    # Acceptable values:
    #   "sticky" - the default behaviour (remembers last used)
    #   "http"   - suggests https
    #   "ssh"    - suggests ssh (if available)
    #
    # user - User setting the value
    #
    # Returns nothing
    def set_suggested_protocol(value, user)
      unless %w[sticky http ssh].include?(value)
        raise ArgumentError, "suggested protocol value #{value.inspect} unknown"
      end

      if value == "sticky"
        config.delete(KEY, user)
      else
        config.set!(KEY, value, user)
      end
    end
  end
end
