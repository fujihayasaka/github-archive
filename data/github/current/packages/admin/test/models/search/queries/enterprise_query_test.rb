# typed: true
# frozen_string_literal: true

require "test_helper"

unless GitHub.single_business_environment?
  class SearchQueriesEnterpriseQueryTest < GitHub::TestCase
    fixtures do
      setup_search
      @business_one = Timecop.freeze(2.days.ago) do
        create :business, slug: "one-enterprises", name: "One Onnnnnnnnne Enterprises, Ltd"
      end
      @business_two = Timecop.freeze(1.day.ago) do
        create :business, slug: "two-enterprises", name: "Two Twwwwwwwwwo Enterprises, Ltd"
      end
      make_searchable(@business_one, @business_two, type: "enterprise")
    end

    setup do
      reset_cache
      @query = Search::Queries::EnterpriseQuery.new
    end

    teardown_once do
      teardown_search
    end

    test "it will only query enterprises" do
      assert_equal "enterprise", @query.query_params[:type]
    end

    test "it prunes deleted enterprises" do
      @query.phrase = "one"
      @business_one.delete

      assert_enqueued_with(job: RemoveFromSearchIndexJob, args: ["enterprise", @business_one.id]) do
        assert_empty @query.execute.results
      end
    end

    test "searches by slug" do
      @query.phrase = "one"
      assert_equal [@busines_one], @query.execute.results.map { |result| result["_model"] }

      @query.phrase = "two"
      assert_equal [@busines_two], @query.execute.results.map { |result| result["_model"] }
    end

    test "searches by name" do
      @query.phrase = "onnnnnnnnne"
      assert_equal [@busines_one], @query.execute.results.map { |result| result["_model"] }

      @query.phrase = "twwwwwwwwwo"
      assert_equal [@busines_two], @query.execute.results.map { |result| result["_model"] }
    end
  end
end
