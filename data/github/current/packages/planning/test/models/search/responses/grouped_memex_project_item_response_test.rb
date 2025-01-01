# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchResponsesGroupedMemexProjectItemResponseTest < GitHub::TestCase
  fixtures do
    @project = create(:memex_project)
    @archived_item = create(:memex_project_item, :archived, memex_project: @project)
    @unarchived_item = create(:memex_project_item, archived_at: nil, memex_project: @project)
    @all_items = [@archived_item, @unarchived_item]
  end

  context "#grouped?" do
    test "returns true when initialized with an empty list of primary groups" do
      response = Search::Responses::GroupedMemexProjectItemResponse.new(
        basic_elasticsearch_response,
        { primary_groups: MemexProjectColumn::Groupable::PaginatedGroups.new }
      )

      assert_predicate response, :grouped?
    end

    test "also returns true when initialized with a non-empty list of primary groups" do
      response = Search::Responses::GroupedMemexProjectItemResponse.new(
        basic_elasticsearch_response,
        {
          primary_groups: MemexProjectColumn::Groupable::PaginatedGroups.new(
            nodes: [
              MemexProjectColumn::Groupable::Group.new(group_by_key: 1, grouped_items_page_size: 1)
            ]
          )
        }
      )

      assert_predicate response, :grouped?
    end

    test "returns true when initialized with a nil list of primary groups" do
      response = Search::Responses::GroupedMemexProjectItemResponse.new(
        basic_elasticsearch_response,
        { primary_groups: nil }
      )
      assert_predicate response, :grouped?
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
