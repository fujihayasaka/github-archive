# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Octoshift
  module Errors
    class DatastoreUnavailableForWrites < StandardError
      attr_reader :role

      # Public: Initialize a DatastoreUnavailableForWrites error.
      #
      # role - A Symbol or String representing the database role.
      def initialize(role)
        @role = role.to_sym
      end

      # Public: The error message.
      #
      # Returns a String with the error message.
      def message
        "Datastore is not available for writes."
      end
    end
  end
end
