# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchFilterBuilderTest < GitHub::TestCase
  fixtures do
    @defunkt = create(:staff_admin_user, login: "defunkt", plan: "medium", email: "chris@ozmm.org")
    @mojombo = create(:user, login: "mojombo", email: "tom@mojombo.com")
  end

  setup do
    @quals = Search::ParsedQuery.qualifiers
    @quals[:user].must %w[defunkt mojombo]
    @quals[:repo].must "mojombo/toml"
    @quals[:repo].must_not "defunkt/dotjs"
    @quals[:created].must ">2013-01-01"

    @builder = Search::FilterBuilder.new @quals
  end

  test "sets the qualifiers hash" do
    builder = Search::FilterBuilder.new nil
    assert_nil builder.qualifiers
  end

  test "builds filters" do
    filter = @builder.term_filter(:repo)

    assert_equal({ term: { repo: "mojombo/toml" } }, filter.must)
    assert_equal({ term: { repo: "defunkt/dotjs" } }, filter.must_not)
  end

  test "removes negative filter items from the positive filter" do
    @quals[:user].must_not "defunkt"
    filter = @builder.term_filter(:user)

    assert_equal({ term: { user: "mojombo" } }, filter.must)
    assert_equal({ term: { user: "defunkt" } }, filter.must_not)
  end

  test "transforms values given a block" do
    @quals[:user].must "TwP"
    filter = @builder.term_filter(:user) { |login| User.find_by_login(login).try(:id) }

    assert_equal({ terms: { user: [@defunkt.id, @mojombo.id] } }, filter.must)
    assert_nil filter.must_not
  end

  test "maps field names" do
    filter = @builder.term_filter(:user_id, :user) { |login| User.find_by_login(login).try(:id) }
    assert_equal({ terms: { user_id: [@defunkt.id, @mojombo.id] } }, filter.must)
    assert_nil filter.must_not
  end

  test "can lookup different filter types" do
    filter = @builder.date_range_filter(:created_at, :created)

    assert_equal({ range: { created_at: { gt: "2013-01-01||/d" } } }, filter.must)
    assert_nil filter.must_not
  end

  test "combines multiple elements" do
    @quals[:user].must_not "defunkt"
    filter = @builder.term_filter(:users, :user, :repo)

    assert_equal({ terms: { users: %w[mojombo mojombo/toml] } }, filter.must)
    assert_equal([
      { term: { users: "defunkt" } },
      { term: { users: "defunkt/dotjs" } },
    ], filter.must_not)
  end

  test "generates a user filter" do
    filter = @builder.user_filter(:user_id, :user, exclude_private_profiles: false)

    assert_equal({ terms: { user_id: [@defunkt.id, @mojombo.id] } }, filter.must)
    assert_nil filter.must_not
  end
end
