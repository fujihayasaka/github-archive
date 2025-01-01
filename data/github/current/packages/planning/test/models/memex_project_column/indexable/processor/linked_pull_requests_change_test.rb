# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumn::Interface::Indexable::Processor::LinkedPullRequestsChangeTest < GitHub::TestCase
  include HydroTestHelpers
  include MemexHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    @actor = create(:user)
    @repo = create(:repository, owner: @actor)
    @user = create(:user)
    @repo.add_member(@user)
    @project = create(:memex_project, owner: @actor, title: "test project")
    @linked_pull_requests_field = @project.memex_project_columns.find(&:linked_pull_requests?).to_field
    @issue = create(:issue, repository: @repo, state: "open")
    @issue_item = create(:memex_project_item, content: @issue, memex_project: @project)
    @linked_pr = create(:pull_request, :disable_disk_access, repository: @repo, user: @user)
  end

  setup do
    setup_search
  end

  teardown do
    teardown_search
  end

  context "#matching elasticsearch documents" do
    test "returns true when there are matching documents" do
      @issue.close_issue_references.create!(
        actor_id: @user.id,
        pull_request: @linked_pr,
      )
      populate_elasticsearch_index!([@issue_item])
      message = column_update_message(issue: @issue, pull_request: @linked_pr, disconnected: true)

      assert MemexProjectColumn::Interface::Indexable::Processor::LinkedPullRequestsChange.new(message).matching_elasticsearch_documents?

    end

    test "returns false when there are no matching documents" do
      other_issue = create(:issue, repository: @repo, state: "open")
      other_issue_item = create(:memex_project_item, content: other_issue, memex_project: @project)
      @issue.close_issue_references.create!(
        actor_id: @user.id,
        pull_request: @linked_pr,
      )
      populate_elasticsearch_index!([@issue_item])
      message = column_update_message(issue: other_issue, pull_request: @linked_pr, disconnected: true)

      refute MemexProjectColumn::Interface::Indexable::Processor::LinkedPullRequestsChange.new(message).matching_elasticsearch_documents?

    end
  end

  context "#canonical data fetching" do
    test "returns true when the model is present" do
      message = column_update_message(issue: @issue, pull_request: @linked_pr, disconnected: true)

      passes_through_canonical_data_gate = MemexProjectColumn::Interface::Indexable::Processor::LinkedPullRequestsChange.new(message).canonical_data_present?
      assert passes_through_canonical_data_gate
    end

    test "returns false when the model is not present" do
      message = column_update_message(issue: @issue, pull_request: @linked_pr, disconnected: true)
      @issue.delete
      passes_through_canonical_data_gate = MemexProjectColumn::Interface::Indexable::Processor::LinkedPullRequestsChange.new(message).canonical_data_present?
      refute passes_through_canonical_data_gate
    end
  end

  context "#update" do
    test "updates with new linked pull request", es_8_only: true do
      populate_elasticsearch_index!([@issue_item])

      ref = @issue.close_issue_references.create!(
        actor_id: @user.id,
        pull_request: @linked_pr,
      )

      message = column_update_message(issue: @issue, pull_request: @linked_pr)
      processor = MemexProjectColumn::Interface::Indexable::Processor::LinkedPullRequestsChange.new(message)
      response = processor.update(es_client)
      @index.refresh

      successes = response.items.map(&:update).filter_map { |r| r&.status == 200 }
      assert_equal 1, successes.size

      doc = get_doc(@issue_item.id)
      field_value = field_value(doc, @linked_pull_requests_field)
      assert field_value.find { _1["id"] == ref.pull_request_id }
    end

    test "removes field from field_values when last linked pr is removed", es_8_only: true do
      ref = @issue.close_issue_references.create!(
        actor_id: @user.id,
        pull_request: @linked_pr,
      )
      populate_elasticsearch_index!([@issue_item])

      ref.destroy

      message = column_update_message(issue: @issue, pull_request: @linked_pr, disconnected: true)
      processor = MemexProjectColumn::Interface::Indexable::Processor::LinkedPullRequestsChange.new(message)
      response = processor.update(es_client)
      @index.refresh
      successes = response.items.map(&:update).filter_map { |r| r&.status == 200 }
      assert_equal 1, successes.size

      doc = get_doc(@issue_item.id)
      refute field(doc, @linked_pull_requests_field.id)
    end

    test "updates field value when 1 of 2 linked prs is removed", es_8_only: true do
      pr = create(:pull_request, :disable_disk_access, repository: @repo, user: @actor, base_ref: "topic-partial-merge")
      refs = [
        @issue.close_issue_references.create!(actor_id: @user.id, pull_request: @linked_pr),
        @issue.close_issue_references.create!(actor_id: @actor.id, pull_request: pr),
      ]
      populate_elasticsearch_index!([@issue_item])

      doc = get_doc(@issue_item.id)
      field_value = field_value(doc, @linked_pull_requests_field)
      refs.each do |ref|
        assert field_value.find { _1["id"] == ref.pull_request_id }
      end

      ref_ids = refs.map(&:pull_request_id)
      refs.first.destroy

      message = column_update_message(issue: @issue, pull_request: @linked_pr, disconnected: true)
      processor = MemexProjectColumn::Interface::Indexable::Processor::LinkedPullRequestsChange.new(message)
      response = processor.update(es_client)
      @index.refresh
      successes = response.items.map(&:update).filter_map { |r| r&.status == 200 }
      assert_equal 1, successes.size

      value = field_value(get_doc(@issue_item.id), @linked_pull_requests_field)
      refute value.find { _1["id"] == ref_ids.first }
      assert value.find { _1["id"] == ref_ids.second }
    end

    test "noops when linked_pull_requests_column value already exists in the index" do
      # populate ES with an item that has a linked_pr
      @issue.close_issue_references.create!(
        actor_id: @user.id,
        pull_request: @linked_pr,
      )
      populate_elasticsearch_index!([@issue_item])

      # send a message that has the same list
      message = column_update_message(issue: @issue, pull_request: @linked_pr)

      # Process the message and save the response
      response = MemexProjectColumn::Interface::Indexable::Processor::LinkedPullRequestsChange.new(message).update(es_client)

      assert_equal Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Noop, response.items.first&.update&.result
    end

    test "only updates expected documents" do
      issue_in_same_repo = create(:issue, repository: @issue.repository)
      issue_in_different_repo = create(:issue)
      draft_issue = create(:draft_issue)

      items = [
        create(:memex_project_item, content: issue_in_same_repo, memex_project: @project),
        create(:memex_project_item, content: issue_in_different_repo, memex_project: @project),
        create(:memex_project_item, content: draft_issue, memex_project: @project),
        @issue_item
      ]
      ref = @issue.close_issue_references.create!(actor_id: @user.id, pull_request: @linked_pr)

      populate_elasticsearch_index!(items)

      # Artificially set the draft issue id to be the same as our issue id, to test content type matching
      response = index.docs.update(document_wrapper({ _id: items[2].id, doc: { content: { id: @issue.id } } }), { routing: @project.id })
      index.refresh

      ref.destroy!
      message = column_update_message(issue: @issue, pull_request: @linked_pr, disconnected: true)
      response = MemexProjectColumn::Interface::Indexable::Processor::LinkedPullRequestsChange.new(message).update(es_client)
      assert_equal response.items.size, 1
    end

    test "updates matching issues across projects" do
      project2 = create(:memex_project, owner: @actor, title: "my other project")
      issue_item2 = create(:memex_project_item, content: @issue, memex_project: project2)

      populate_elasticsearch_index!([@issue_item, issue_item2])

      @issue.close_issue_references.create!(
        actor_id: @user.id,
        pull_request: @linked_pr,
      )

      message = column_update_message(issue: @issue, pull_request: @linked_pr)
      processor = MemexProjectColumn::Interface::Indexable::Processor::LinkedPullRequestsChange.new(message)
      response = processor.update(es_client)

      assert_equal response.items.size, 2
    end
  end

  context "#dependent_mysql_replication_cluster" do
    test "returns the Issues cluster" do
      message = column_update_message(issue: @issue, pull_request: @linked_pr)
      processor = MemexProjectColumn::Interface::Indexable::Processor::LinkedPullRequestsChange.new(message)
      assert_equal Issue.cluster_name, processor.dependent_mysql_replication_cluster
    end
  end

  context "project_ids_to_resync_on_failure" do
    test "provides correct project ids for resyncing on failure" do
      project_2 = create(:memex_project)
      issue_item_2 = create(:memex_project_item, memex_project: project_2, content: @issue)
      create(:close_issue_reference, issue: @issue, pull_request: @linked_pr)
      message = column_update_message(issue: @issue, pull_request: @linked_pr)
      processor = MemexProjectColumn::Interface::Indexable::Processor::LinkedPullRequestsChange.new(message)
      assert_same_elements [@issue_item.memex_project_id, issue_item_2.memex_project_id], processor.project_ids_to_resync_on_failure
    end
  end

  context "updated_models" do
    test "provides correct models" do
      project_2 = create(:memex_project)
      issue_item_2 = create(:memex_project_item, memex_project: project_2, content: @issue)
      create(:close_issue_reference, issue: @issue, pull_request: @linked_pr)
      message = column_update_message(issue: @issue, pull_request: @linked_pr)
      processor = MemexProjectColumn::Interface::Indexable::Processor::LinkedPullRequestsChange.new(message)
      assert_same_elements [@issue, @issue_item, issue_item_2], processor.updated_models
    end
  end

  context "subscriptions" do
    test "invoked when a pr is linked to an issue" do
      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::LinkedPullRequestsChange, "github.v1.CloseIssueReferenceConnected") do
        create(:close_issue_reference, issue: @issue, pull_request: @linked_pr)
      end
    end

    test "invoked when a pr is unlinked from an issue" do
      @issue.close_issue_references.create!(
        actor_id: @user.id,
        pull_request: @linked_pr,
      )
      reset_hydro

      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::LinkedPullRequestsChange, "github.v1.CloseIssueReferenceDisconnected") do
        @issue.close_issue_references.first.destroy
      end
    end
  end

  context "valid_message?" do
    test "returns true if all criterion are met" do
      message = column_update_message(issue: @issue, pull_request: @linked_pr)
      processor = MemexProjectColumn::Interface::Indexable::Processor::LinkedPullRequestsChange.new(message)
      assert processor.valid_message?
    end

    test "returns false if issue is not present" do
      message = column_update_message(issue: nil, pull_request: @linked_pr, include_repository: false)
      processor = MemexProjectColumn::Interface::Indexable::Processor::LinkedPullRequestsChange.new(message)
      refute processor.valid_message?
    end

    test "returns false if issue repository is not present" do
      message = column_update_message(issue: @issue, pull_request: @linked_pr, include_repository: false)
      processor = MemexProjectColumn::Interface::Indexable::Processor::LinkedPullRequestsChange.new(message)
      refute processor.valid_message?
    end

    test "returns false if issue reference is disallowed" do
      message = column_update_message(issue: @issue, pull_request: @linked_pr)
      processor = MemexProjectColumn::Interface::Indexable::Processor::LinkedPullRequestsChange.new(message)

      MemexProjectColumn::Interface::Indexable::Processor::LinkedPullRequestsChange.stub_const(:DISALLOWED_REFERENCES, [[@issue.id, @issue.repository_id]]) do
        refute processor.valid_message?
      end
    end
  end

  def column_update_message(issue:, pull_request:, disconnected: false, include_repository: true)
    build_message(
      {
        actor: Hydro::EntitySerializer.user(@actor),
        issue_repository: include_repository ? Hydro::EntitySerializer.repository(issue.repository) : nil,
        issue: issue.present? ? Hydro::EntitySerializer.issue(issue) : nil,
        pull_request: Hydro::EntitySerializer.pull_request(pull_request),
        pull_request_author: Hydro::EntitySerializer.user(@user),
      }.compact,
      schema: "github.v1.CloseIssueReference#{disconnected ? "Disc" : "C"}onnected"
    )
  end

  private def document_wrapper(body)
    if index.index_running_version_8_plus?
      body
    else
      body.merge({ _type: Elastomer::Adapters::MemexProjectItem.document_type })
    end
  end
end
