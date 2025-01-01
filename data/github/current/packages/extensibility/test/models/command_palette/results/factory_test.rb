# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  module Results
    class ResultsFactoryTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers

      class UnkownClass; end

      test "returns nil for unkown object" do
        assert_nil Factory.build(UnkownClass.new, 1, Context::Scope.new(nil))
      end
    end
  end
end
