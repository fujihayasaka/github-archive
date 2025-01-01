# typed: true
# frozen_string_literal: true

require "test_helper"

class UserLists::SortingStrategyTest < GitHub::TestCase
  test "falls back to default order when argument is invalid" do
    option = create_option("unsupported")

    assert_equal "name", option.sort_by
    assert_order_by(option, "slug")
  end

  test "name resolves to slug" do
    option = create_option("name")

    assert_equal "name", option.sort_by
    assert_order_by(option, "slug")
  end

  test "updated_at resolves to last_added_at" do
    option = create_option("updated_at")

    assert_equal "updated_at", option.sort_by
    assert_order_by(option, "last_added_at")
  end

  test "created_at resolves to last_added_at" do
    option = create_option("created_at")

    assert_equal "created_at", option.sort_by
  end

  test "casts value to string" do
    option = create_option(Struct.new(:to_s).new("created_at"))

    assert_equal "created_at", option.sort_by
    assert_order_by(option, "created_at")
  end

  test "has a default direction" do
    option = create_option("created_at")

    assert_equal "asc", option.direction
    assert_order_by(option, "created_at", "asc")
  end

  test "accepts asc direction" do
    option = create_option("created_at", :asc)

    assert_equal "asc", option.direction
    assert_order_by(option, "created_at", "asc")
  end

  test "accepts desc direction" do
    option = create_option("created_at", "desc")

    assert_equal "desc", option.direction
    assert_order_by(option, "created_at", "desc")
  end

  test "invalid direction is converted to default" do
    option = create_option("created_at", "invalid")

    assert_equal "asc", option.direction
    assert_order_by(option, "created_at", "asc")
  end

  test "serializes option as 'sort_by.direction'" do
    option = create_option("updated_at", "desc")

    assert_equal "updated_at.desc", option.serialize
  end

  test "unserialize" do
    option = klass.unserialize("updated_at.desc")

    assert_order_by(option, "last_added_at", "desc")
  end

  test "sorts array as well as active record interface" do
    a = build(:user_list, slug: "a")
    b = build(:user_list, slug: "b")
    c = build(:user_list, slug: "c")

    assert_equal %w[a b c], create_option("name", "asc").apply([a, c, b]).map(&:slug)
    assert_equal %w[c b a], create_option("name", "desc").apply([a, c, b]).map(&:slug)
  end

  test "has human names" do
    assert_equal "Name ascending (A-Z)", create_option("name", "asc").to_human
    assert_equal "Name descending (Z-A)", create_option("name", "desc").to_human
    assert_equal "Newest", create_option("created_at", "desc").to_human
    assert_equal "Oldest", create_option("created_at", "asc").to_human
    assert_equal "Last updated", create_option("updated_at", "desc").to_human
    assert_equal create_option(nil, nil).to_human, create_option("invalid", "invalid").to_human
  end

  class FakeArQuery
    attr_reader :order_value

    def order(value)
      @order_value = value
      self
    end
  end

  def create_option(*args)
    klass.new(*args)
  end

  def assert_order_by(option, expected_column, expected_direction = "asc")
    query = option.apply(FakeArQuery.new)

    expected = { expected_column => expected_direction }

    assert_equal expected, query.order_value
  end

  def klass
    UserLists::SortingStrategy
  end
end
