# typed: true
# frozen_string_literal: true

module GitHub
  module Throttler

    # Behaves like the default Freno::Throttler::IdentityMapper but stablishes
    # a precondition to avoid accidentally misconfigured throttling code.
    #
    # https://github.com/github/freno-throttler/blob/master/lib/freno/throttler/mapper.rb
    #
    class SafeIdentityMapper
      def call(context)
        cluster_names = Array(context)
        if cluster_names.empty?
          raise ArgumentError.new("context must denote one or more store names: (ex mysql1, collab)")
        end
        cluster_names
      end
    end
  end
end
