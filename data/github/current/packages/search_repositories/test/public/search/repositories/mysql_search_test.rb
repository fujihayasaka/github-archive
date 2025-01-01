# typed: true
# frozen_string_literal: true

require "test_helper"

class MysqlSearchTest < GitHub::TestCase
  setup do
    @org = create :enterprise_linked_organization
    @user = @org.admins.first
    @first_repo = create :repository, owner: @org, name: "aaa", stargazer_count: 0
    create :fork_repository, forker: @user, fork_repo: @first_repo, organization: @org, stargazer_count: 5
    create :archived_repository, public: true, owner: @org, stargazer_count: 5
    create :repository, template: true, owner: @org, stargazer_count: 5
    create :private_repository, owner: @org, stargazer_count: 5
    @last_repo = create :internal_repository, owner: @org, name: "zzz", stargazer_count: 10

    @first_repo.update!(pushed_at: 2.hours.ago)
    @last_repo.update!(pushed_at: Time.now + 2.hours)
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

  test "supports some sort types" do
    enable_feature_flag(:es_repos_mysql_support_sort)

    assert Search::Repositories::MysqlSearch.supported?("sort:updated", @user)
    assert Search::Repositories::MysqlSearch.supported?("sort:updated-desc", @user)
    assert Search::Repositories::MysqlSearch.supported?("sort:name", @user)
    assert Search::Repositories::MysqlSearch.supported?("sort:name-asc", @user)
    assert Search::Repositories::MysqlSearch.supported?("sort:stars", @user)
    assert Search::Repositories::MysqlSearch.supported?("sort:stars-desc", @user)
  end

  test "does not support some sort directions" do
    refute Search::Repositories::MysqlSearch.supported?("sort:name-desc", @user)
    refute Search::Repositories::MysqlSearch.supported?("sort:updated-asc", @user)
    refute Search::Repositories::MysqlSearch.supported?("sort:stars-asc", @user)
  end

  test "does not support some sort types" do
    refute Search::Repositories::MysqlSearch.supported?("sort:help-wanted-issues", @user)
    refute Search::Repositories::MysqlSearch.supported?("sort:size", @user)
    refute Search::Repositories::MysqlSearch.supported?("sort:size-asc", @user)
    refute Search::Repositories::MysqlSearch.supported?("sort:size-desc", @user)
  end

  test "search repos in the org" do
    results = Search::Repositories::MysqlSearch.search(@org, @org.admins.first, "", 1, per_page: 10, sort_order: nil, limit_to_repo_ids: nil)
    assert_equal 6, results[:repos].size
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

  [
    ["sort:name", "aaa"],
    ["sort:name-asc", "aaa"],
    ["sort:stars", "zzz"],
    ["sort:stars-desc", "zzz"],
    ["sort:stargazers", "zzz"],
    ["sort:updated-desc", "zzz"],
  ].each do |query, expected_first_repo_name|
    test "applies sort to query '#{query}'" do
      enable_feature_flag(:es_repos_mysql_support_sort)

      results = Search::Repositories::MysqlSearch.search(@org, @org.admins.first, query, 1, per_page: 10, sort_order: nil, limit_to_repo_ids: nil)
      assert_equal expected_first_repo_name, results[:repos].first[:name]
    end
  end

  [
    ["freetext", "Query not supported"],
    ["sort:name-desc", "Query not supported"],
    ["sort:stars-asc", "Query not supported"],
    ["sort:updated-asc", "Query not supported"],
    ["sort:boo", "Query not supported"],
    ["sort:boo-desc", "Query not supported"],
  ].each do |query, expected_error|
    test "raises not supported for query '#{query}'" do
      assert_raises_with_message(ArgumentError, expected_error) do
        Search::Repositories::MysqlSearch.search(@org, @org.admins.first, query, 1, per_page: 10, sort_order: nil, limit_to_repo_ids: nil)
      end
    end
  end

end
