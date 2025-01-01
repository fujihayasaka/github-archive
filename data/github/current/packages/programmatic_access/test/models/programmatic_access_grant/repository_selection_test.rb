# typed: true
# frozen_string_literal: true

require "test_helper"

class ProgrammaticAccessGrant::RepositorySelectionTest < GitHub::TestCase
  test "defines options" do
    assert_same_elements ProgrammaticAccessGrant::RepositorySelection::OPTIONS, %i[all none subset]
  end

  test "defines option order using the same option keys" do
    assert_same_elements(
      ProgrammaticAccessGrant::RepositorySelection::OPTIONS.map(&:to_s),
      ProgrammaticAccessGrant::RepositorySelection::OPTION_ORDER.keys
    )
  end

  test "option order value increases with level of access" do
    order_values = ProgrammaticAccessGrant::RepositorySelection::OPTION_ORDER.values_at(
      :none, :subset, :all
    )

    assert_equal order_values, order_values.sort
  end
end
