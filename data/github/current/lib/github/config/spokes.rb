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
    end
  end

  extend Config::Spokes
end
