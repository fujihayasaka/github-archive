# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchFiltersActionFilterTest < GitHub::TestCase
  setup do
    @quals = Search::ParsedQuery.qualifiers
  end

  test "builds an action filter" do
    @quals[:action].must("user.login")

    filter = Search::Filters::ActionFilter.new \
      field: :action,
      qualifiers: @quals,
      denylist: ["team.create"]

    assert filter.valid?
    assert_nil filter.invalid_reason, "don't want to have security leak"
  end

  test "can invalidate filter with must qualifier" do
    @quals[:action].must("user.login")
    @quals[:action].must_not("team.create")

    filter = Search::Filters::ActionFilter.new \
      field: :action,
      qualifiers: @quals,
      denylist: ["user.login"]

    refute filter.valid?
    assert_nil filter.invalid_reason, "don't want to have security leak"
  end

  test "matching must_not qualifier does not invalidate query" do
    @quals[:action].must("team.create")
    @quals[:action].must_not("user.login")

    filter = Search::Filters::ActionFilter.new \
      field: :action,
      qualifiers: @quals,
      denylist: ["user.login"]

    assert filter.valid?
  end
end
