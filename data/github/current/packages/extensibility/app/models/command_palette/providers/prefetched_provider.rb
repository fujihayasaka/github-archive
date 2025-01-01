# typed: true
# frozen_string_literal: true

module CommandPalette
  module Providers
    # A parent class used to define a prefetched provider
    class PrefetchedProvider < ApplicationProvider
      def self.type
        "prefetched"
      end

      def self.debounce
        0
      end
    end
  end
end
