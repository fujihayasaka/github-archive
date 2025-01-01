# typed: true
# frozen_string_literal: true

require "test_helper"

class TestQueryWithFilterHash < Search::Query
end

class TestQueryWithFields < Search::Query
  def self.field_list
    %i[user author org label sort milestone]
  end

  def self.unique_field_list
    %i[sort milestone]
  end
end

class TestCustomResponse < ::Search::Results
end

class SearchQueryTest < GitHub::TestCase
  include GitHub::LoggerHelper

  setup do
    @index = Elastomer::Index.new("test")
    @query = Search::Query.new
    @query.instance_variable_set(:@index, @index)
    GitHub::Experiment.raise_on_mismatches = false
  end

  fixtures do
    @nobody = create(:user, login: "nobody")
  end

  context "`to_offset` helper" do
    test "generates a valid offset" do
      assert_equal 0,  Search::Query.to_offset(page: 1)
      assert_equal 10, Search::Query.to_offset(page: 2)
      assert_equal 20, Search::Query.to_offset(page: 3)
    end

    test "accounts for `per_page` values" do
      assert_equal 0,  Search::Query.to_offset(page: 1, per_page: 5)
      assert_equal 7,  Search::Query.to_offset(page: 2, per_page: 7)
      assert_equal 84, Search::Query.to_offset(page: 3, per_page: 42)
    end

    test "uses default values for negative inputs" do
      assert_equal 0,  Search::Query.to_offset(page: -1)
      assert_equal 20, Search::Query.to_offset(page: 3, per_page: -1)
    end
  end

  context "when initializing" do
    test "setting the search phrase sets the query" do
      query = Search::Query.new(phrase: "looking for @defunkt -@mojombo", query: "gets ignored")

      assert_equal "looking for @defunkt -@mojombo", query.phrase
      assert_equal '"looking" "for"', query.query

      user = query.qualifiers[:user]
      assert_equal %w[defunkt], user.must
      assert_equal %w[mojombo], user.must_not
    end

    test "sets a default per_page value" do
      query = Search::Query.new
      assert_equal Search::Query::per_page_default, query.per_page
    end

    test "sets a default max_offset value" do
      query = Search::Query.new
      assert_equal Search::Query::max_offset_default, query.max_offset
    end

    test "sets preference on enterprise" do
      GitHub.stubs(:enterprise?).returns(true) # rubocop:todo GitHub/DontStubEnterpriseInTests
      @query = Search::Query.new
      assert_equal :_local, @query.preference
    end

    test "sets no preference not on enterprise" do
      GitHub.stubs(:enterprise?).returns(false) # rubocop:todo GitHub/DontStubEnterpriseInTests
      @query = Search::Query.new
      assert_nil @query.preference
    end

    test "expands macros in supported qualified terms" do
      user = create :user
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      query = TestQueryWithFields.new phrase: "unqualified user:@me milestone:@me author:@me", current_user: user
      assert_equal query.query, "unqualified"
      assert_equal query.qualifiers[:user].must, [user.login]
      assert_equal query.qualifiers[:milestone].must, ["@me"]
      assert_equal query.qualifiers[:author].must, [user.login]

      assert_equal 1, GitHub.dogstats.increments("search.me_macro").length
    end

    test "does not increment the counter when no @me is expanded" do
      user = create :user
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      query = TestQueryWithFields.new phrase: "unqualified user:someone milestone:@me", current_user: user
      assert_equal query.qualifiers[:user].must, ["someone"]
      assert_equal query.qualifiers[:milestone].must, ["@me"]

      assert_equal 0, GitHub.dogstats.increments("search.me_macro").length
    end

    # Enterprise will _always_ return :_local for the preference
    unless GitHub.enterprise?
      test "sets preference to the current user ID" do
        @query = Search::Query.new current_user: @nobody, remote_ip: "127.0.0.1"
        assert_equal @nobody.id.to_s, @query.preference
      end

      test "sets preference to the remote IP address" do
        @query = Search::Query.new remote_ip: "4.2.2.2"
        assert_equal "4.2.2.2", @query.preference
      end
    end

    test "does not support page and offset together" do
      assert_raises ArgumentError do
        Search::Query.new page: 1, offset: 3
      end
    end
  end

  context "when setting the query" do
    test "removes unbalanced quotes" do
      @query.query = %q{"this is a quoted string}
      assert_equal '"this" "is" "a" "quoted" "string"', @query.query

      @query.query = %q{moar quotes"}
      assert_equal '"moar" "quotes"', @query.query

      @query.query = %q{stupid """quotes""""""""""""}
      assert_equal %q{"stupid" """quotes"""""""""""}, @query.query
    end

    test "ignores escaped quotes" do
      @query.query = %q{"escaped \" quotes}
      assert_equal '"escaped" \" quotes', @query.query
    end

    test "inifinte quotes are dumb" do
      @query.query = %q{"}
      assert_equal "", @query.query

      @query.query = %q{""""""}
      assert_equal "", @query.query

      @query.query = %q{"} * 1023
      assert_equal "", @query.query
    end
  end

  context "when sorting" do
    test "use the given sort options" do
      query = Search::Query.new sort: %w[foo desc]
      assert_equal %w[foo desc], query.sort

      query.sort = %w[bar asc]
      assert_equal %w[bar asc], query.sort
    end

    test "parses out sort options" do
      query = Search::Query.new
      query.define_singleton_method(:qualifier_fields) { [:sort] }
      query.phrase = "foo bar sort:updated"
      assert_equal %w[updated desc], query.sort

      query.sort = nil
      query.phrase = "foo bar sort:updated-asc"
      assert_equal %w[updated asc], query.sort

      query.sort = nil
      query.phrase = "foo bar sort:comments,updated-asc"
      assert_equal %w[comments desc updated asc], query.sort

      query.sort = nil
      query.phrase = "foo bar sort:COMMENTS sort:updated-asc"
      assert_equal %w[comments desc updated asc], query.sort

      query.sort = nil
      query.phrase = "foo bar sort:comments-foo-desc,updated-asc"
      assert_equal %w[comments-foo desc updated asc], query.sort

      query.sort = %w[foo desc]
      query.phrase = "foo bar sort:updated"
      assert_equal %w[foo desc], query.sort

      query.sort = nil
      query.phrase = "foo bar sort:reactions-+1-asc"
      assert_equal %w[reactions-+1 asc], query.sort

      query.sort = nil
      query.phrase = "foo bar sort:reactions-+1"
      assert_equal %w[reactions-+1 desc], query.sort

      query.sort = nil
      query.phrase = "foo bar sort:reactions--1"
      assert_equal %w[reactions--1 desc], query.sort
    end
  end

  context "when computing offsets" do
    test "properly computes offset" do
      assert_equal 0, @query.offset

      @query.configure_page_and_offset(page: 2)
      assert_equal Search::Query::per_page_default, @query.offset

      @query.configure_page_and_offset(page: 10)
      assert_equal 9 * Search::Query::per_page_default, @query.offset
    end

    test "raises an error when the offset is too big" do
      @query.configure_page_and_offset(page: 1_000_000)
      assert_raises(Search::Query::MaxOffsetError) { @query.offset }
    end
  end

  context "when normalizing results" do
    test "pass through without a normalizer" do
      ary = %w[one two three four five]

      results = @query.normalize(ary)
      assert_same ary, results
    end

    test "invokes the normalizer when present" do
      @query.normalizer = lambda { |ary| ary.map { |val| val.to_s.upcase } }
      ary = %w[one two three four five]

      results = @query.normalize(ary)
      assert_equal %w[ONE TWO THREE FOUR FIVE], results
    end
  end

  context "when pruning results" do
    test "pass through without an overridden #prune_results method" do
      ary = %w[one two three four five]

      results = @query.prune_results(ary)
      assert_same ary, results
    end
  end

  context "when constructing queries" do
    test "builds a nil query" do
      doc = {
        query: { match_all: {} },
        _source: true,
        from: 0,
        size: Search::Query::per_page_default,
      }
      assert_equal doc, @query.query_document

      @query.configure_page_and_offset(page: 2)
      doc[:from] = Search::Query::per_page_default
      assert_equal doc, @query.query_document
    end

    test "builds a nil count query" do
      doc = { query: { match_all: {} } }
      assert_equal doc, @query.count_document
    end

    test "extracts a context for metrics annotations" do
      query = Search::Query.new(context: "testing")
      assert_equal "testing", query.context

      assert_equal "query", @query.context
    end
  end

  context "when building query params" do
    test "includes the default context" do
      params = @query.build_query_params
      assert_equal "query", params[:context]
    end

    test "includes default params" do
      params = @query.build_query_params
      assert_equal GitHub.es_query_timeout, params[:timeout], "timeout is set from the GitHub configs"

      if GitHub.enterprise?
        assert_equal :_local, params[:preference]
      else
        refute params.key?(:preference)
      end
    end
  end

  context "when caching" do
    test "build a consistent cache key" do
      @query.phrase = "foo"
      @query.configure_page_and_offset(page: 4)

      query = Search::Query.new(phrase: "foo", page: 4)

      assert_equal query.cache_key, @query.cache_key
    end

    test "cache keys change with each page" do
      key = @query.cache_key

      @query.configure_page_and_offset(page: 42)
      refute_equal key, @query.cache_key
    end

    test "ensure count_with_timeout_cache_key is different for issue query and pull request query" do
      issue_query = Search::Queries::IssueQuery.new(raw_phrase: "test is:issue")
      pull_request_query1  = Search::Queries::IssueQuery.new(raw_phrase: "test is:pr")
      pull_request_query2  = Search::Queries::IssueQuery.new(raw_phrase: "test is:pull-request")
      assert_equal true, issue_query.count_with_timeout_cache_key.start_with?("search/queries/issue_query")
      assert_equal true, pull_request_query1.count_with_timeout_cache_key.start_with?("search/queries/pull_request_query")
      assert_equal true, pull_request_query2.count_with_timeout_cache_key.start_with?("search/queries/pull_request_query")
    end
  end

  context "when executing" do
    setup do # rubocop:disable GitHub/NestedSetupTeardown
      @response = {
        "took" => 1029,
        "timed_out" => false,
        "_shards" => { "total" => 2, "successful" => 2, "failed" => 0 },
        "hits" => {
          "total" => 306345,
          "max_score" => 19.010113,
          "hits" => [
            { "_index" => "issues-3", "_type" => "milestone", "_id" => "206158", "_score" => 19.010113,  "_source" => { "number" => 6, "repo_id" => 5798298, "public" => true, "title" => "1.0.0", "description" => "Change editor", "state" => "open", "created_at" => "2012-11-03T04 => 35 => 22-07 => 00", "updated_at" => "2013-01-27T03 => 23 => 05-08 => 00", "due_on" => "2012-11-30T00 => 00 => 00-08 => 00" }, "highlight" => { "description" => ["<em>Change</em> editor"] } },
            { "_index" => "issues-3", "_type" => "milestone", "_id" => "17053", "_score" => 16.308693,  "_source" => { "number" => 1, "repo_id" => 1927093, "public" => true, "title" => "review code change", "description" => "review code change", "state" => "open", "created_at" => "2011-06-20T20 => 44 => 38-07 => 00", "updated_at" => "2013-02-14T15 => 21 => 37-08 => 00", "due_on" => "2011-06-23T00 => 00 => 00-07 => 00" }, "highlight" => { "title" => ["review code <em>change</em>"], "description" => ["review code <em>change</em>"] } },
          ],
        },
        "aggregations" => { "language" => {
          "doc_count_error_upper_bound" => 0,
          "sum_other_doc_count" => 29001,
          "buckets" => [
            { "key" => "JavaScript", "doc_count" => 69085 },
            { "key" => "Ruby", "doc_count" => 44419 },
            { "key" => "Python", "doc_count" => 37977 },
            { "key" => "PHP", "doc_count" => 34182 },
            { "key" => "Java", "doc_count" => 28707 },
            { "key" => "C", "doc_count" => 16136 },
            { "key" => "C++", "doc_count" => 13556 },
            { "key" => "C#", "doc_count" => 8352 },
            { "key" => "Objective-C", "doc_count" => 7605 },
            { "key" => "Shell", "doc_count" => 4979 },
          ],
        } },
      }

      @response["hits"] = Elastomer::UpgradeShims.shim_search_response_hits(@response["hits"]) if @index.index_running_version_8_plus?
      @index.stubs(:search).returns(@response)
      @index.stubs(:count).returns(Elastomer::UpgradeShims.get_total_hits(@response["hits"]))

      @exec_query = TestQueryWithFilterHash.new
      @exec_query.instance_variable_set(:@index, @index)
    end

    test "executes the query" do
      @exec_query.configure_page_and_offset(page: 4)
      @exec_query.normalizer = lambda { |ary| ary.map { |hit| hit["_id"].to_i } }
      results = @exec_query.execute

      assert_equal [206158, 17053], results.results
      assert_equal 4, results.page
      assert_equal Search::Query::per_page_default, results.per_page
      assert_equal @response["took"], results.time
      assert_equal Elastomer::UpgradeShims.get_total_hits(@response["hits"]), results.total
    end

    test "executes the count query" do
      @exec_query.configure_page_and_offset(page: 4)
      @exec_query.normalizer = lambda { |ary| ary.map { |hit| hit["_id"].to_i } }

      assert_equal Elastomer::UpgradeShims.get_total_hits(@response["hits"]), @exec_query.count
    end

    test "count_with_timeout handles non-nested index response" do
      @response["hits"] = { "total" => Elastomer::UpgradeShims.get_total_hits(@response["hits"]) }
      @index.stubs(:count_with_timeout).returns(@response)
      assert_equal @response["hits"]["total"], @exec_query.count_with_timeout.total
    end

    test "count_with_timeout handles nested index response" do
      @response["hits"] = Elastomer::UpgradeShims.shim_search_response_hits(@response["hits"])
      @index.stubs(:count_with_timeout).returns(@response)
      assert_equal @response["hits"]["total"]["value"], @exec_query.count_with_timeout.total
    end

    test "executes the count_with_timeout query with size=0" do
      @index.expects(:count_with_timeout).with do |doc, _params|
        assert_equal doc[:size], 0
      end

      @exec_query.count_with_timeout
    end

    test "logs query metadata" do
      GitHub.stubs(:context).returns({
        actor_ip: "122.2.2.1",
        request_id: "the-request-id",
        url: "the-url",
        user_agent: "the-user-agent",
      })

      log_received_with_at = T.let(false, T::Boolean)
      log_received_with_cache_key = T.let(false, T::Boolean)

      output = capture_logs do
        @exec_query.execute
      end

      output.each_line do |actual_line|
        if actual_line.include?("code.function=\"execute\"")
          log_received_with_at = true
          assert_log_match(actual_line, "http.client_ip", "122.2.2.1")
          assert_log_match(actual_line, "gh.request_id", "the-request-id")
          assert_log_match(actual_line, "gh.context.url", "the-url")
          assert_log_match(actual_line, "http.request.header.x_original_user_agent", "the-user-agent")
          assert_log_match(actual_line, "db.elasticsearch.path_parts.index", "test")
        elsif actual_line.include?("code.function=\"cache_key\"")
          log_received_with_cache_key = true
          assert_log_match(actual_line, "gh.search.cache_key.value", /test_query_with_filter_hash:\w{64}:v3/)
        else
          raise "Unexpected log entry"
        end
      end

      assert log_received_with_at, "expected GitHub.logger.info to have been received at least once with a hash including the key :at"
      assert log_received_with_cache_key, "expected GitHub.logger.info to have been received at least once with a hash including the key :cache_key"
    end

    context "with a normalizer that converts the results object type" do
      test "properly sends data to hydro" do
        @exec_query.normalizer = lambda { |results| results.map! { |_h| Object.new } }

        GlobalInstrumenter.expects(:instrument).with do |_event, payload|
          assert_equal(@response["hits"]["hits"].count, payload[:results].count)
        end

        @exec_query.execute
      end
    end

    context "query errors" do
      # It would be ideal to test the case where the first request "times out" and the
      # second request succeds; to ensure that we record two per-request metrics and one
      # overall metric. So far, I've been unable to stub or otherwise tweak the request
      # pipeline to get the second request to be processed with the usual Faraday bits.

      # OTOH it's pretty straightforward to make all the requests time out.
      test "records only per-request metrics when all (re)tries time out" do
        @index.unstub(:search)
        issue = create(:issue)
        make_searchable issue

        # This will recreate the client using the stubbed GitHub.dogstats value
        # for GitHub::FaradayMiddleware::Dogstats
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        Elastomer.router.reset!
        query = Search::Queries::IssueQuery.new(phrase: issue.title)
        query.count
        GitHub.dogstats.reset

        Typhoeus::Request.any_instance.stubs(:run).raises(Faraday::TimeoutError.new)

        query.execute

        # The datadog middleware should record a metric for each (re)try
        assert_equal 2, GitHub.dogstats.distributions("gh.faraday_client.dist_time").count

        # The second request succeeds and instrumentation should record an overall metric
        assert_equal 0, GitHub.dogstats.distributions("rpc.elasticsearch.dist.time").count
      end

      test "it increments a counter in graphite if timed_out? based on index" do
        @index.unstub(:search)
        GitHub.stubs(:hydro_enabled?).returns(true)
        FlipperSubscriber.stubs(:client).returns(MemoryStatsD.new)
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        response = Faraday::Response.new \
          status: 200,
          body: @response.merge("timed_out" => true),
          url: URI.parse("http://localhost:9200/test/_search"),
          method: "get"

        @index.client.connection.stubs(:get).returns(response)

        assert @exec_query.execute.timed_out?

        assert_datadog_timing_recorded = lambda do |key, tags|
          timings = GitHub.dogstats.timings(key)
          assert timings.length > 0,
            "No timings for #{key.inspect} found in #{GitHub.dogstats.timings.map { |s| s.stat }.inspect}"

          timings.each do |timing|
            tags.each do |tag|
              assert_includes timing.tags, tag
            end
          end
        end

        expected_tags = [
          "rpc_operation:search",
          "index:test",
          "timed_out:true",
          "catalog_service:github/search_muddle",
        ].to_set

        assert_datadog_timing_recorded.call("rpc.elasticsearch.time", expected_tags)

        assert_equal 1, GitHub.dogstats.distributions("rpc.elasticsearch.dist.time").count
        assert_empty expected_tags - GitHub.dogstats.distributions("rpc.elasticsearch.dist.time").first.tags
      end

      test "reports query parsing errors to datadog and splunk" do
        Failbot.expects(:report).never

        stats = GitHub::MemoryDogstatsD.new
        GitHub.stubs(:dogstats).returns(stats)

        @index.stubs(:search).raises(ElastomerClient::Client::RequestError.new(
"{\"root_cause\"=>[{\"type\"=>\"query_parsing_exception\", \"reason\"=>\"FaileyRni5yU7zaIonSg\", \"reason\"=>{\"type\"=>\"query_parsing_exception\", \"reason\"=>\"Failed to parse query [treeish OR]\", \"index\"=>\"code-search-test-1\", \"line\"=>1, \"col\"=>131, \"caused_by\"=>{\"type\"=>\"parse_exception\", \"reason\"=>\"Cannot parse 'treeish OR': Encountered \\\"<EOF>\\\" at line 1, column 10.\\nWas expecting one of:\\n    <NOT> ...\\n    \\\"+\\\" ...\\n    \\\"-\\\" ...\\n    <BAREOPER> ...\\n    \\\"(\\\" ...\\n    \\\"*\\\" ...\\n    <QUOTED> ...\\n    <TERM> ...\\n    <PREFIXTERM> ...\\n    <WILDTERM> ...\\n    <REGEXPTERM> ...\\n    \\\"[\\\" ...\\n    \\\"{\\\" ...\\n    <NUMBER> ...\\n    <TERM> ...\\n    \\\"*\\\" ...\\n    \", \"caused_by\"=>{\"type\"=>\"parse_exception\", \"reason\"=>\"Encountered \\\"<EOF>\\\" at line 1, column 10.\\nWas expecting one of:\\n    <NOT> ...\\n    \\\"+\\\" ...\\n    \\\"-\\\" ...\\n    <BAREOPER> ...\\n    \\\"(\\\" ...\\n    \\\"*\\\" ...\\n    <QUOTED> ...\\n    <TERM> ...\\n    <PREFIXTERM> ...\\n    <WILDTERM> ...\\n    <REGEXPTERM> ...\\n    \\\"[\\\" ...\\n    \\\"{\\\" ...\\n    <NUMBER> ...\\n    <TERM> ...\\n    \\\"*\\\" ...\\n    \"}}}}]}",
        ))

        results = T.let(nil, T.untyped)
        assert_logged("code.function" => "execute") do
          results = @exec_query.execute
        end
        assert results.empty?
        assert results.parse_error?

        assert stat = stats.increments("search.query.errors")[0]
        assert_includes stat.tags, "index:#{@index.name}"
        assert_includes stat.tags, "error:parse-failure"
        assert_includes stat.tags, "es_cluster:#{@index.cluster_name}"
      end

      test "logs error metadata" do
        GitHub.stubs(:context).returns({
          actor_ip: "122.2.2.1",
          request_id: "the-request-id",
          url: "the-url",
          user_agent: "the-user-agent",
        })

        @index.stubs(:search).raises(
          ElastomerClient::Client::RequestError.new(
            Faraday::Response.new(
              status: 400,
              body: {
                "error" => {
                  "root_cause" => [{
                    "type" => "query_parsing_exception",
                    "reason" => "Failed to parse query [\"communitywestbank\" OR \"ntt\\-logisco.co.jp\" OR \"SF_USERNAME salesforce\" OR \"dview.org\" OR]",
                    "index" => "commits-1",
                    "line" => 1,
                    "col" => 224,
                  }],
                  "type" => "search_phase_execution_exception",
                  "reason" => "all shards failed",
                  "phase" => "query_fetch",
                  "grouped" => true,
                  "failed_shards" => [{
                    "shard" => 0,
                    "index" => "commits-1",
                    "node" => "neI1H-yFSF-z0rQ1CYuJCA",
                    "reason" => {
                      "type" => "query_parsing_exception",
                      "reason" => "Failed to parse query [\"communitywestbank\" OR \"ntt\\-logisco.co.jp\" OR \"SF_USERNAME salesforce\" OR \"dview.org\" OR]",
                      "index" => "commits-1",
                      "line" => 1,
                      "col" => 224,
                      "caused_by" => {
                        "type" => "parse_exception",
                        "reason" => "Cannot parse '\"communitywestbank\" OR \"ntt\\-logisco.co.jp\" OR \"SF_USERNAME salesforce\" OR \"dview.org\" OR': Encountered \"<EOF>\" at line 1, column 89.\nWas expecting one of:\n    <NOT> ...\n    \"+\" ...\n    \"-\" ...\n    <BAREOPER> ...\n    \"(\" ...\n    \"*\" ...\n    <QUOTED> ...\n    <TERM> ...\n    <PREFIXTERM> ...\n    <WILDTERM> ...\n    <REGEXPTERM> ...\n    \"[\" ...\n    \"{\" ...\n    <NUMBER> ...\n    <TERM> ...\n    \"*\" ...\n    ", "caused_by" => {
                          "type" => "parse_exception",
                          "reason" => "Encountered \"<EOF>\" at line 1, column 89.\nWas expecting one of:\n    <NOT> ...\n    \"+\" ...\n    \"-\" ...\n    <BAREOPER> ...\n    \"(\" ...\n    \"*\" ...\n    <QUOTED> ...\n    <TERM> ...\n    <PREFIXTERM> ...\n    <WILDTERM> ...\n    <REGEXPTERM> ...\n    \"[\" ...\n    \"{\" ...\n    <NUMBER> ...\n    <TERM> ...\n    \"*\" ...\n    ",
                        }
                      },
                    },
                  }],
                },
                "status" => 400,
              },
            ),
          ),
        )

        expected_payload = {
          "code.function" => "execute",
          "http.client_ip" => "122.2.2.1",
          "gh.request_id" => "the-request-id",
          "gh.context.url" => "the-url",
          "http.request.header.x_original_user_agent" => "the-user-agent",
          "gh.search.error.name" => "parse-failure",
          "gh.search.error.type" => '"query_parsing_exception"',
          "gh.search.error.reason" => /.+Failed to parse query \[\\+"communitywestbank\\+" OR \\+"ntt\\+-logisco\.co\.jp\\+" OR \\+"SF_USERNAME salesforce\\+" OR \\+"dview\.org\\+" OR\].+/,
          "gh.search.error.index" => '"commits-1"',
          "db.elasticsearch.path_parts.index" => "test"
        }
        assert_logged(**expected_payload) do
          @exec_query.execute
        end
      end

      test "timeout errors are logged and tracked in DataDog, not via Failbot" do
        Failbot.expects(:report).never
        stats = GitHub::MemoryDogstatsD.new
        GitHub.stubs(:dogstats).returns(stats)
        @index.stubs(:search).raises(ElastomerClient::Client::TimeoutError)

        expected_payload = {
          "exception.type" => "ElastomerClient::Client::TimeoutError"
        }
        results = T.let(nil, T.untyped)
        assert_logged(**expected_payload) do
          results = @exec_query.execute
        end
        assert results.empty?
        refute results.parse_error?

        assert stat = stats.increments("search.query.errors")[0]
        assert_includes stat.tags, "index:#{@index.name}"
        assert_includes stat.tags, "error:timeout-error"
      end

      test "errors return the correct results class" do
        @index.stubs(:search).raises(ElastomerClient::Client::TimeoutError)

        results = @exec_query.execute(results_class: TestCustomResponse)
        assert results.empty?
        assert results.is_a?(TestCustomResponse)
      end
    end

    context "query validations" do
      test "long queries are invalid" do
        query = TestQueryWithFilterHash.new phrase: <<-PHRASE
          next to of course god america i
          love you land of the pilgrims' and so forth oh
          say can you see by the dawn's early my
          country 'tis of centuries come and go
          and are no more what of it we should worry
          in every language even deafanddumb
          thy sons acclaim your glorious name by gorry
          by jingo by gee by gosh by gum
          why talk of beauty what could be more beaut-
          iful than these heroic happy dead
          who rushed like lions to the roaring slaughter
          they did not stop to think they died instead
          then shall the voice of liberty be mute?

          He spoke. And drank rapidly a glass of water
        PHRASE

        assert !query.valid_query?, "search phrase is too long"
        assert_equal "The search is longer than 256 characters.", query.invalid_reason
      end

      test "more than five conditionals are disallowed" do
        query = TestQueryWithFilterHash.new phrase: "foo OR bar AND baz NOT buz || biz && bit"
        assert query.valid_query?, "up to five conditionals are allowed"

        query = TestQueryWithFilterHash.new phrase: "foo OR bar AND baz NOT buz || biz && bit OR too many"
        assert !query.valid_query?, "but six is right out"
        assert_equal "More than five AND / OR / NOT operators were used.", query.invalid_reason
      end

      test "logical operator only queries are disallowed" do
        %w[AND OR NOT || &&].each do |phrase|
          query = TestQueryWithFilterHash.new phrase: phrase
          assert !query.valid_query?, "logical operators without terms cause errors"
          assert_equal "The search contains only logical operators (AND / OR / NOT) without any search terms.", query.invalid_reason
        end

        query = TestQueryWithFilterHash.new phrase: "NOT OR"
        assert !query.valid_query?, "logical operators without terms cause errors"

        query = TestQueryWithFilterHash.new phrase: "&& ||"
        assert !query.valid_query?, "logical operators without terms cause errors"

        query = TestQueryWithFilterHash.new phrase: "SYSTEM_PERFORMANCE_INFORMATION"
        assert query.valid_query?, "have we anchored our regular expressions my precious?"

        query = TestQueryWithFilterHash.new phrase: "HAND"
        assert query.valid_query?, "have we anchored our regular expressions my precious?"
      end
    end
  end

  context "github_connect dotcom results query" do
    setup do # rubocop:disable GitHub/NestedSetupTeardown
      @dotcom_response = {
        "total_count" => 6076,
        "incomplete_results" => false,
        "items" => [
            {
                "login" => "railstutorial",
                "id" => 35562,
                "avatar_url" => "https://avatars1.githubusercontent.com/u/35562?v=4",
                "html_url" => "https://github.com/railstutorial",
                "type" => "User",
                "site_admin" => false,
                "score" => 97.46734,
                "text_matches" => [],
            },
            {
                "login" => "hfpp2012",
                "id" => 740643,
                "avatar_url" => "https://avatars2.githubusercontent.com/u/740643?v=4",
                "html_url" => "https://github.com/hfpp2012",
                "type" => "User",
                "site_admin" => false,
                "score" => 80.11921,
                "text_matches" => [],
            },
          ],
        }

      @dotcom_query = TestQueryWithFilterHash.new(
        query: "red bull",
        raw_phrase: "is:issue is:open red bull",
      )
      @search_type = "users"
      @search_headers = {
        "Accept" => %w(
          application/vnd.github.text-match+json
          application/vnd.github.extended-search-results+json
        ).join(", "),
      }
    end

    test "execute dotcom returns results when no errors are encountered" do
      GitHub::Connect.expects(:execute_dotcom_search).
        with(@search_type, "is:issue is:open red bull", 4, @search_headers, nil).
        returns(@dotcom_response)
      @dotcom_query.configure_page_and_offset(page: 4)
      @dotcom_query.dotcom_normalizer = lambda { |ary| ary.map { |hit| hit["id"] } }
      results = @dotcom_query.execute_dotcom(@nobody, "users")

      assert_equal [35562, 740643], results.results
      assert_equal 4, results.page
      assert_equal Search::Query::per_page_default, results.per_page
    end

    test "identifies user (by passing its token) if private search enabled *and* user profile is connected" do
      common_params = [@search_type, "is:issue is:open red bull", nil, @search_headers]
      params_without_token = common_params + [nil]
      params_with_token    = common_params + ["user_token"]

      # Default search
      GitHub::Connect.expects(:execute_dotcom_search).
        with(*params_without_token).returns(@dotcom_response)
      @dotcom_query.execute_dotcom(@nobody, "users")

      # After enabling pravate search
      GitHub.stubs(:dotcom_private_search_enabled?).returns(true)
      GitHub::Connect.expects(:execute_dotcom_search).
        with(*params_without_token).returns(@dotcom_response)
      @dotcom_query.execute_dotcom(@nobody, "users")

      # After connecting user profile
      dotcom_user = DotcomUser.for(@nobody)
      dotcom_user.token = "user_token"
      dotcom_user.save!
      GitHub::Connect.expects(:execute_dotcom_search).
        with(*params_with_token).returns(@dotcom_response)
      @dotcom_query.execute_dotcom(@nobody, "users")
    end

    test "it returns a timeout error when the request times out" do
      GitHub::Connect.expects(:execute_dotcom_search).
        with(@search_type, "is:issue is:open red bull", nil, @search_headers, nil).
        returns(GitHub::Result.error(GitHub::Connect::TimeoutError.new(GitHub::Connect::TimeoutError)))
      results = @dotcom_query.execute_dotcom(@nobody, "users")

      assert results.timed_out?
    end

    test "returns empty dotcom results if the response from dotcom is empty" do
      GitHub::Connect.expects(:execute_dotcom_search).
        with(@search_type, "is:issue is:open red bull", nil, @search_headers, nil).
        returns({ "total_count" => 0, "incomplete_results" => false, "items" => [] })
      results = @dotcom_query.execute_dotcom(@nobody, "users")

      assert results.empty?
    end
  end
end

class SearchQueryWithCircuitBreakerTest < GitHub::TestCase
  include GitHub::LoggerHelper

  fixtures do
    # Using an issue for testing the circuit breaker because issue query instantiation
    # calls Elastomer::Indexes::Issues.searcher, which tries to hit the ES cluster and
    # raises a ServerError when the circuit breaker is open.
    @issue = create(:issue)
    make_searchable @issue
  end

  setup do
    close_elasticsearch_circuit_breaker

    # Reset Elastomer to ensure that query initialization needs a round trip
    # through the resilient/circuit breaker bits.
    Elastomer.router.reset!
  end

  teardown do
    close_elasticsearch_circuit_breaker
  end

  context "when the circuit breaker is open" do
    test "initializes the query" do
      open_elasticsearch_circuit_breaker

      assert_nothing_raised do
        Search::Queries::IssueQuery.new(phrase: @issue.title)
      end
    end

    test "executes the query" do
      open_elasticsearch_circuit_breaker

      assert_nothing_raised do
        query = Search::Queries::IssueQuery.new(phrase: @issue.title)
        results = query.execute
        assert_empty results
        assert_predicate results, :error?
      end
    end

    test "executes the count query" do
      open_elasticsearch_circuit_breaker

      assert_nothing_raised do
        query = Search::Queries::IssueQuery.new(phrase: @issue.title)
        assert_equal 0, query.count
      end
    end

    test "executes the count_with_timeout query" do
      open_elasticsearch_circuit_breaker

      assert_nothing_raised do
        query = Search::Queries::IssueQuery.new(phrase: @issue.title)
        results = query.count_with_timeout
        assert_equal 0, results.total
        assert_predicate results, :error?
      end
    end
  end
end
