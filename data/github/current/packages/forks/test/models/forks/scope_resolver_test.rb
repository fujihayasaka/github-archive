# typed: true
# frozen_string_literal: true

require "test_helper"

class Forks::ScopeResolverTest < GitHub::TestCase
  include Forks::FixtureHelpers

  setup do
    @root_repo = create(:repository, owner: create(:user))
    3.times { create_fork }
  end

  def resolver(result_limit:)
    @resolver = Forks::ScopeResolver.new(@root_repo, current_user: nil, include: [:active, :inactive], period: "1mo", result_limit:)
  end

  test "it clamps the results to the result limit" do
    assert_equal 1, resolver(result_limit: 1).resolve.count
    assert_equal 2, resolver(result_limit: 2).resolve.count
    assert_equal 3, resolver(result_limit: 100).resolve.count
  end
end
