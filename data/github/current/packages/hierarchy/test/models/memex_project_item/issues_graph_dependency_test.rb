# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectItem::IssuesGraphDependencyTest < GitHub::TestCase
  include GitHub::LoggerHelper

  fixtures do
    @repository = create(:repository)
    GitHub.flipper[:tasklist_block].enable(@repository.owner)
    @issue = create(:issue, repository: @repository)
    @pull_request = create(:pull_request, :disable_disk_access, repository: @repository)
    @memex = create(:memex_project)
    @item = create(:memex_project_item, memex_project: @memex, content: @issue)
    @item_to_destroy = create(:memex_project_item)
  end

  setup do
    @issue_graph_client = mock("issue_graph_client")
    GitHub.stubs(:issues_graph_api_client).returns(@issue_graph_client)
    GitHub.flipper[:issues_graph_api].enable
    GitHub.flipper[:project_timeline_events].enable
  end

  context "delegation" do
    test "delegates #to_hierarchy_model_key to the content" do
      assert_equal @item.to_hierarchy_model_key, @issue.to_hierarchy_model_key,
        "expected the item to delegate the #to_hierarchy_model_key method to the underlying content"
    end

    test "delegates #to_hierarchy_model to the content" do
      assert_equal @item.to_hierarchy_model, @issue.to_hierarchy_model,
        "expected the item to delegate the #to_hierarchy_model method to the underlying content"
    end

    test "delegation raises for models that we don't represent on the graph" do
      assert_raises NotImplementedError do
        DraftIssue.new.to_hierarchy_model
      end

      assert_raises NotImplementedError do
        DraftIssue.new.to_hierarchy_model_key
      end
    end
  end

  context "#enqueue_sync_to_hierarchy_job" do
    test "enqueues SyncMemexProjectItemByIdToIssuesGraphJob on create" do
      assert GitHub.issues_graph_api_enabled?
      assert_enqueued_with(job: SyncMemexProjectItemByIdToIssuesGraphJob) do
        create(:memex_project_item, memex_project: @memex)
      end
    end

    test "also enqueues SyncMemexProjectItemToIssuesGraphJob on create when pull request content" do
      pull_request = create(:pull_request, :disable_disk_access)
      assert GitHub.issues_graph_api_enabled?
      assert_enqueued_with(job: SyncMemexProjectItemByIdToIssuesGraphJob) do
        create(:memex_project_item, memex_project: @memex, content: pull_request)
      end
    end

    test "does not enqueue SyncMemexProjectItemToIssuesGraphJob on create when draft issue content" do
      draft_issue = create(:draft_issue)
      assert GitHub.issues_graph_api_enabled?
      assert_no_enqueued_jobs only: SyncMemexProjectItemByIdToIssuesGraphJob do
        create(:memex_project_item, memex_project: @memex, content: draft_issue)
      end
    end

    test "does not error when performed with DraftIssue" do
      draft_issue = create(:draft_issue)
      assert GitHub.issues_graph_api_enabled?
      assert_nothing_raised do
        perform_enqueued_jobs(only: SyncMemexProjectItemByIdToIssuesGraphJob) do
          create(:memex_project_item, memex_project: @memex, content: draft_issue)
        end
      end
    end

    test "does not error when performed with a PR" do
      pull_request = create(:pull_request, :disable_disk_access)
      assert GitHub.issues_graph_api_enabled?
      assert_nothing_raised do
        perform_enqueued_jobs(only: SyncMemexProjectItemByIdToIssuesGraphJob) do
          create(:memex_project_item, memex_project: @memex, content: pull_request)
        end
      end
    end

    test "enqueues SyncMemexProjectItemByIdToIssuesGraphJob on update" do
      memex_project_item = create(:memex_project_item, memex_project: @memex)
      assert_enqueued_with(job: SyncMemexProjectItemByIdToIssuesGraphJob, args: [memex_project_item.id]) do
        memex_project_item.touch
      end
    end

    test "logs message on update" do
      memex_project_item = create(:memex_project_item, memex_project: @memex)

      expected_keys = {
        "Body": "MemexProjectItem#enqueue_sync_to_hierarchy_job fired",
        "code.namespace": "MemexProjectItem",
        "code.function": "enqueue_sync_to_hierarchy_job",
        "gh.memex.item.id": memex_project_item.id,
        "gh.memex.item.is_destroyed": false
      }

      assert_logged(**expected_keys) do
        assert_enqueued_with(job: SyncMemexProjectItemByIdToIssuesGraphJob, args: [memex_project_item.id]) do
          memex_project_item.touch
        end
      end
    end

    test "does not enqueue SyncMemexProjectItemByIdToIssuesGraphJob on destroy" do
      assert_no_enqueued_jobs only: SyncMemexProjectItemByIdToIssuesGraphJob do
        @item.destroy
      end
    end

    test "logs message and raises error if enqueue_sync_to_hierarchy_job is invoked on destroyed object" do
      @item.destroy

      expected_keys = {
        "Body": "MemexProjectItem#enqueue_sync_to_hierarchy_job fired",
        "code.namespace": "MemexProjectItem",
        "code.function": "enqueue_sync_to_hierarchy_job",
        "gh.memex.item.id": @item.id,
        "gh.memex.item.is_destroyed": true
      }

      assert_logged(**expected_keys) do
        assert_raises MemexProjectItem::IssuesGraphDependency::SyncJobEnqueuedForDestroyedItemError do
          @item.enqueue_sync_to_hierarchy_job
        end
      end
    end

    test "noop when flag is not turned on" do
      GitHub.flipper[:issues_graph_api].disable

      assert_no_enqueued_jobs only: SyncMemexProjectItemByIdToIssuesGraphJob do
        create(:memex_project_item, memex_project: @memex)
      end
    end
  end

  context "#sync_to_hierarchy" do
    test "calls the client when the item is created" do
      @issue_graph_client
        .expects(:upsert_project_and_relationships)
        .once

      assert_performed_jobs 1, only: [SyncMemexProjectItemByIdToIssuesGraphJob] do
        create(:memex_project_item)
      end
    end

    test "calls the client when the item is updated" do
      @issue_graph_client
        .expects(:upsert_project_and_relationships)
        .with(
          has_entries(
            from: @item.memex_project.to_hierarchy_model,
            to: [@item.to_hierarchy_model],
          )
        ).once

      assert_performed_jobs 1, only: [SyncMemexProjectItemByIdToIssuesGraphJob] do
        @item.touch
      end
    end

    test "noop when the item is deleted" do
      @issue_graph_client
        .expects(:upsert_project_and_relationships)
        .with(
          from: @item_to_destroy.memex_project.to_hierarchy_model,
          to: [@item_to_destroy.to_hierarchy_model]
        ).never

      assert_performed_jobs 0, only: [SyncMemexProjectItemByIdToIssuesGraphJob] do
        @item.destroy
      end
    end

    test "noop when flag is not turned on" do
      GitHub.flipper[:issues_graph_api].disable

      @issue_graph_client
        .expects(:upsert_project_and_relationships)
        .with(
          from: @item.memex_project.to_hierarchy_model,
          to: [@item.to_hierarchy_model]
        ).never

      assert_performed_jobs 0, only: [SyncMemexProjectItemByIdToIssuesGraphJob] do
        @item.touch
      end
    end
  end
end
