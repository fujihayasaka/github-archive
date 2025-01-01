# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchResultsTest < GitHub::TestCase
  setup do
    @hash = MultiJson.decode(
      %q|{"took":1029,"timed_out":false,"_shards":{"total":2,"successful":2,"failed":0},"hits":{"total":306345,"max_score":19.010113,"hits":[{"_index":"issues-3","_type":"milestone","_id":"206158","_score":19.010113,"_source":{"number":6,"repo_id":5798298,"public":true,"title":"1.0.0","description":"Change editor","state":"open","created_at":"2012-11-03T04:35:22-07:00","updated_at":"2013-01-27T03:23:05-08:00","due_on":"2012-11-30T00:00:00-08:00"},"highlight":{"description":["<em>Change</em> editor"]}},{"_index":"issues-3","_type":"milestone","_id":"17053","_score":16.308693,"_source":{"number":1,"repo_id":1927093,"public":true,"title":"review code change","description":"review code change","state":"open","created_at":"2011-06-20T20:44:38-07:00","updated_at":"2013-02-14T15:21:37-08:00","due_on":"2011-06-23T00:00:00-07:00"},"highlight":{"title":["review code <em>change</em>"],"description":["review code <em>change</em>"]}},{"_index":"issues-3","_type":"milestone","_id":"259521","_score":16.235155,"_source":{"number":2,"repo_id":5754070,"public":true,"title":"Expand to unstructured mesh R2S","description":"Change the various steps to allow for unstructured mesh tallies as well as structured mesh.","state":"open","created_at":"2013-02-04T08:22:26-08:00","updated_at":"2013-02-25T10:10:50-08:00"},"highlight":{"description":["<em>Change</em> the various steps to allow for unstructured mesh tallies as well as structured mesh."]}},{"_index":"issues-3","_type":"issue","_id":"11216693","_score":15.913154,"_source":{"title":"Change","body":"Hi,\n\nI fork your repo and added some function for python and a new plugin for django.\n\nI made some incompatible change with plugins path. Because the static path are not portable for os x and custom config.\n\nYou can take a look at my changes and decide if you would like to merge or not.\n\nhttps://github.com/francisl/oh-my-fish\n\nFrancis\n","mention_ids":[],"author_id":98903,"num_comments":3,"num_reactions":1,"repo_id":5152538,"network_id":5152538,"public":true,"state":"open","number":13,"labels":[],"created_at":"2013-02-20T13:41:53-08:00","updated_at":"2013-02-21T05:18:29-08:00","comments":[{"comment_id":13861351,"body":"Hey Francis!\n\nI've been following your commits since a few days ago, and I was thinking about the changes you have done. I don't know much about python, so please, correct me if I'm wrong.\n\nThe plugins (django and python) you created are not necessary for having python or django installed and running, right? It seems to me that they are functions created for your own convenience.\nIf this is the case, I don't think it belongs to oh-my-fish. I, myself, have a bunch of plugins that are only on my dotfiles.\n\nYou have also removed the paths, does it mean you didn't install python using homebrew?\n","author_id":526122,"created_at":"2013-02-20T14:37:14-08:00","updated_at":"2013-02-20T14:37:14-08:00"},{"comment_id":13862755,"body":"Yes I'm using homebrew, but I also have many virtualenv for python and node.\n\nFor the plugins, I do have many custom plugins, which aren't in the repo. I only commit general useful command. Plugins are to provide helper functionality. You can find similar one in oh-my-zsh.\n\nAnd yes the django plugin require django to be installed, but all plugins aren't load by default.\n\nanyway, do as you please, the project is well enough structured that if you want to add something in the future it will be easy do so.\n","author_id":98903,"created_at":"2013-02-20T15:05:33-08:00","updated_at":"2013-02-20T15:05:33-08:00"},{"comment_id":13888069,"body":"Are those functions useful for any python/django user? If they are, I'll be happy to accept a pull request.\n","author_id":526122,"created_at":"2013-02-21T05:18:29-08:00","updated_at":"2013-02-21T05:18:29-08:00"}]},"highlight":{"body":["incompatible <em>change</em> with plugins path. Because the static path are not portable for os x and custom config.\n\nYou can take a look at my changes and decide if you would like"],"title":["<em>Change</em>"]}},{"_index":"issues-3","_type":"milestone","_id":"158514","_score":14.3565235,"_source":{"number":3,"due_on":"2012-09-24T00:00:00-07:00","updated_at":"2012-12-17T02:38:31-08:00","description":"Change search system","public":true,"created_at":"2012-08-09T01:28:45-07:00","repo_id":287490,"title":"2.4","state":"open"},"highlight":{"description":["<em>Change</em> search system"]}},{"_index":"issues-3","_type":"milestone","_id":"4149","_score":14.269905,"_source":{"number":2,"repo_id":1622278,"public":true,"title":"First released version","description":"Change library and translate english source","state":"open","created_at":"2011-04-18T15:18:17-07:00","updated_at":"2013-02-14T15:18:35-08:00"},"highlight":{"description":["<em>Change</em> library and translate english source"]}},{"_index":"issues-3","_type":"issue","_id":"10682727","_score":14.238852,"_source":{"updated_at":"2013-02-06T05:20:48-08:00","labels":[],"body":"Swanand\n","public":true,"author_id":2681304,"language_id":181,"pull_request_id":4009668,"created_at":"2013-02-05T23:45:49-08:00","repo_id":8046461,"num_comments":1,"num_reactions":0,"comments":[{"updated_at":"2013-02-06T05:20:48-08:00","body":"this one needs manual intervention\n","author_id":2656650,"created_at":"2013-02-06T05:20:48-08:00","comment_id":13181428}],"assignee_id":2656650,"title":"Change","state":"open","network_id":8046461,"number":1,"mention_ids":[]},"highlight":{"title":["<em>Change</em>"]}},{"_index":"issues-3","_type":"milestone","_id":"195146","_score":14.18772,"_source":{"number":3,"repo_id":6010875,"public":true,"title":"Version 2.9.0","description":"Change Log:\r\n\r\n-Changes are forthcoming ","state":"open","created_at":"2012-10-13T18:21:38-07:00","updated_at":"2012-12-02T17:39:16-08:00","due_on":"2012-12-12T00:00:00-08:00"},"highlight":{"description":["<em>Change</em> Log:\r\n\r\n-Changes are forthcoming "]}},{"_index":"issues-3","_type":"issue","_id":"11371587","_score":14.12054,"_source":{"title":"Change to use Bukkit.broadcast().","body":"We should use Bukkit.broadcast() because it does what we want, and because it\nis more correct and more efficient than the original implementation.\nFurthermore, it works on Permissibles instead of Players, which leads to\nmore flexibility and interoperability with other plugins.\n","mention_ids":[],"author_id":357646,"num_comments":1,"num_reactions":2,"repo_id":2004372,"network_id":2004372,"public":true,"state":"open","number":6,"labels":[],"created_at":"2013-02-25T10:15:44-08:00","updated_at":"2013-02-25T11:21:35-08:00","pull_request_id":4308784,"language_id":181,"comments":[{"comment_id":14068114,"body":"Very useful commit. Definitely should be pulled. Simple, but useful.\n","author_id":37625,"created_at":"2013-02-25T11:21:24-08:00","updated_at":"2013-02-25T11:21:35-08:00"}]},"highlight":{"title":["<em>Change</em> to use Bukkit.broadcast()."]}},{"_index":"issues-3","_type":"issue","_id":"10986522","_score":13.751915,"_source":{"title":"Change SessionsController","body":"Make sure that facebook account is set when request.env[\"omniath.auth\"] exists.\n Add also failure action in case if fb authentication will failed.\n","mention_ids":[],"author_id":103073,"num_comments":0,"num_reactions":0,"repo_id":8003014,"network_id":8003014,"public":true,"state":"open","number":94,"labels":["Done"],"created_at":"2013-02-13T23:56:55-08:00","updated_at":"2013-02-25T08:47:28-08:00","milestone_id":266892,"assignee_id":3440055,"language_id":326,"comments":[]},"highlight":{"title":["<em>Change</em> SessionsController"]}}]},"aggregations":{"language_id":{"doc_count_error_upper_bound":0,"sum_other_doc_count":29001,"buckets":[{"key":183,"doc_count":69085},{"key":326,"doc_count":44419},{"key":303,"doc_count":37977},{"key":272,"doc_count":34182},{"key":181,"doc_count":28707},{"key":41,"doc_count":16136},{"key":43,"doc_count":13556},{"key":42,"doc_count":8352},{"key":257,"doc_count":7605},{"key":346,"doc_count":4979}]}}}|,
    )
    @user = create(:user, login: "user")
    @results = Search::Results.new(@hash, page: 1, per_page: 10)
  end

  context "#languages" do
    test "returns an empty array when aggregation is missing" do
      results = ::Search::Results.empty
      assert results.languages.empty?
    end

    test "excludes languages not found in Linguist" do
      aggregations = {
        "language_id" => {
          "doc_count_error_upper_bound" => 0,
          "sum_other_doc_count" => 0,
          "buckets" => [
            { "key" => 388, "doc_count" => 22 },
          ],
        },
      }
      @results.aggregations = aggregations
      assert_equal 1, @results.languages.size
      assert_equal Linguist::Language["VimL"], @results.languages.first.language
    end
  end

  context "#states" do
    test "returns an empty array when aggregation is missing" do
      results = ::Search::Results.empty
      assert results.states.empty?
    end

    test "excludes states not found" do
      aggregations = {
        "state" => {
          "doc_count_error_upper_bound" => 0,
          "sum_other_doc_count" => 0,
          "buckets" => [
            { "key" => "open", "doc_count" => 2 },
          ],
        },
      }
      @results.aggregations = aggregations
      assert_equal 1, @results.states.size
    end
  end

  context "#state_counts" do
    test "returns an empty hash when aggregation is missing" do
      results = ::Search::Results.empty
      assert results.state_counts.empty?
    end

    test "excludes states not found" do
      aggregations = {
        "state" => {
          "doc_count_error_upper_bound" => 0,
          "sum_other_doc_count" => 0,
          "buckets" => [
            { "key" => "open", "doc_count" => 2 },
          ],
        },
      }
      @results.aggregations = aggregations
      assert_equal 2, @results.state_counts["open"]
      assert_nil @results.state_counts["closed"]
    end

    test "includes multiple state counts" do
      aggregations = {
        "state" => {
          "doc_count_error_upper_bound" => 0,
          "sum_other_doc_count" => 0,
          "buckets" => [
            { "key" => "open", "doc_count" => 2 },
            { "key" => "closed", "doc_count" => 3 },
          ],
        },
      }
      @results.aggregations = aggregations
      assert_equal 2, @results.state_counts["open"]
      assert_equal 3, @results.state_counts["closed"]
    end
  end

  context "package types" do
    test "includes package types from both package type and subtype aggregations if FF is on for current_user" do
      # enable search_action_packages feature flag
      @results.search_action_packages_enabled!
      enable_feature_flag(:search_action_packages, @user)
      aggregations = {
        "package_subtype" => {
          "doc_count_error_upper_bound" => 0,
          "sum_other_doc_count" => 0,
          "buckets" => [
            { "key" => "actions", "doc_count" => 1 },
          ]
        },
        "package_type" => {
          "doc_count_error_upper_bound" => 0,
          "sum_other_doc_count" => 0,
          "buckets" => [
            { "key" => "container", "doc_count" => 2 }
          ]
        }
      }
      @results.aggregations = aggregations
      assert_equal 2, @results.package_types.size
      assert_includes @results.package_types.second.term, "actions"
      assert_equal 1, @results.package_types.first.count
      assert_equal 1, @results.package_types.second.count
    end

    test "includes package types from package type aggregation only if FF is off" do
      # disable search_action_packages feature flag
      disable_feature_flag(:search_action_packages)
      aggregations = {
        "package_subtype" => {
          "doc_count_error_upper_bound" => 0,
          "sum_other_doc_count" => 0,
          "buckets" => [
            { "key" => "actions", "doc_count" => 1 },
          ]
        },
        "package_type" => {
          "doc_count_error_upper_bound" => 0,
          "sum_other_doc_count" => 0,
          "buckets" => [
            { "key" => "container", "doc_count" => 2 }
          ]
        }
      }
      @results.aggregations = aggregations
      assert_equal 1, @results.package_types.size
      assert_equal "container", @results.package_types.first.term
      assert_equal 2, @results.package_types.first.count
    end

    test "package types returns only package type if there is no package subtype" do
      aggregations = {
        "package_type" => {
          "doc_count_error_upper_bound" => 0,
          "sum_other_doc_count" => 0,
          "buckets" => [
            { "key" => "container", "doc_count" => 1 }
          ]
        }
      }
      @results.aggregations = aggregations
      assert_equal 1, @results.package_types.size
      assert_includes @results.package_types.first.term, "container"
    end

    test "package types returns only package subtype if there is no package type" do
      @results.search_action_packages_enabled!
      enable_feature_flag(:search_action_packages, @user)
      aggregations = {
        "package_subtype" => {
          "doc_count_error_upper_bound" => 0,
          "sum_other_doc_count" => 0,
          "buckets" => [
            { "key" => "actions", "doc_count" => 1 },
          ]
        },
        "package_type" => {
          "doc_count_error_upper_bound" => 0,
          "sum_other_doc_count" => 0,
          "buckets" => [
            { "key" => "container", "doc_count" => 1 },
          ]
        }
      }
      @results.aggregations = aggregations
      assert_equal 1, @results.package_types.size
      assert_includes @results.package_types.first.term, "action"
    end
  end

  context "#reject!" do
    test "does not tell failbot when index is in sync" do
      @results.reject! { |hit| hit["_id"].to_i < 0 }
      assert_equal 10, @results.results.size
    end

    test "tells failbot when index is out of sync" do
      missing = @results.reject! { |hit| hit["_id"].to_i > 0 }
      assert @results.results.empty?
      assert_equal 10, missing.length
    end
  end

  context "pagination" do
    test "reports total pages available" do
      assert_equal(100, @results.total_pages)

      @hash["hits"]["total"] = 134
      @results = Search::Results.new(@hash, page: 1, per_page: 10)
      assert_equal(14, @results.total_pages)
    end

    test "do not return total pages above max_result_window" do
      @hash["hits"]["total"] = 25_000

      @results = Search::Results.new(@hash, page: 1, per_page: 30, max_offset: 10_000)
      # 30-size: max_offset allows page 334 because it starts in 9990,
      # but it goes til 10020 so it's invalid for max_result_window
      assert_equal(333, @results.total_pages)

      @results = Search::Results.new(@hash, page: 1, per_page: 25, max_offset: 10_000)
      # 25-size: both max_offset and max_result_window allows page 400 because it ends on 10000
      assert_equal(400, @results.total_pages)
    end

    test "reports the previous page number" do
      assert_nil @results.previous_page

      @hash["hits"]["total"] = 134
      @results = Search::Results.new(@hash, page: 3, per_page: 10)
      assert_equal(2, @results.previous_page)
    end

    test "reports the next page number" do
      assert_equal(2, @results.next_page)

      @hash["hits"]["total"] = 134
      @results = Search::Results.new(@hash, page: 7, per_page: 20)
      assert_nil @results.next_page
    end

    test "reports when we are out of bounds" do
      assert !@results.out_of_bounds?

      @hash["hits"]["total"] = 134
      @results = Search::Results.new(@hash, page: 100, per_page: 20)
      assert @results.out_of_bounds?
    end

    test "reports the current offset" do
      assert_equal(0, @results.offset)

      @hash["hits"]["total"] = 134
      @results = Search::Results.new(@hash, page: 3, per_page: 20)
      assert_equal(40, @results.offset)
    end
  end

  context "total" do
    test "it sets the total to zero when there are no hits" do
      @hash["hits"] = []
      @results = Search::Results.new(@hash)
      assert_equal 0, @results.total
      assert_equal :eq, @results.total_relation
    end

    test "it sets the total appropriately for an ES 5 response" do
      @results = Search::Results.new(@hash)
      assert_equal 306345, @results.total
      assert_equal :eq, @results.total_relation
    end

    test "it sets the total appropriately for an ES 8 response" do
      @hash["hits"]["total"] = { "value" => 10000, "relation" => "gte" }
      @results = Search::Results.new(@hash)
      assert_equal 10000, @results.total
      assert_equal :gte, @results.total_relation
    end
  end

  context "timed_out?" do
    test "returns value if the payload includes a timed_out key" do
      @hash["timed_out"] = true
      @results = Search::Results.new(@hash, page: 1, per_page: 10)

      assert @results.timed_out?

      @hash["timed_out"] = false
      @results = Search::Results.new(@hash, page: 1, per_page: 10)

      refute @results.timed_out?
    end
  end

  context "when pagination is disabled" do
    test "page is nil" do
      @results = Search::Results.new(@hash)
      assert_nil @results.page
    end

    test "raises an ArgumentError when pagination methods are called" do
      @results = Search::Results.new(@hash)

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
      @results = Search::Results.empty

      assert_equal 0, @results.total_pages
      assert_nil @results.previous_page
      assert_nil @results.next_page
      assert_equal 0, @results.offset
      assert @results.out_of_bounds?
    end

    test "contains no search results" do
      @results = Search::Results.empty
      assert_empty @results.results
    end

    test "total count is zero" do
      @results = Search::Results.empty
      assert_equal 0, @results.total
    end

    test "can override total count" do
      @results = Search::Results.empty(total: 42)
      assert_empty @results.results
      assert_equal 42, @results.total
    end
  end

  context "#includes_public_repositories?" do
    context "when there are public repos in the topic repo results" do
      test "it returns true" do
        topic = create(:topic, name: "random-topic")
        create(:repository_topic, repository: create(:private_repository), topic: topic)
        create(:repository_topic, repository: create(:repository), topic: topic)
        source = {
          "created_at" => topic.created_at.iso8601,
          "updated_at" => topic.updated_at.iso8601,
          "display_name" => topic.display_name,
          "name" => topic.name,
          "created_by" => topic.created_by,
          "description" => topic.description,
          "short_description" => topic.short_description,
          "released" => topic.released,
          "featured" => topic.featured?,
          "curated" => topic.curated?,
          "repository_count" => topic.applied_repository_topics.on_public_repositories.size,
          "aliases" => topic.alias_names,
          "related" => topic.related_topic_names,
        }
        @hash["hits"]["total"] = 1
        @hash["hits"]["hits"] = [Search::TopicResultView.new(
          "_id" => topic.id.to_s,
          "_source" => source,
          "_model" => topic,
        )]

        results = Search::Results.new(@hash)

        assert_predicate results, :includes_public_repositories?
      end
    end

    context "when there are no public repos in the topic repo results" do
      test "it returns false" do
        topic = create(:topic, name: "random-private-topic")
        create(:repository_topic, repository: create(:private_repository), topic: topic)
        create(:repository_topic, repository: create(:private_repository), topic: topic)
        source = {
          "created_at" => topic.created_at.iso8601,
          "updated_at" => topic.updated_at.iso8601,
          "display_name" => topic.display_name,
          "name" => topic.name,
          "created_by" => topic.created_by,
          "description" => topic.description,
          "short_description" => topic.short_description,
          "released" => topic.released,
          "featured" => topic.featured?,
          "curated" => topic.curated?,
          "repository_count" => topic.applied_repository_topics.on_public_repositories.size,
          "aliases" => topic.alias_names,
          "related" => topic.related_topic_names,
        }
        @hash["hits"]["total"] = 1
        @hash["hits"]["hits"] = [Search::TopicResultView.new(
          "_id" => topic.id.to_s,
          "_source" => source,
          "_model" => topic,
        )]

        results = Search::Results.new(@hash)

        refute_predicate results, :includes_public_repositories?
      end
    end
  end
end

class SearchResultsModelsTest < GitHub::TestCase
  test "#paginated_models returns paginated models" do
    repo1, repo2 = create_pair(:repository)
    fake_es_response = {
      "hits" => {
        "total" => 5,
        "hits" => [
          {
            "_id" => repo1.id.to_s,
            "_model" => repo1,
          },
          {
            "_id" => repo2.id.to_s,
            "_model" => repo2,
          },
        ]
      }
    }
    collection = Search::Results.new(fake_es_response, page: 2, per_page: 3).paginated_models

    assert_equal 5, collection.total_entries
    assert_equal 2, collection.current_page
    assert_equal [repo1, repo2], collection
  end

  context "#parse_error?" do
    test "returns true when the error is a parse failure" do
      results = Search::Results.empty(error_message: "Someone done messed up", error_details: {
        "gh.search.error.name" => "parse-failure"
      })
      assert results.error?
      assert results.parse_error?
    end

    test "returns false when the error is not a parse failure" do
      results = Search::Results.empty(error_message: "boom", error_details: {
        "gh.serch.error.name" => "ExplodedException"
      })
      assert results.error?
      refute results.parse_error?
    end
  end
end
