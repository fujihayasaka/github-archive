# typed: true
# frozen_string_literal: true

require "test_helper"

class ContentStateChangeTest < GitHub::TestCase
  include MemexHelpers
  include HydroTestHelpers
  include ProjectsProcessorTestHelpers
  include PullRequestIntegrationTestHelpers

  fixtures do
    @actor = create(:verified_user)
    @repo = create(:repository, owner: @actor, has_discussions: true)
    @memex = create(:memex_project, owner: @actor, title: "My Memex Project")
    @issue = create(:issue, repository: @repo,  state: "open")
    @pull = setup_pull_request(repository: @repo)
    @issue_item = create(:memex_project_item, content: @issue, memex_project: @memex)
    @issue_items = [
      @issue_item,
      create(:memex_project_item, content: @issue),
      create(:memex_project_item, content: @issue)
    ]
    @pull_items = create_list(:memex_project_item, 2, content: @pull)
  end

  setup do
    setup_search
  end

  context "#subscriptions - issues" do
    test "invoked on issue close" do
      issue = create(:issue)
      reset_hydro

      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::ContentStateChange, "github.v1.IssueClose") do
        issue.close
      end
    end

    test "invoked on issue reopen" do
      issue = create(:issue)
      issue.close
      reset_hydro

      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::ContentStateChange, "github.v1.IssueReopen") do
        issue.open
      end
    end

    test "invoked on issue converted to discussion" do
      issue = create(:issue, repository: @repo, user: @actor)
      converter = IssueToDiscussionConverter.new(issue, actor: @actor)
      converter.prepare_for_conversion
      reset_hydro

      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::ContentStateChange, "github.v1.IssueConvertedToDiscussion") do
        converter.finish_conversion
      end
    end
  end

  context "#subscriptions - pull requests" do
    # Some parts of the pull request lifecycle are async or too slow to be reliable in tests.
    # To get around these issues, we test less of the stack, just publishing the message directly
    # and validating that the processor is invoked.
    test "invoked on pull request closed" do
      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::ContentStateChange, "github.v1.PullRequestClose") do
        hydro_publisher.publish({}, schema: "github.v1.PullRequestClose")
      end
    end

    test "invoked on pull request reopen" do
      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::ContentStateChange, "github.v1.PullRequestReopen") do
        hydro_publisher.publish({}, schema: "github.v1.PullRequestReopen")
      end
    end

    test "invoked on pull request merged" do
      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::ContentStateChange, "github.v1.PullRequestMerge") do
        hydro_publisher.publish({}, schema: "github.v1.PullRequestMerge")
      end
    end

    test "invoked on pull request converted to draft" do
      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::ContentStateChange, "github.v1.PullRequestConvertToDraft") do
        hydro_publisher.publish({}, schema: "github.v1.PullRequestConvertToDraft")
      end
    end

    test "invoked on pull request in progress" do
      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::ContentStateChange, "github.v1.PullRequestInProgress") do
        hydro_publisher.publish({}, schema: "github.v1.PullRequestInProgress")
      end
    end

    test "invoked on pull request ready for review" do
      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::ContentStateChange, "github.v1.PullRequestReadyForReview") do
        hydro_publisher.publish({}, schema: "github.v1.PullRequestReadyForReview")
      end
    end
  end

  context "#update" do
    test "updates issue state across multiple Elasticsearch documents", es_8_only: true do
      populate_elasticsearch_index!(@issue_items)
      assert_equal 3, index.count_all(content_query(@issue, state: "open"))

      @issue.close(@actor, attributes: { state_reason: "not_planned" })
      MemexProjectColumn::Interface::Indexable::Processor::ContentStateChange.new(issue_close_message).update(es_client)
      index.refresh

      assert_equal 0, index.count_all(content_query(@issue, state: "open"))
      assert_equal 3, index.count_all(content_query(@issue, state: "closed", state_reason: "not_planned"))
    end

    test "sets issue closed_at timestamp when issue is closed" do
      populate_elasticsearch_index!(@issue_items)

      original_doc = get_doc(@issue_item.id)
      assert_nil original_doc["_source"]["content"]["closed_at"], "closed_at should be nil before update"

      @issue.close(@actor, attributes: { state_reason: "not_planned" })
      MemexProjectColumn::Interface::Indexable::Processor::ContentStateChange.new(issue_close_message).update(es_client)
      index.refresh

      updated_doc = get_doc(@issue_item.id)
      assert_equal @issue.closed_at.iso8601, updated_doc["_source"]["content"]["closed_at"], "closed_at should not be nil after update"
    end

    test "clears issue closed_at timestamp when issue is re-opened" do
      @issue.close(@actor)
      populate_elasticsearch_index!(@issue_items)

      original_doc = get_doc(@issue_item.id)
      assert_equal @issue.closed_at.iso8601, original_doc["_source"]["content"]["closed_at"], "closed_at should not be nil before update"

      @issue.open(@actor)
      MemexProjectColumn::Interface::Indexable::Processor::ContentStateChange.new(issue_close_message).update(es_client)
      index.refresh

      updated_doc = get_doc(@issue_item.id)
      assert_nil updated_doc["_source"]["content"]["closed_at"], "closed_at should be nil after update"
    end

    test "updates issue state across multiple Elasticsearch documents with refresh enabled", es_8_only: true do
      GitHub.flipper[:memex_update_by_query_refresh].enable
      populate_elasticsearch_index!(@issue_items)
      assert_equal 3, index.count_all(content_query(@issue, state: "open"))

      @issue.close(@actor, attributes: { state_reason: "not_planned" })
      MemexProjectColumn::Interface::Indexable::Processor::ContentStateChange.new(issue_close_message).update(es_client)
      index.refresh

      assert_equal 0, index.count_all(content_query(@issue, state: "open"))
      assert_equal 3, index.count_all(content_query(@issue, state: "closed", state_reason: "not_planned"))
    end

    test "updates pull request open/closed state across multiple Elasticsearch documents", es_8_only: true do
      populate_elasticsearch_index!(@pull_items)
      assert_equal 2, index.count_all(content_query(@pull, state: "open"))

      @pull.close(@actor)
      MemexProjectColumn::Interface::Indexable::Processor::ContentStateChange.new(pull_close_message).update(es_client)
      index.refresh

      assert_equal 0, index.count_all(content_query(@pull, state: "open"))
      assert_equal 2, index.count_all(content_query(@pull, state: "closed"))
    end

    test "updates pull request draft state across multiple Elasticsearch documents", es_8_only: true do
      populate_elasticsearch_index!(@pull_items)
      assert_equal 0, index.count_all(content_query(@pull, is_draft: true))

      @pull.convert_to_draft(user: @actor)
      MemexProjectColumn::Interface::Indexable::Processor::ContentStateChange.new(pull_close_message).update(es_client)
      index.refresh

      assert_equal 2, index.count_all(content_query(@pull, is_draft: true))
    end

    test "noops when the index already has the latest values", es_8_only: true do
      @issue.close(@actor, attributes: { state_reason: "not_planned" })
      populate_elasticsearch_index!(@issue_items)
      response = MemexProjectColumn::Interface::Indexable::Processor::ContentStateChange.new(issue_close_message).update(es_client)
      expected_noop_count = @issue_items.count
      expected_total = expected_noop_count
      actual_noops = response.items.select do |item|
        item.update&.result == Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Noop
      end

      assert_equal expected_total, response.items.count
      assert_equal expected_noop_count, actual_noops.count
    end

    test "raises canonical data missing error if project items are no longer present during update", es_8_only: true do
      @pull_items.each(&:destroy!)
      assert_raises(MemexProjectColumn::Interface::Indexable::CanonicalDataMissingError) do
        MemexProjectColumn::Interface::Indexable::Processor::ContentStateChange.new(pull_close_message).update(es_client)
      end
    end

    test "raises canonical data missing error if content is no longer present during update", es_8_only: true do
      message = pull_close_message
      @pull.destroy!
      assert_raises(MemexProjectColumn::Interface::Indexable::CanonicalDataMissingError) do
        MemexProjectColumn::Interface::Indexable::Processor::ContentStateChange.new(message).update(es_client)
      end
    end
  end

  test "provides correct project ids for resyncing on failure" do
    @pull.convert_to_draft(user: @actor)
    project_ids = @pull.memex_project_items.map(&:memex_project_id)
    processor = MemexProjectColumn::Interface::Indexable::Processor::ContentStateChange.new(pull_close_message)
    assert_equal project_ids.sort, processor.project_ids_to_resync_on_failure.sort
  end

  test "provides correct updated models" do
    @pull.convert_to_draft(user: @actor)
    processor = MemexProjectColumn::Interface::Indexable::Processor::ContentStateChange.new(pull_close_message)
    assert_same_elements [@pull, *@pull.memex_project_items], processor.updated_models
  end

  private def content_query(content, state: nil, state_reason: nil, is_draft: nil)
    extra_clauses = []
    extra_clauses << { "term": { "content.state": state } } if state.present?
    extra_clauses << { "term": { "content.state_reason": state_reason } } if state_reason.present?
    extra_clauses << { "term": { "content.is_draft": is_draft } } if is_draft.present?

    {
      "query": {
        "bool": {
          "filter": {
            "bool": {
              "filter": [
                {
                  "term": {
                    "content.repository_id": content.repository_id,
                  }
                },
                {
                  "term": {
                    "content.id": content.id,
                  }
                },
                {
                  "term": {
                    "content.type": content.class.name,
                  }
                }
              ] + extra_clauses.compact
            }
          }
        }
      }
    }
  end

  private def issue_close_message
    build_message(
      {
        actor: Hydro::EntitySerializer.user(@actor),
        issue: Hydro::EntitySerializer.issue(@issue),
        repository: Hydro::EntitySerializer.repository(@repo),
      },
      schema: "github.v1.IssueClose"
    )
  end

  private def pull_close_message
    build_message(
      {
        actor: Hydro::EntitySerializer.user(@actor),
        issue: Hydro::EntitySerializer.issue(@issue),
        pull_request: Hydro::EntitySerializer.pull_request(@pull),
        repository: Hydro::EntitySerializer.repository(@repo),
        repository_owner: Hydro::EntitySerializer.user(@repo.owner),
      },
      schema: "github.v1.PullRequestClose"
    )
  end
end
