# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchMemexProjectItemReconcilerTest < GitHub::TestCase
  include MemexHelpers
  include IssuesGraphTestHelpers
  include DogstatsTestHelpers
  include GitHub::LoggerHelper

  fixtures do
    @beginning_of_week = Time.zone.now.beginning_of_week.freeze
    @now = Time.zone.now.freeze
    @user = create(:verified_user)

    @memex = create(:memex_project)
    @items = Timecop.freeze(@beginning_of_week) do
      issue_and_pull_items = (create_list(:issue, 14) + create_list(:pull_request, 6, :disable_disk_access)).map do |content|
        create(:memex_project_item, content: content, memex_project: @memex)
      end
      draft_items = 6.times.map { |n| @memex.build_draft_issue(creator: @user, title: "Idea ##{n}").tap(&:save!) }
      issue_and_pull_items + draft_items
    end
  end

  setup do
    GitHub.flipper[:memex_project_consistency_score_ignore_inconsistent_fields].disable

    setup_search
    @index = Elastomer::Indexes::MemexProjectItems.new
    @document_type = Elastomer::Adapters::MemexProjectItem.document_type
  end

  teardown_once do
    teardown_search
  end

  private def assignees_present_query
    {
      query: {
        bool: {
          must: {
            nested: {
              path: "field_values",
              query: {
                exists: {
                  field: "field_values.#{MemexProjectColumn::Assignees.value_name}.login"
                }
              }
            }
          }
        }
      }
    }
  end

  private def match_all_query
    { query: { match_all: {} } }
  end

  private def reconcile!(items = @items, read_only: false, live_updates: true)
    Search::MemexProjectItemReconciler.new(@memex.id, read_only:, live_updates:).reconcile!(items, wait_for_refresh: true)
  end

  private def clear!(gte_id = nil)
    Search::MemexProjectItemReconciler.new(@memex.id).clear!(
      greater_than_or_equal_to_item_id: gte_id,
      wait_for_refresh: true
    )
  end

  context "#reconcile!" do
    test "fails if items come from different projects" do
      mixed_items = @items + create_list(:memex_project_item, 3)
      assert mixed_items.map(&:memex_project_id).uniq.length > 1

      error = assert_raises(ArgumentError) do
        reconcile!(mixed_items)
      end

      assert_equal "All items must belong to the project this reconciler was initialized with.", error.message
    end

    test "fails if items are not ordered by increasing ID" do
      error = assert_raises(ArgumentError) do
        reconcile!(@items.sort_by { |i| -i.id })
      end

      assert_equal "Items must be ordered by increasing id.", error.message
    end

    test "ensures that datetime fields are formatted as iso8601" do
      reconcile!(@items)
      assert_equal @items.length, @index.count(match_all_query, routing: @memex.id, type: @document_type)
      assert_empty @index.search(assignees_present_query, routing: @memex.id, type: @document_type, size: @items.length).dig("hits", "hits")

      item = @items.first
      new_created_at = item.created_at.in_time_zone("Alaska")
      item.stubs(:created_at).returns(new_created_at)
      assert item.set_column_value(@memex.columns.find(&:assignees?), [item.repository&.owner || @user], @user)

      GitHub.logger.expects(:info).with(
        Search::MemexProjectItemReconciler::LOG_MESSAGE,
        has_entries({
          "elasticsearch.document.id" => item.id.to_s,
          "gh.memex.project_item_reconciler.action" => "update",
          "gh.memex.project_item_reconciler.diff" => is_a(Array)
        })
      )

      reconcile!([item])

      updated_item = @index.search(assignees_present_query, routing: @memex.id, type: @document_type, size: @items.length).dig("hits", "hits").first
      created_at = updated_item.dig("_source", "created_at")
      assert_predicate(Time.parse(created_at), :utc?)
    end

    test "adds missing documents to Elasticsearch" do
      refute_empty @items
      assert_equal 0, @index.count(match_all_query, routing: @memex.id, type: @document_type)

      @items.each do |item|
        GitHub.logger.expects(:info).with(
          Search::MemexProjectItemReconciler::LOG_MESSAGE,
          has_entries({
            "elasticsearch.document.id" => item.id.to_s,
            "gh.memex.project_item_reconciler.action" => "add",
            "gh.memex.project_item_reconciler.counted" => true,
          })
        )
      end

      result = reconcile!(@items)

      assert_equal @items.length, result.added
      assert_equal @items.length, result.total
      assert_equal 0, result.updated + result.removed

      assert_equal @items.length, @index.count(match_all_query, routing: @memex.id, type: @document_type)
      assert_dogstats_increment(@items.length, Search::MemexProjectItemReconciler::METRIC_NAME, tags: ["action:add"])
    end

    test "updates existing documents in Elasticsearch" do
      reconcile!(@items)
      assert_equal @items.length, @index.count(match_all_query, routing: @memex.id, type: @document_type)
      assert_empty @index.search(assignees_present_query, routing: @memex.id, type: @document_type, size: @items.length).dig("hits", "hits")

      items_to_update = @items.each_with_index.find_all { |_, index| index.even? }.map(&:first)
      refute_empty items_to_update

      items_to_update.each do |item|
        # Make a change to each item that is only tracked in an external service, and so can only be detected by
        # diffing the generated Elasticsearch document (which contains data fetched from external services).
        # This ensures that the code actually performs such a diff.
        assert item.set_column_value(@memex.columns.find(&:assignees?), [item.repository&.owner || @user], @user)
      end

      items_to_update.each do |item|
        GitHub.logger.expects(:info).with(
          Search::MemexProjectItemReconciler::LOG_MESSAGE,
          has_entries({
            "elasticsearch.document.id" => item.id.to_s,
            "gh.memex.project_item_reconciler.action" => "update",
            "gh.memex.project_item_reconciler.diff" => is_a(Array),
            "gh.memex.project_item_reconciler.counted" => true,
          })
        )
      end

      fake_page_size = 3
      assert @items.length > fake_page_size
      Search::MemexProjectItemReconciler.stub_const(:DEFAULT_PAGE_SIZE, fake_page_size) do
        reconcile!(@items)
      end

      updated_items = @index.search(assignees_present_query, routing: @memex.id, type: @document_type, size: @items.length).dig("hits", "hits")

      assert_same_elements items_to_update.map { |m| m.id.to_s }, updated_items.map { |d| d["_id"] }
      assert_dogstats_increment(items_to_update.length, Search::MemexProjectItemReconciler::METRIC_NAME, tags: ["action:update"])
    end

    test "removes stale documents within the ID range of the given items from Elasticsearch" do
      reconcile!(@items)
      assert_equal @items.length, @index.count(match_all_query, routing: @memex.id, type: @document_type)

      items_to_keep = @items.each_with_index.find_all { |_, index| index != 0 && index.even? }.map(&:first)
      refute_empty items_to_keep

      minimum_id_to_keep = items_to_keep.map(&:id).min
      maximum_id_to_keep = items_to_keep.map(&:id).max

      # Confirm that there is at least one item on either side of our target ID range.
      assert @items.map(&:id).min < minimum_id_to_keep
      assert @items.map(&:id).max > maximum_id_to_keep

      GitHub.logger.expects(:info).at_most(@items.length - items_to_keep.length).with(
        Search::MemexProjectItemReconciler::LOG_MESSAGE,
        has_entries({
          "gh.memex.project_item_reconciler.action" => "delete",
          "gh.memex.project_item_reconciler.counted" => true,
        })
      )

      result = reconcile!(items_to_keep)

      remaining_document_ids = @index.search(match_all_query, routing: @memex.id, type: @document_type, size: @items.length).dig("hits", "hits").map { |d| d["_id"].to_i }
      document_ids_outside_range = (remaining_document_ids - items_to_keep.map(&:id))

      # Make sure we've kept all the document we were supposed to keep.
      assert_equal items_to_keep.length, (items_to_keep.map(&:id) & remaining_document_ids).length

      # Make sure we've removed documents.
      assert remaining_document_ids.length < @items.length

      # Make sure that anything left in Elasticsearch is outside the range of IDs we were supposed to remove.
      assert document_ids_outside_range.all? { |id| id < minimum_id_to_keep || id > maximum_id_to_keep }

      # Make sure we logged a delete metric.
      assert_dogstats_increment(:at_least_one, Search::MemexProjectItemReconciler::METRIC_NAME, tags: ["action:delete"])

      # Make sure the result object reflects the correct numbers.
      num_deleted_documents = @items.length - document_ids_outside_range.length - items_to_keep.length
      assert_equal num_deleted_documents, result.removed
      assert_equal num_deleted_documents, result.total
      assert_equal 0, result.added + result.updated
    end

    test "completes successfully when the operation is a no-op" do
      reconcile!(@items)
      assert_equal @items.length, @index.count(match_all_query, routing: @memex.id, type: @document_type)

      # Re-apply the operation without any changes.
      assert_nothing_raised do
        result = reconcile!(@items)
        assert_equal 0, result.total
      end

      assert_equal @items.length, @index.count(match_all_query, routing: @memex.id, type: @document_type)
    end

    test "logs incomplete documents at end of reconcilation process" do
      exception = StandardError.new("boom")
      @items.first.expects(:denormalized_title_value).raises(exception)
      expected_log_attributes = {
        "gh.memex.project_item_reconciler.action" => "incomplete",
        "elasticsearch.document.id" => @items.first.id,
      }
      assert_nothing_raised do
        assert_logged(**expected_log_attributes) do
          reconcile!(@items)
        end
      end

      assert_dogstats_count 1, "memex.project_item_reconciler.incomplete"
    end

    test "logs critical when an unexpected error is thrown but otherwise continues reconciliation" do
      exception = StandardError.new("boom")
      @items.first.expects(:denormalized_title_value).raises(exception)
      expected_log_attributes = {
        "gh.memex.project_item_reconciler.action" => "build_document",
        "exception.class" => exception.class.name,
        "exception.message" => exception.message,
        "gh.memex.project_item_reconciler.critical_error" => true,
      }
      assert_nothing_raised do
        assert_logged(**expected_log_attributes) do
          result = reconcile!(@items)
          # Assert that the total includes the incomplete doc so that it's evaluated as part of consistency score
          assert_equal @items.length - 1, result.total
        end
      end

      assert_dogstats_increment(
        1,
        "#{Search::MemexProjectItemReconciler::METRIC_NAME}.skip",
        tags: ["critical:true", "exception:#{exception.class.name}"]
      )
    end

    test "logs non-critical when an expected error is thrown" do
      exception = Elastomer::Adapters::MemexProjectItem::CanonicalDataMissingError.new("boom")
      @items.first.expects(:denormalized_title_value).raises(exception)
      expected_log_attributes = {
        "gh.memex.project_item_reconciler.action" => "build_document",
        "exception.class" => exception.class.name,
        "exception.message" => exception.message,
        "gh.memex.project_item_reconciler.critical_error" => false,
      }
      assert_nothing_raised do
        assert_logged(**expected_log_attributes) do
          result = reconcile!(@items)
          assert_equal @items.length - 1, result.total
        end
      end

      assert_dogstats_increment(
        1,
        "#{Search::MemexProjectItemReconciler::METRIC_NAME}.skip",
        tags: ["critical:false", "exception:#{exception.class.name}"]
      )
    end

    test "reports errors from the Elasticsearch bulk index API" do
      assert_equal 0, @index.count_all(match_all_query, type: @document_type)

      Elastomer::Index.any_instance.stubs(:bulk).returns({
        "errors" => true,
        "items" => [
          { "index" => { "_id" => @items[0].id.to_s, "status" => 400, "error" => "first error" } },
          { "index" => { "_id" => @items[1].id.to_s, "status" => 400, "error" => "second error" } },
        ]
      })

      # Make sure we report the error to Splunk.
      GitHub.logger.expects(:info).with(
        "Bulk index error",
        has_entries({
          "gh.memex.project_item_reconciler.error" => anything,
        })
      )

      result = reconcile!(@items)

      # Make sure we reported the errors to Sentry also.
      ["first error", "second error"].each do |message|
        assert_match message, Failbot.exception_message_from_hash(Failbot.reports.last)
      end

      # Make sure we counted the number of errors.
      assert_dogstats_count_value(2, "memex.project_item_reconciler.bulk_errors", tags: ["function:reconcile"])

      # Make sure we processed as many items as we could.
      assert_equal @items.length - 2, result.added
      assert_equal @items.length - 2, result.total
      assert_equal 0, result.updated + result.removed
    end

    test "does not report errors from the Elasticsearch bulk index API if the error key is false" do
      assert_equal 0, @index.count_all(match_all_query, type: @document_type)

      Elastomer::Index.any_instance.stubs(:bulk).returns({
        "errors" => false,
        "items" => [
          { "index" => { "_id" => @items[0].id.to_s, "status" => 200 } },
          { "index" => { "_id" => @items[1].id.to_s, "status" => 200 } },
        ]
      })

      refute_logged("Body" => "Bulk index error") do
        result = reconcile!(@items)

        # Make sure that the operation wasn't a no-op (so there was an opportunity to report errors, but that we
        # still did not do so).
        assert result.total > 0
      end
    end

    test "includes fields known to be inconsistent towards the count of updated documents in Elasticsearch" do
      reconcile!(@items)
      assert_equal @items.length, @index.count(match_all_query, routing: @memex.id, type: @document_type)

      item_to_update = @items.first
      refute_nil item_to_update

      # Make a change to an item that is only tracked in an external service, and so can only be detected by
      # diffing the generated Elasticsearch document (which contains data fetched from external services).
      # This ensures that the code actually performs such a diff.
      item_to_update.update_column(:updated_at, item_to_update.updated_at + 2.seconds)

      result = reconcile!(@items)
      updated_document = @index.docs.get(id: item_to_update.id, routing: @memex.id, type: @document_type)

      assert_equal item_to_update.id.to_s, updated_document["_id"]
      assert_equal item_to_update.updated_at, Time.parse(updated_document["_source"]["updated_at"])
      assert_dogstats_increment(1, Search::MemexProjectItemReconciler::METRIC_NAME, tags: ["action:update"])

      assert_equal 1, result.updated
    end

    test "logs changes for inconsistent documents when memex_project_consistency_score_ignore_inconsistent_fields is disabled" do
      reconcile!(@items)
      assert_equal @items.length, @index.count(match_all_query, routing: @memex.id, type: @document_type)

      item_to_update = @items.first
      refute_nil item_to_update

      item_to_update.update_column(:updated_at, item_to_update.updated_at + 2.seconds)

      GitHub.logger.expects(:info).with(
        Search::MemexProjectItemReconciler::LOG_MESSAGE,
        has_entries({
          "elasticsearch.document.id" => item_to_update.id.to_s,
          "gh.memex.project_item_reconciler.action" => "update",
          "gh.memex.project_item_reconciler.diff" => is_a(Array),
          "gh.memex.project_item_reconciler.counted" => true,
        })
      )

      result = reconcile!(@items)
      assert_equal 1, result.updated
    end

    test "ignores fields known to be inconsistent towards the count of updated documents in Elasticsearch" do
      GitHub.flipper[:memex_project_consistency_score_ignore_inconsistent_fields].enable

      reconcile!(@items)
      assert_equal @items.length, @index.count(match_all_query, routing: @memex.id, type: @document_type)

      item_to_update = @items.first
      refute_nil item_to_update

      # Make a change to and item that is only tracked in an external service, and so can only be detected by
      # diffing the generated Elasticsearch document (which contains data fetched from external services).
      # This ensures that the code actually performs such a diff.
      item_to_update.update_column(:updated_at, item_to_update.updated_at + 5.days)

      result = reconcile!(@items)
      updated_document = @index.docs.get(id: item_to_update.id, routing: @memex.id, type: @document_type)

      assert_equal item_to_update.id.to_s, updated_document["_id"]
      assert_equal item_to_update.updated_at, Time.parse(updated_document["_source"]["updated_at"])
      assert_dogstats_increment(Search::MemexProjectItemReconciler::METRIC_NAME, tags: ["action:update"])

      assert_equal 0, result.updated
    end

    test "logs changes for inconsistent documents when memex_project_consistency_score_ignore_inconsistent_fields is enabled" do
      GitHub.flipper[:memex_project_consistency_score_ignore_inconsistent_fields].enable

      reconcile!(@items)
      assert_equal @items.length, @index.count(match_all_query, routing: @memex.id, type: @document_type)

      item_to_update = @items.first
      refute_nil item_to_update

      item_to_update.update_column(:updated_at, item_to_update.updated_at + 2.seconds)

      GitHub.logger.expects(:info).with(
        Search::MemexProjectItemReconciler::LOG_MESSAGE,
        has_entries({
          "elasticsearch.document.id" => item_to_update.id.to_s,
          "gh.memex.project_item_reconciler.action" => "update",
          "gh.memex.project_item_reconciler.diff" => is_a(Array),
          "gh.memex.project_item_reconciler.counted" => false,
        })
      )

      result = reconcile!(@items)
      assert_equal 0, result.updated
    end

    test "traces its execution" do
      reconcile!(@items)
      refute_nil find_span_by(name: "search/memex_project_item_reconciler#reconcile!")
    end

    unless TestEnv.test_all_features?
      # We don't run this test in "all features" builds because it makes our query count assertion inconsistent.
      test "avoids egregious N+1s" do
        # Choose an intentionally loose bound on the number of acceptable queries.
        # This makes this test more robust to small/incidental changes to the query count,
        # but should hopefully trip if performance degrades significantly.
        #
        # We should have a conversation each time we increase this number.
        acceptable_number_of_queries = 21

        # Make sure we have enough items for the test to be valid, and that number
        # we've chosen for acceptable queries is a reasonable bound on inefficency.
        assert @items.length > 10 && acceptable_number_of_queries < @items.length

        assert_max_query_count(acceptable_number_of_queries, ignore_feature_flags: true, backtrace_lines: 10) { reconcile!(@items) }
      end

      test "avoids duplicate requests to the issues-graph service" do
        client = stub_issues_graph_client!

        # Allow one request that loads data for the "Tracks" field.
        client.expects(:get_project_item_completions).at_most_once.returns(as_completions_result([]))

        # Allow one request that loads data for the "Tracked-by" field.
        client.expects(:get_project_tracked_by_items).at_most_once.returns(as_tracked_by_items_result([]))

        # If either of the above requests happens more than once, then the line below will raise an error.
        # It will also raise an error if any other method is called on the stubbed issues graph client.
        reconcile!(@items)
      end
    end

    test "calls the broadcaster if reconciliation succeeds" do
      MemexProjectColumn::Indexable::Processor::LiveUpdateBroadcaster.expects(:call).once
      reconcile!(@items)
    end

    test "does not broadcast live updates when reconciliation succeeds if disabled" do
      MemexProjectColumn::Indexable::Processor::LiveUpdateBroadcaster.expects(:call).never
      reconcile!(@items, live_updates: false)
    end

    test "does not call the broadcaster if reconciliation fails" do
      mixed_items = @items + create_list(:memex_project_item, 3)
      assert mixed_items.map(&:memex_project_id).uniq.length > 1 # this should make reconciliation fail

      MemexProjectColumn::Indexable::Processor::LiveUpdateBroadcaster.expects(:call).never
      assert_raises(ArgumentError) { reconcile!(mixed_items) }
    end

    test "does not preload elasticsearch document data for columns excluded from index" do
      fields = MemexProjectColumn::FieldDependency::FIELD_CLASS_REGISTRY.collect(&:constantize)
      excluded_fields_from_index = fields.select(&:exclude_from_index?)

      excluded_fields_from_index.each do |field|
        field.any_instance.expects(:preload_elasticsearch_document_data).never
      end

      reconcile!(@items)
    end
  end

  context "#clear!" do
    test "removes all item documents for a particular project from Elasticsearch" do
      result = reconcile!(@items)
      assert_equal @items.length, @index.count(match_all_query, routing: @memex.id, type: @document_type)

      result = clear!

      assert_equal @items.length, result.removed
      assert_equal @items.length, result.total
      assert_equal 0, result.added + result.updated

      assert_equal 0, @index.count(match_all_query, routing: @memex.id, type: @document_type)
    end

    test "can remove all items above a certain ID value for a particular project from Elasticsearch" do
      reconcile!(@items)
      assert_equal @items.length, @index.count(match_all_query, routing: @memex.id, type: @document_type)

      min_item_id = @items[2].id
      remaining_ids = MemexProjectItem.where(memex_project_id: @memex.id).where("id < ?", min_item_id).pluck(:id)
      assert_equal 2, remaining_ids.length

      result = clear!(min_item_id)

      assert_equal @items.length - 2, result.removed
      assert_equal @items.length - 2, result.total
      assert_equal 0, result.added + result.updated

      remaining_items = @index.search(match_all_query, routing: @memex.id, type: @document_type, size: @items.length).dig("hits", "hits")
      assert_same_elements remaining_ids, remaining_items.map { |d| d["_id"].to_i }
    end

    test "does not touch any other project's item documents" do
      other_project = create(:memex_project)
      other_items = create_list(:memex_project_item, 5, memex_project: other_project)

      reconcile!(@items)
      Search::MemexProjectItemReconciler.new(other_project.id).reconcile!(other_items, wait_for_refresh: true)
      assert_equal @items.length + other_items.length, @index.count(match_all_query, routing: @memex.id, type: @document_type)

      clear!

      remaining_items = @index.search(match_all_query, routing: other_project.id, type: @document_type, size: @items.length).dig("hits", "hits")
      assert_equal other_items.length, remaining_items.length
      assert remaining_items.all? { |d| d.dig("_source", "memex_project_id") == other_project.id }
    end

    test "reports errors from the Elasticsearch delete by query API" do
      ElastomerClient::Client.any_instance.stubs(:delete_by_query).returns({
        "deleted" => 0,
        "failures" => [
          { "error" => "first error" },
          { "error" => "second error" },
        ]
      })

      # Make sure we report the error to Splunk.
      GitHub.logger.expects(:info).with(
        "Delete by query error",
        has_entries({
          "gh.memex.project_item_reconciler.error" => anything,
        })
      )

      result = clear!

      # Make sure we reported the errors to Sentry also.
      ["first error", "second error"].each do |message|
        assert_match message, Failbot.exception_message_from_hash(Failbot.reports.last)
      end

      # Make sure we counted the number of errors.
      assert_dogstats_count_value(2, "memex.project_item_reconciler.bulk_errors", tags: ["function:clear"])


      # Make sure we completed the operation successfully.
      assert_equal 0, result.removed
    end

    test "does not report errors from the Elasticsearch delete by query API when failures array is empty" do
      ElastomerClient::Client.any_instance.stubs(:delete_by_query).returns({
        "failures" => []
      })

      refute_logged("Body" => "Delete by query error") do
        result = clear!

        # Make sure we completed the operation successfully.
        assert_equal 0, result.removed
      end
    end

    test "traces its execution" do
      reconcile!(@items)
      clear!
      refute_nil find_span_by(name: "search/memex_project_item_reconciler#clear!")
    end

    test "does not write if read_only option is passed in" do
      ElastomerClient::Client::Bulk.any_instance.expects(:index).never
      ElastomerClient::Client::Bulk.any_instance.expects(:delete).never
      reconcile!(@items, read_only: true)
    end
  end
end
