# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  module Providers
    class PrefetchedProviderTest < GitHub::TestCase
      test "element configuration" do
        assert_equal "prefetched", PrefetchedProvider.type
        assert_equal 0, PrefetchedProvider.debounce
        assert_equal [:default], PrefetchedProvider.send(:modes)
      end
    end
  end
end
