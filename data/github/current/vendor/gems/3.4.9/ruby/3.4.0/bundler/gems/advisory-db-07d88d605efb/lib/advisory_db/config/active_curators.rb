# frozen_string_literal: true

module AdvisoryDB
  module Config
    module ActiveCurators
      # If a new Curator is added to the team or if a current one leaves the team,
      # they need to be added here.  Order is not important, but this list is in
      # alphabetical order for readability.
      CURATORS = %w[
        darakian
        helixplant
        jonathanlevans
        shelbyc
        taladrane
      ].freeze

      def active_curators
        CURATORS
      end
    end
  end
end
