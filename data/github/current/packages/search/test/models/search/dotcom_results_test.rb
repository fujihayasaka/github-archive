# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchDotcomResultsTest < GitHub::TestCase
  setup do
    @hash = MultiJson.decode(
      %q|{"total_count": 306345,"incomplete_results": false,"items": [{"id": 8514,"name": "rails","full_name": "rails/rails","owner": {"login": "rails","id": 4223,"avatar_url": "https://avatars1.githubusercontent.com/u/4223?v=4"},"private": false,"html_url": "https://github.com/rails/rails","description": "Ruby on Rails","fork": false,"created_at": "2008-04-11T02:19:47Z","updated_at": "2017-10-23T11:03:03Z","pushed_at": "2017-10-23T13:41:45Z","size": 156618,"stargazers_count": 37364,"watchers_count": 37364,"language": "Ruby","has_issues": true,"has_projects": true,"has_downloads": true,"has_wiki": false,"has_pages": false,"forks_count": 15272,"mirror_url": null,"archived": false,"open_issues_count": 1172,"topics": ["activejob","activerecord","html","mvc","rails","ruby"],"forks": 15272,"open_issues": 1172,"watchers": 37364,"default_branch": "master","permissions": {"admin": false,"push": false,"pull": true},"score": 143.26695},{"id": 10496245,"name": "rails","full_name": "capistrano/rails","owner": {"login": "capistrano","id": 58257,"avatar_url": "https://avatars2.githubusercontent.com/u/58257?v=4"},"private": false,"html_url": "https://github.com/capistrano/rails","description": "Official Ruby on Rails specific tasks for Capistrano","fork": false,"created_at": "2013-06-05T06:17:50Z","updated_at": "2017-10-23T11:00:34Z","size": 112,"stargazers_count": 594,"watchers_count": 594,"language": "Ruby","has_issues": true,"has_projects": true,"has_downloads": true,"has_wiki": false,"has_pages": false,"forks_count": 229,"mirror_url": null,"archived": false,"open_issues_count": 4,"topics": ["capistrano","deployment","rails"],"forks": 229,"open_issues": 4,"watchers": 594,"default_branch": "master","permissions": {"admin": false,"push": false,"pull": true},"score": 87.00995}]}|,
    )
    @results = Search::DotcomResults.new(@hash, page: 1, per_page: 10)
  end

  context "pagination" do
    test "reports total pages available" do
      assert_equal(100, @results.total_pages)

      @hash["total_count"] = 134
      @results = Search::DotcomResults.new(@hash, page: 1, per_page: 10)
      assert_equal(14, @results.total_pages)
    end

    test "reports the previous page number" do
      assert_nil @results.previous_page

      @hash["total_count"] = 134
      @results = Search::DotcomResults.new(@hash, page: 3, per_page: 10)
      assert_equal(2, @results.previous_page)
    end

    test "reports the next page number" do
      assert_equal(2, @results.next_page)

      @hash["total_count"] = 134
      @results = Search::DotcomResults.new(@hash, page: 7, per_page: 20)
      assert_nil @results.next_page
    end

    test "reports when we are out of bounds" do
      assert !@results.out_of_bounds?

      @hash["total_count"] = 134
      @results = Search::DotcomResults.new(@hash, page: 100, per_page: 20)
      assert @results.out_of_bounds?
    end

    test "reports the current offset" do
      assert_equal(0, @results.offset)

      @hash["total_count"] = 134
      @results = Search::DotcomResults.new(@hash, page: 3, per_page: 20)
      assert_equal(40, @results.offset)
    end
  end

  context "when pagination is disabled" do
    test "page is nil" do
      @results = Search::DotcomResults.new(@hash)
      assert_nil @results.page
    end

    test "raises an ArgumentError when pagination methods are called" do
      @results = Search::DotcomResults.new(@hash)

      assert_raises(ArgumentError) { @results.total_pages }
      assert_raises(ArgumentError) { @results.previous_page }
      assert_raises(ArgumentError) { @results.next_page }
      assert_raises(ArgumentError) { @results.offset }
      assert_raises(ArgumentError) { @results.out_of_bounds? }
      assert_raises(ArgumentError) { @results.current_page }
    end
  end

  context "empty results" do
    test "empty results should always have pagination enabled" do
      @results = Search::DotcomResults.empty

      assert_equal 0, @results.total_pages
      assert_nil @results.previous_page
      assert_nil @results.next_page
      assert_equal 0, @results.offset
      assert @results.out_of_bounds?
    end

    test "contains no search results" do
      @results = Search::DotcomResults.empty

      assert @results.empty?
      assert_empty @results.results
    end
  end
end
