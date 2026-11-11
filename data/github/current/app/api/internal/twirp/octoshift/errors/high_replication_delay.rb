# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Octoshift
  module Errors

    # Public: Used for raising errors associated with replication delay.
    class HighReplicationDelay < StandardError

      # Public: Returns the Integer amount of delay in milliseconds.
      attr_reader :delay, :role

      # Public: Initialize a HighReplicationDelay error.
      #
      # ms_delay - An Integer with the amount of delay in milliseconds.
      def initialize(ms_delay, role)
        @delay = ms_delay.ceil
        @role = role.to_sym
      end

      # Public: The error message.
      #
      # Returns a String with the error message.
      def message
        "High replication delay of #{delay}ms."
      end
    end
  end
end
