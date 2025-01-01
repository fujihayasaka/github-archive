# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessTradeControlsDependencyTest < GitHub::TestCase
  fixtures do
    @business = create(:business)
  end

  context "#has_any_trade_restrictions?" do
    test "returns false for business" do
      refute_predicate @business, :has_any_trade_restrictions?
    end
  end
end
