# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumnTracksTest < GitHub::TestCase
  include IssuesGraphTestHelpers

  fixtures do
    @issue = create(:issue)
    @item = create(:memex_project_item, content: @issue)
    @tracks_field = @item.memex_project.columns.find(&:tracks?).to_field
  end

  setup do
    disable_feature_flag(:memex_table_without_limits)
    disable_feature_flag(:memex_project_without_limits_public_beta)
  end

  context ".elasticsearch_mapping" do
    test "returns the correct nested multi-field configuration" do
      assert_equal @tracks_field.class.elasticsearch_mapping.to_hash,
        {
        dynamic: "strict",
        properties: {
          completed:  { type: "integer" },
          total:  { type: "integer" },
          percent:  { type: "integer" },
        }
      }
    end
  end

  context "#preload_elasticsearch_document_data" do
    test "preloads tracks data", skip_enterprise: true do
      expect_issues_graph_api_call!
      @tracks_field.preload_elasticsearch_document_data([@item])

      mock_issues_graph_client.stubs(:get_issue).raises(RuntimeError.new("unexpected call to issues graph service"))
      @tracks_field.elasticsearch_document(@item)
    end
  end

  context "#elasticsearch_document" do
    test "returns a fragment containing the tracks value", skip_enterprise: true do
      expect_issues_graph_api_call!

      assert_equal(
        @item.completion,
        @tracks_field.elasticsearch_document(@item).to_hash,
      )
    end

    test "returns an empty fragment on enterprise", enterprise_only: true do
      mock_issues_graph_client.expects(:get_issue).never

      expected_completion = {
        total: nil,
        completed: nil,
        percent: nil,
      }

      assert_equal expected_completion, @tracks_field.elasticsearch_document(@item).to_hash, "Expected completion to be empty"
    end
  end

  context "#seed_elasticsearch_document" do
    test "generates a valid tracks value" do
      context = Elastomer::Interfaces::Document::MemexProjectItem::SeedContext.new(require_non_nil_value: true)
      @tracks_field.seed_elasticsearch_document(context).to_hash => {completed:, total:, percent:}

      assert_predicate completed, :integer?
      assert_predicate total, :integer?
      assert_predicate percent, :integer?

      assert_equal(completed <= total, true)
      assert_equal(percent <= 100, true)
    end
  end

  private def expect_issues_graph_api_call!
    enable_feature_flag(:tasklist_block)
    enable_feature_flag(:issue_hierarchy_state)
    disable_feature_flag(:issues_graph_api_concurrent_faraday)
    enable_feature_flag(:optimize_single_memex_hierarchy_prefill)
    enable_feature_flag(:project_hierarchy_columns)
    disable_feature_flag(:issues_graph_api_disable_denormalized_read)

    tracking_parent = IssuesGraph::Proto::Issue.new(
      completion: IssuesGraph::Proto::Completion.new(
        completed: 4,
        total: 10,
        percent: 40
      )
    )

    mock_issues_graph_client
      .expects(:get_issue)
      .returns(as_tracked_issue_result(parent: tracking_parent))
      .once
  end
end
