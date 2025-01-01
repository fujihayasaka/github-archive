# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamMemberQueryComponentsTest < GitHub::TestCase
  test "with nil query should default to empty state" do
    query = TeamMemberQueryComponents.new(nil)
    assert_equal "", query.query
    assert_equal "IMMEDIATE", query.membership
    assert_nil query.role
  end

  test "with no special parameters, returns the query and defaults other values" do
    query = TeamMemberQueryComponents.new("hello")
    assert_equal "hello", query.query
    assert_equal "IMMEDIATE", query.membership
    assert_nil query.role
  end

  test "when passing membership, removes from query and returns membership" do
    query = TeamMemberQueryComponents.new("membership:child-team hello")
    assert_equal "hello", query.query
    assert_equal "CHILD_TEAM", query.membership
  end

  test "when passing role, removes from query and returns role" do
    query = TeamMemberQueryComponents.new("role:maintainer hello")
    assert_equal "hello", query.query
    assert_equal "MAINTAINER", query.role
  end

  test "when passing role, does not remove and does not return" do
    query = TeamMemberQueryComponents.new("hello role:fake")
    assert_equal "hello role:fake", query.query
    assert_nil query.role
  end

  test "when passing in nonsense paramaters, it does not remove and does not return" do
    query = TeamMemberQueryComponents.new("hello fake:fake")
    assert_equal "hello fake:fake", query.query
    assert_nil query.role
  end

  context "when graphql is false" do
    test "with nil query should default to empty state" do
      query = TeamMemberQueryComponents.new(nil, graphql: false)
      assert_equal "", query.query
      assert_equal "immediate", query.membership
      assert_nil query.role
    end

    test "with no special parameters, returns the query and defaults other values" do
      query = TeamMemberQueryComponents.new("hello", graphql: false)
      assert_equal "hello", query.query
      assert_equal "immediate", query.membership
      assert_nil query.role
    end

    test "when passing membership, removes from query and returns membership" do
      query = TeamMemberQueryComponents.new("membership:child-team hello", graphql: false)
      assert_equal "hello", query.query
      assert_equal "child_team", query.membership
    end

    test "when passing role, removes from query and returns role" do
      query = TeamMemberQueryComponents.new("role:maintainer hello", graphql: false)
      assert_equal "hello", query.query
      assert_equal "maintainer", query.role
    end

    test "when passing role, does not remove and does not return" do
      query = TeamMemberQueryComponents.new("hello role:fake", graphql: false)
      assert_equal "hello role:fake", query.query
      assert_nil query.role
    end

    test "when passing in nonsense paramaters, it does not remove and does not return" do
      query = TeamMemberQueryComponents.new("hello fake:fake", graphql: false)
      assert_equal "hello fake:fake", query.query
      assert_nil query.role
    end
  end
end
