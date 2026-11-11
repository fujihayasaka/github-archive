# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Spokes
      # A list of datacenters that can be used when placing new repository replicas.
      #
      # If this is not set, all datacenters are acceptable for placement.
      attr_reader :spokes_voting_datacenters
      def spokes_voting_datacenters=(val)
        @spokes_voting_datacenters =
          case val
          when "", []
            nil
          when String
            val.split(",")
          else
            val
          end
      end

      # The pre-receive hook is now executed more directly instead of going
      # through the "in"-repository shell script.
      #
      # If needed, GHES admins can bring back the fallback code by running this:
      #   ghe-config app.github.pre-receive-fallback-enabled true
      attr_writer :pre_receive_fallback_enabled
      def pre_receive_fallback_enabled?
        !!@pre_receive_fallback_enabled
      end
    end
  end

  extend Config::Spokes
end
