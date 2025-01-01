# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchResponsesMemexProjectItemResponseTest < GitHub::TestCase
  fixtures do
    @project = create(:memex_project)
    @archived_item = create(:memex_project_item, :archived, memex_project: @project)
    @unarchived_item = create(:memex_project_item, archived_at: nil, memex_project: @project)
    @all_items = [@archived_item, @unarchived_item]
  end

  setup do
    @response_with_all_items = Search::Responses::MemexProjectItemResponse.new(
      {
        took: "1",
        hits: {
          total: {
            value: @all_items.length,
            relation: "eq",
          },
          hits: @all_items.map { |item| { _source: { database_id: item.id } } }
        }
      }.deep_stringify_keys,
      { per_page: 5 }
    )
  end

  context "#models" do
    test "returns MemexProjectItem models in the same order as the Elasticsearch response" do
      assert_equal [@archived_item, @unarchived_item], @response_with_all_items.models
    end
  end

  context "#grouped?" do
    test "returns false when initialized without a list of primary groups" do
      refute_predicate @response_with_all_items, :grouped?
    end
  end

  private def basic_elasticsearch_response
    {
      "took" => "1",
      "hits" => {
        "total" => {
          "value" => 0,
          "relation" => "eq",
        },
        "hits" => []
      }
    }
  end
end
