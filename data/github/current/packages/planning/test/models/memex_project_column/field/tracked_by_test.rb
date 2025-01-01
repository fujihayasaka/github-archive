# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumnTrackedByTest < GitHub::TestCase
  include IssuesGraphTestHelpers

  fixtures do
    @item = create(:memex_project_item)
    @parent_issue = create(:issue, repository: @item.repository)
    @tracked_by_field = @item.memex_project.columns.find(&:tracked_by?).to_field
  end

  setup do
    enable_feature_flag(:tasklist_block)
    enable_feature_flag(:project_hierarchy_columns)
    disable_feature_flag(:issues_graph_api_disable_denormalized_read)
    disable_feature_flag(:memex_increased_issues_graph_timeouts)
    disable_feature_flag(:memex_table_without_limits)
    disable_feature_flag(:memex_project_without_limits_public_beta)
  end

  context ".elasticsearch_mapping" do
    test "returns the correct nested configuration" do
      assert_equal(
        {
          type: "keyword",
          copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS
        },
        @tracked_by_field.class.elasticsearch_mapping.to_hash
      )
    end
  end

  context "#preload_elasticsearch_document_data" do
    test "preloads tracked by data", skip_enterprise: true do
      stub_get_project_tracked_by_items
      @tracked_by_field.preload_elasticsearch_document_data([@item])

      mock_issues_graph_client.stubs(:get_project_tracked_by_items).raises(RuntimeError.new("unexpected call to issues graph service"))
      @tracked_by_field.elasticsearch_document(@item)
    end
  end

  context "#elasticsearch_document" do
    test "returns a fragment containing the tracked by items", skip_enterprise: true do
      stub_get_project_tracked_by_items
      tracked_by_items = @item.tracked_by_items.to_a
      refute_empty tracked_by_items
      expected_result = tracked_by_items.map do |tracked_by|
        "#{tracked_by.owner_display_login}/#{tracked_by.repository_name}##{tracked_by.number}"
      end
      assert_equal(
        expected_result,
        @tracked_by_field.elasticsearch_document(@item)
      )
    end

    test "returns an empty array if item has no tracked by items", skip_enterprise: true do
      stub_get_project_tracked_by_items(with_items: false)
      assert_empty @item.tracked_by_items
      assert_equal([], @tracked_by_field.elasticsearch_document(@item))
    end

    test "returns nil if issue graph client errors", skip_enterprise: true do
      mock_issues_graph_client.expects(:get_project_tracked_by_items).returns(error_result("issues-graph error")).times(2)
      error = assert_raises(MemexProjectItem::ItemPrefillError) { @item.tracked_by_items }
      assert_match /We encountered a problem retrieving the \"Tracked by\" data/, error.message
      assert_nil @tracked_by_field.elasticsearch_document(@item)
    end

    test "returns an empty array on enterprise without calling issues graph", enterprise_only: true do
      mock_issues_graph_client.expects(:get_project_tracked_by_items).never

      assert_equal([], @tracked_by_field.elasticsearch_document(@item))
    end
  end

  context "#seed_elasticsearch_document" do
    test "generates tracked by items with arbitrary repo names and numbers" do
      context = Elastomer::Interfaces::Document::MemexProjectItem::SeedContext.new(require_non_nil_value: true)
      seed_result = @tracked_by_field.seed_elasticsearch_document(context)
      refute_nil seed_result
    end
  end

  def stub_get_project_tracked_by_items(with_items: true)
    tracked_by_item_partial = {
      key: { ownerId: @parent_issue.repository.owner_id, itemId: @parent_issue.id },
      userName: @parent_issue.user.name,
      repoName: @parent_issue.repository.name,
      number: @parent_issue.number,
    }
    mock_issues_graph_client.expects(:get_project_tracked_by_items)
      .with(any_parameters)
      .returns(as_tracked_by_items_result([
        {
          key: { ownerId: @item.repository.owner_id, itemId: @item.content.id },
          trackedByItems: with_items ? [tracked_by_item_partial] : [],
        }
      ]))
  end
end
