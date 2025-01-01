# typed: true
# frozen_string_literal: true

require "test_helper"

class MysqlSearchTest < GitHub::TestCase
  setup do
    @org = create :enterprise_linked_organization
    @user = @org.admins.first
    public_repo = create :repository, owner: @org
    create :fork_repository, forker: @user, fork_repo: public_repo, organization: @org
    create :archived_repository, public: true, owner: @org
    create :repository, template: true, owner: @org
    create :private_repository, owner: @org
    create :internal_repository, owner: @org
  end

  test "supported for no query" do
    assert Search::Repositories::MysqlSearch.supported?("", @user)
    assert Search::Repositories::MysqlSearch.supported?(nil, @user)
    assert Search::Repositories::MysqlSearch.supported?("   ", @user)
  end

  test "supported for known terms" do
    assert Search::Repositories::MysqlSearch.supported?("fork:true", @user)
    assert Search::Repositories::MysqlSearch.supported?("visibility:public", @user)
    assert Search::Repositories::MysqlSearch.supported?("archived:false", @user)
    assert Search::Repositories::MysqlSearch.supported?("mirror:false", @user)
    assert Search::Repositories::MysqlSearch.supported?("template:true", @user)
  end

  test "supported for small number of modifiers" do
    assert Search::Repositories::MysqlSearch.supported?("fork:true visibility:public", @user)
    assert Search::Repositories::MysqlSearch.supported?("archived:false mirror:false", @user)
  end

  test "not supported for free text" do
    refute Search::Repositories::MysqlSearch.supported?("freetext", @user)
    refute Search::Repositories::MysqlSearch.supported?("fork:true freetext", @user)
  end

  test "not supported for other terms" do
    refute Search::Repositories::MysqlSearch.supported?("fork:true archived:false x:y", @user)
    refute Search::Repositories::MysqlSearch.supported?("fork:true archived:false props.env:prod", @user)
  end

  test "not supported for comma-separated values" do
    refute Search::Repositories::MysqlSearch.supported?("visibility:internal,private", @user)
  end

  test "not supported for negated terms" do
    refute Search::Repositories::MysqlSearch.supported?("-visibility:public", @user)
    refute Search::Repositories::MysqlSearch.supported?("fork:true -visibility:public", @user)
  end

  test "not supported for a large number of terms" do
    refute Search::Repositories::MysqlSearch.supported?("fork:true visibility:public archived:false", @user)
    refute Search::Repositories::MysqlSearch.supported?("fork:true visibility:public archived:false mirror:false", @user)
  end

  test "search repos in the org" do
    results = Search::Repositories::MysqlSearch.search(@org, @org.admins.first, "", 1, per_page: 10, sort_order: nil, limit_to_repo_ids: nil)
    assert_equal 6, results[:repos].size
  end

  test "search repos throws if query not supported" do
    error = assert_raises ArgumentError do
      Search::Repositories::MysqlSearch.search(@org, @org.admins.first, "freetext", 1, per_page: 10, sort_order: nil, limit_to_repo_ids: nil)
    end
    assert_equal "Query not supported by MysqlSearch", error.message
  end

  [
    ["fork:true", 1],
    ["fork:True", 1],
    ["fork:false", 5],
    ["visibility:public", 4],
    ["visibility:Public", 4],
    ["visibility:internal", 1],
    ["visibility:private", 1],
    ["archived:true", 1],
    ["archived:True", 1],
    ["archived:false", 5],
    ["mirror:true", 0],
    ["mirror:True", 0],
    ["mirror:false", 6],
    ["template:true", 1],
    ["template:True", 1],
    ["template:false", 5],
    ["fork:false visibility:public", 3],
    ["mirror:true template:true", 0],
  ].each do |query, expected_size|
    test "search repos works for query '#{query}'" do
      results = Search::Repositories::MysqlSearch.search(@org, @org.admins.first, query, 1, per_page: 10, sort_order: nil, limit_to_repo_ids: nil)
      assert_equal expected_size, results[:repos].size
    end
  end
end
