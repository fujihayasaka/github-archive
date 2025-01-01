# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueTransferUpdatesTest < GitHub::TestCase
  include MemexHelpers
  include HydroTestHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    @actor = create(:user)
    @repo = create(:repository, owner: @actor)
    @new_repo = create(:repository, owner: @actor)
    @user = create(:user)
    @repo.add_member(@user)
    @new_repo.add_member(@user)
    @project = create(:memex_project, owner: @actor, title: "test project")
    @open_issue = create(:issue, repository: @repo,  state: "open")
    @closed_issue = create(:issue, repository: @repo,  state: "closed")
    @pull = create(:pull_request, :disable_disk_access, repository: @repo)
    @repository_field = @project.columns.find(&:repository?).to_field
    @labels_field = @project.columns.find(&:labels?).to_field
    @milestone_field = @project.columns.find(&:milestone?).to_field
    @project_items = [
      create(:memex_project_item, content: @open_issue, memex_project: @project),
      create(:memex_project_item, content: @pull, memex_project: @project),
      create(:memex_project_item, content: @closed_issue, memex_project: @project)
    ]
  end

  setup do
    setup_search
    @index = Elastomer::Indexes::MemexProjectItems.new
  end

  context "#subscriptions" do
    test "invoked on issue transfer" do
      assert_consumes(MemexProjectColumn::Indexable::Processor::IssueTransferUpdates, "github.v1.IssueTransferred") do
        transfer = IssueTransfer.new(old_issue: @open_issue, old_repository: @open_issue.repository, new_repository: @new_repo, actor: @user)
        transfer.transfer!
        transfer.save!
        assert transfer.new_issue
      end
    end
  end

  context "#matching_elasticsearch_documents?" do
    test "returns true when there is at least one memex project item document in elastic search matching the issue being transferred" do
      populate_elasticsearch_index!(@project_items)

      transfer = initiate_issue_transfer(old_issue: @open_issue, old_repository: @open_issue.repository, new_repository: @new_repo, actor: @user)
      message = issue_transfer_message(issue: @open_issue, new_issue: transfer.new_issue, actor: @user)

      assert MemexProjectColumn::Indexable::Processor::IssueTransferUpdates.new(message).matching_elasticsearch_documents?
    end

    test "returns false when there are no memex project item documents in elastic search matching the issue being transferred" do
      populate_elasticsearch_index!(@project_items)

      issue_not_in_project = create(:issue, repository: @repo,  state: "open")

      transfer = initiate_issue_transfer(old_issue: issue_not_in_project, old_repository: issue_not_in_project.repository, new_repository: @new_repo, actor: @user)
      message = issue_transfer_message(issue: issue_not_in_project, new_issue: transfer.new_issue, actor: @user)

      refute MemexProjectColumn::Indexable::Processor::IssueTransferUpdates.new(message).matching_elasticsearch_documents?
    end
  end

  context "#canonical_data_present?" do
    test "returns true when the issue transferred exists in the database" do
      populate_elasticsearch_index!(@project_items)

      transfer = initiate_issue_transfer(old_issue: @open_issue, old_repository: @open_issue.repository, new_repository: @new_repo, actor: @user)
      message = issue_transfer_message(issue: @open_issue, new_issue: transfer.new_issue, actor: @user)

      assert MemexProjectColumn::Indexable::Processor::IssueTransferUpdates.new(message).canonical_data_present?
    end

    test "returns false when the issue transferred dosn't exist in the database" do
      populate_elasticsearch_index!(@project_items)

      transfer = initiate_issue_transfer(old_issue: @open_issue, old_repository: @open_issue.repository, new_repository: @new_repo, actor: @user)
      message = issue_transfer_message(issue: @open_issue, new_issue: transfer.new_issue, actor: @user)
      transfer.new_issue.delete

      refute MemexProjectColumn::Indexable::Processor::IssueTransferUpdates.new(message).canonical_data_present?
    end
  end

  context "#update" do
    test "updates project item content and repository field_values when an issue is transferred" do
      # arrange
      item_in_another_project = create(:memex_project_item, content: @open_issue)
      another_repository = item_in_another_project.memex_project.columns.find(&:repository?).to_field
      populate_elasticsearch_index!(@project_items + [item_in_another_project])

      # act
      transfer = initiate_issue_transfer(old_issue: @open_issue, old_repository: @open_issue.repository, new_repository: @new_repo, actor: @user)
      message = issue_transfer_message(issue: @open_issue, new_issue: transfer.new_issue, actor: @user)
      MemexProjectColumn::Indexable::Processor::IssueTransferUpdates.new(message).update(es_client)
      @index.refresh

      # assert
      # both items that point to the same issue now should have fields updated
      item_in_this_project = get_doc(@project_items[0].id)
      item_in_another_project = get_doc(item_in_another_project.id)
      expected_content = {
        "id" => transfer.new_issue.id,
        "number" => transfer.new_issue.number,
        "state_reason" => nil,
        "is_draft" => false,
        "repository_id" => @new_repo.id,
        "state" => "open",
        "type" => "Issue"
      }

      assert_equal expected_content, item_in_this_project.dig("_source", "content")
      assert_equal expected_content, item_in_another_project.dig("_source", "content")

      # asserting repo fields
      item_in_this_project_repo = field_value(item_in_this_project, @repository_field)
      item_in_another_project_repo = field_value(item_in_another_project, another_repository)
      expected_repo_field = {
        "id" => @new_repo.id,
        "full_name" => @new_repo.full_name,
        "owner_id" => @new_repo.owner.id,
        "owner_type" => @new_repo.owner.type
      }

      assert_equal expected_repo_field, item_in_this_project_repo
      assert_equal expected_repo_field, item_in_another_project_repo
    end

    test "updates project item labels and milestone on issue transfer" do
      # arrange
      source_label_a = create(:label, repository: @repo)
      source_label_b = create(:label, repository: @repo)
      source_milestone = create(:milestone, repository: @repo)

      dest_label_b = create(:label, repository: @new_repo)
      dest_label_b.name = source_label_b.name
      dest_label_b.save!

      dest_milestone = create(:milestone, repository: @new_repo)
      dest_milestone.title = source_milestone.title
      dest_milestone.save!

      issue = create(:issue, repository: @repo, state: "open")
      issue.replace_labels([source_label_a, source_label_b])
      issue.milestone = source_milestone
      issue.save!
      issue.reload
      project_item = create(:memex_project_item, content: issue, memex_project: @project)
      populate_elasticsearch_index!([project_item])

      # act
      transfer = initiate_issue_transfer(old_issue: issue, old_repository: issue.repository, new_repository: @new_repo, actor: @user)
      message = issue_transfer_message(issue: issue, new_issue: transfer.new_issue, actor: @user)
      MemexProjectColumn::Indexable::Processor::IssueTransferUpdates.new(message).update(es_client)
      @index.refresh

      # assert
      document = get_doc(project_item.id)

      # assert labels
      document_labels = field_value(document, @labels_field)
      assert_equal 1, document_labels.length
      assert_equal dest_label_b.id, document_labels[0]["id"]

      # assert milestone
      document_milestone = field_value(document, @milestone_field)
      assert_equal dest_milestone.id, document_milestone["id"]
    end

    test "No-ops if the issue transfer has already been processed" do
      populate_elasticsearch_index!(@project_items)
      transfer = initiate_issue_transfer(old_issue: @open_issue, old_repository: @open_issue.repository, new_repository: @new_repo, actor: @user)
      message = issue_transfer_message(issue: @open_issue, new_issue: transfer.new_issue, actor: @user)

      response = MemexProjectColumn::Indexable::Processor::IssueTransferUpdates.new(message).update(es_client)
      @index.refresh
      assert_equal 1, response.updated

      # Another message for the same issue transfer comes in
      response = MemexProjectColumn::Indexable::Processor::IssueTransferUpdates.new(message).update(es_client)

      assert_equal 0, response.updated
    end

    test "provides correct project ids for resyncing on failure" do
      item_in_another_project = create(:memex_project_item, content: @open_issue, memex_project: create(:memex_project, owner: @actor))

      transfer = initiate_issue_transfer(old_issue: @open_issue, old_repository: @open_issue.repository, new_repository: @new_repo, actor: @user)
      message = issue_transfer_message(issue: @open_issue, new_issue: transfer.new_issue, actor: @user)

      processor = MemexProjectColumn::Indexable::Processor::IssueTransferUpdates.new(message)
      assert_equal [@project.id, item_in_another_project.memex_project.id].sort, processor.project_ids_to_resync_on_failure.sort
    end
  end

  context "#dependent_mysql_replication_cluster" do
    test "returns the Issues cluster" do
      transfer = initiate_issue_transfer(old_issue: @open_issue, old_repository: @open_issue.repository, new_repository: @new_repo, actor: @user)
      message = issue_transfer_message(issue: @open_issue, new_issue: transfer.new_issue, actor: @user)
      processor = MemexProjectColumn::Indexable::Processor::IssueTransferUpdates.new(message)
      assert_equal Issue.cluster_name, processor.dependent_mysql_replication_cluster
    end
  end


  private

  def issue_transfer_message(issue:, new_issue:, actor:)
    build_message(
      {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        old_repository: Hydro::EntitySerializer.repository(issue.repository),
        old_issue: Hydro::EntitySerializer.issue(issue),
        new_repository: Hydro::EntitySerializer.repository(new_issue.repository),
        new_issue: Hydro::EntitySerializer.issue(new_issue),
        actor: Hydro::EntitySerializer.user(actor),
      },
      schema: "github.v1.IssueTransferred"
    )
  end

  def initiate_issue_transfer(old_issue:, old_repository:, new_repository:, actor:)
    transfer = IssueTransfer.new(old_issue: old_issue, old_repository: old_repository, new_repository: new_repository, actor: actor)
    transfer.transfer!
    transfer.save!
    transfer
  end
end
