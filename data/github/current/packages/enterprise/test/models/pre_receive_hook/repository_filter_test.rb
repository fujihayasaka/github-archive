# typed: true
# frozen_string_literal: true

require "test_helper"

class PreReceiveHookRepositoryFilterTest < GitHub::TestCase
  fixtures do
    @owner = create :user, login: "theowner"
    @org = create :organization, login: "theorg", admin: @owner
  end

  context "results" do
    test "returns first 15 results when there are more" do
      filter = PreReceiveHook::RepositoryFilter.new(@owner, "r")
      assert_equal 15, filter.results.per_page
    end

    test "returns empty hash when no query" do
      filter = PreReceiveHook::RepositoryFilter.new(@owner, "")
      assert_equal Hash.new, filter.results
    end

  end

  context "build_query" do
    test "searches all orgs repo when query is [org]/" do
      filter = PreReceiveHook::RepositoryFilter.new(@owner, "theorg/")
      assert_equal "fork:true user:theorg", filter.build_query
    end
    test "searches only repo names when query does not contain /" do
      filter = PreReceiveHook::RepositoryFilter.new(@owner, "repo")
      assert_equal "fork:true repo", filter.build_query
    end
    test "searches repo's in a given org when query is [org]/[repo]" do
      filter = PreReceiveHook::RepositoryFilter.new(@owner, "theorg/repo")
      assert_equal "fork:true repo user:theorg", filter.build_query
    end

  end
end
