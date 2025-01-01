# typed: true
# frozen_string_literal: true

require "test_helper"

class ElasticsearchClientTest < GitHub::TestCase
  include MemexHelpers
  include HydroTestHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    @memex = create(:memex_project)
    @item = create(:memex_project_item, memex_project: @memex)
  end

  setup do
    setup_search
    populate_elasticsearch_index!([@item])
    @index = Elastomer::Indexes::MemexProjectItems.new
    @client = MemexProjectColumn::Indexable::Processor::ElasticsearchClient.new(@index)
  end

  teardown do
    teardown_search
  end

  context "#delete" do
    test "deletes item when proper params are provided", es_8_only: true do
      params = Elastomer::Interfaces::Api::Delete::Request::Params.new(
        id: @item.id,
        routing: @memex.id,
      )
      response = @client.delete(params)
      assert_equal Elastomer::Interfaces::Api::Delete::Response::Result::Deleted, response.result
    end

    test "raises an error when routing value is not provided", es_8_only: true do
      params = Elastomer::Interfaces::Api::Delete::Request::Params.new(
        id: @item.id,
      )
      assert_raises(ArgumentError) do
        @client.delete(params)
      end
    end
  end

  context "#search" do
    test "executes `query` and returns expected response", es_8_only: true do
      query = { term: { database_id: @item.id } }
      body = Elastomer::Interfaces::Api::Search::Request::Body.new(query:)
      response = @client.search(body)
      assert_equal 1, response.hits.total.value
    end

    test "executes `q` and returns expected response", es_8_only: true do
      q = "database_id:#{@item.id}"
      body = Elastomer::Interfaces::Api::Search::Request::Body.new(q:)
      response = @client.search(body)
      assert_equal 1, response.hits.total.value
    end

    test "requires either `q` or `query` in the body", es_8_only: true do
      assert_raises ArgumentError do
        @client.search(Elastomer::Interfaces::Api::Search::Request::Body.new({}))
      end
    end
  end

  context "#update" do
    test "updates item when proper params are provided", es_8_only: true do
      body = Elastomer::Interfaces::Api::Update::Request::Body.new(
        doc: { updated_at: Time.now.utc.iso8601 },
      )
      params = Elastomer::Interfaces::Api::Update::Request::Params.new(
        id: @item.id,
        routing: @memex.id,
      )
      response = @client.update(body, params)
      assert_equal Elastomer::Interfaces::Api::Update::Response::Result::Updated, response.result
    end

    test "raises an error when routing value is not provided", es_8_only: true do
      body = Elastomer::Interfaces::Api::Update::Request::Body.new(
        doc: { updated_at: Time.now.utc.iso8601 },
      )
      params = Elastomer::Interfaces::Api::Update::Request::Params.new(
        id: @item.id,
      )
      assert_raises(ArgumentError) do
        @client.update(body, params)
      end
    end

    test "defaults to refresh: wait_for when refresh value not provided in params", es_8_only: true do
      body = Elastomer::Interfaces::Api::Update::Request::Body.new(
        doc: {},
      )
      params = Elastomer::Interfaces::Api::Update::Request::Params.new(
        id: @item.id,
        routing: @memex.id,
      )
      response = @index.docs.update(body.to_hash, params.to_hash)

      @index.docs.expects(:update)
        .with(anything, has_entries(refresh: "wait_for"))
        .returns(response)

      @client.update(body, params)
    end

    test "defaults to retry_on_conflict: RETRY_ON_CONFLICT when retry_on_conflict value not provided in params", es_8_only: true do
      body = Elastomer::Interfaces::Api::Update::Request::Body.new(
        doc: {},
      )
      params = Elastomer::Interfaces::Api::Update::Request::Params.new(
        id: @item.id,
        routing: @memex.id,
      )
      response = @index.docs.update(body.to_hash, params.to_hash)

      @index.docs.expects(:update)
        .with(anything, has_entries(retry_on_conflict: MemexProjectColumn::Indexable::Processor::ElasticsearchClient::RETRY_ON_CONFLICT))
        .returns(response)

      @client.update(body, params)
    end
  end

  context "#update_by_query" do
    test "updates item", es_8_only: true do
      query = { term: { database_id: @item.id } }
      script = Elastomer::Interfaces::Api::Request::Script.new(
        { source: "ctx._source.updated_at = params.updated_at", params: { updated_at: Time.now.utc.iso8601 } },
      )
      body = Elastomer::Interfaces::Api::UpdateByQuery::Request::Body.new(query:, script:)
      response = @client.update_by_query(body)
      assert_equal 1, response.updated
    end

    test "defaults to conflicts: proceed when conflicts value not provided in params", es_8_only: true do
      query = { term: { database_id: @item.id } }
      script = Elastomer::Interfaces::Api::Request::Script.new(
        { source: "ctx._source.updated_at = params.updated_at", params: { updated_at: Time.now.utc.iso8601 } },
      )
      body = Elastomer::Interfaces::Api::UpdateByQuery::Request::Body.new(query:, script:)
      response = @index.docs.update_by_query(body.to_hash)

      @index.docs.expects(:update_by_query)
        .with(anything, has_entries(conflicts: "proceed"))
        .returns(response)

      @client.update_by_query(body)
    end

    test "defaults to refresh: true when refresh value not provided in params", es_8_only: true do
      query = { term: { database_id: @item.id } }
      script = Elastomer::Interfaces::Api::Request::Script.new(
        { source: "ctx._source.updated_at = params.updated_at", params: { updated_at: Time.now.utc.iso8601 } },
      )
      body = Elastomer::Interfaces::Api::UpdateByQuery::Request::Body.new(query:, script:)
      response = @index.docs.update_by_query(body.to_hash)

      @index.docs.expects(:update_by_query)
        .with(anything, has_entries(refresh: "true"))
        .returns(response)

      @client.update_by_query(body)
    end
  end

  context "#bulk" do
    test "performs multiple operations in a single request", es_8_only: true do
      @another_item = create(:memex_project_item, memex_project: @memex)
      populate_elasticsearch_index!([@item, @another_item])
      params = Elastomer::Interfaces::Api::Bulk::Request::Params.new(routing: @memex.id)
      updated_at = (Time.now + 1.day).utc.iso8601
      response = @client.bulk(params) do |b|
        b.delete(id: @item.id)
        b.update({ doc: { updated_at: } }, { id: @another_item.id })
      end
      expected_results = [{ "deleted" => 200 }, { "updated" => 200 }]
      mapped_results = response.to_hash[:items].map do |i|
        item = i.values.first
        { item[:result] => item[:status] }
      end
      assert_same_elements(expected_results, mapped_results)
    end

    test "defaults to refresh: wait_for when refresh value not provided in params", es_8_only: true do
      @index.docs.expects(:bulk)
        .with({ refresh: "wait_for" }, anything)
        .returns({ "took" => 300,
          "errors" => false,
          "items" => [{ "delete" =>
            { "_index" => "memex-project-items-test",
              "_id" => @item.id.to_s,
              "_version" => 2,
              "result" => "deleted",
              "_shards" => { "total" => 1, "successful" => 1, "failed" => 0 },
              "_seq_no" => 115,
              "_primary_term" => 1,
              "status" => 200
            },
          }],
        })

      @client.bulk { |b| b.delete(id: 2) }
    end

    test "supports updates across multiple project ids", es_8_only: true do
      @other_memex = create(:memex_project)
      @another_item = create(:memex_project_item, memex_project: @other_memex)
      populate_elasticsearch_index!([@item, @another_item])
      updated_at = (Time.now + 1.day).utc.iso8601
      response = @client.bulk do |b|
        b.delete({ id: @item.id, routing: @memex.id })
        b.update({ doc: { updated_at: } }, { id: @another_item.id, routing: @other_memex.id })
      end
      expected_results = [{ "deleted" => 200 }, { "updated" => 200 }]
      mapped_results = response.to_hash[:items].map do |i|
        item = i.values.first
        { item[:result] => item[:status] }
      end
      assert_same_elements(expected_results, mapped_results)
    end

    test "returns an error when :routing is not provided in the top or nested params", es_8_only: true do
      updated_at = (Time.now + 1.day).utc.iso8601
      response = @client.bulk do |b|
        b.update({ doc: { updated_at: } }, { id: @item.id })
        b.delete({ id: @item.id })
      end.to_hash
      assert(response[:errors])
      error_msgs = response[:items].map { |i| i.values.first[:error][:type] }
      assert error_msgs.all? { |msg| msg == "routing_missing_exception" }
    end

    test "recognizes and records noop operations", es_8_only: true do
      updated_at = (Time.now - 2.days).utc.iso8601
      item_params = { id: @item.id, routing: @memex.id }
      response = @client.bulk do |b|
        b.update({ doc: { updated_at: } }, item_params)
        b.update({ doc: { updated_at: } }, item_params)
      end.to_hash
      refute(response[:errors]) # not an error
      assert_equal(200, response[:items].first.values.first[:status])
      assert_match(
        Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Noop.serialize,
        response[:items].last.values.first[:result]
      )
    end

    test "omits results with missing document errors", es_8_only: true do
      params = Elastomer::Interfaces::Api::Bulk::Request::Params.new(routing: @memex.id)
      response = @client.bulk(params) do |b|
        b.delete({ id: @item.id })
        # attempt to update after deleting
        b.update({ doc: { updated_at: Time.now.utc.iso8601 } }, { id: @item.id })
      end.to_hash
      refute(response[:errors]) # not considered an error
      assert_equal(1, response[:items].size) # result omitted
    end
  end
end
