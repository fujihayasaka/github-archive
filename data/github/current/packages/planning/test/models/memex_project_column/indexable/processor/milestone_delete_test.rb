# typed: true
# frozen_string_literal: true

require "test_helper"

class MilestoneDeleteTest < GitHub::TestCase
  include HydroTestHelpers
  include MemexHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    @actor = create(:user)
    @repo = create(:repository, owner: @actor)
    @user = create(:user)
    @repo.add_member(@user)
    @project = create(:memex_project, owner: @actor, title: "test project")
    @open_issue = create(:issue, repository: @repo,  state: "open")
    @pull = create(:pull_request, :disable_disk_access, repository: @repo)
    @milestone_1 = create(:milestone, repository: @repo, title: "Milestone 1")
    @milestone_2 = create(:milestone, repository: @repo, title: "Milestone 2")
    @milestone_field = @project.columns.find(&:milestone?).to_field
    @issue_item = create(:memex_project_item, content: @open_issue, memex_project: @project)
    @pr_item = create(:memex_project_item, content: @pull, memex_project: @project)
    @items = [@issue_item, @pr_item]
  end

  setup do
    setup_search
  end

  teardown do
    teardown_search
  end

  context "#subscriptions" do
    test "invoked in response to a column value update message" do
      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::MilestoneDelete, "github.v1.MilestoneDelete") do
        @milestone_1.destroy
      end
    end
  end

  context "#matching_elasticsearch_documents?" do
    test "returns true when there are matching documents in the index" do
      @open_issue.update(milestone: @milestone_1)
      populate_elasticsearch_index!(@items)
      message = milestone_delete_message
      assert MemexProjectColumn::Interface::Indexable::Processor::MilestoneDelete.new(message).matching_elasticsearch_documents?
    end

    test "returns false when there are no matching documents in the index" do
      populate_elasticsearch_index!(@items)
      message = milestone_delete_message
      refute MemexProjectColumn::Interface::Indexable::Processor::MilestoneDelete.new(message).matching_elasticsearch_documents?
    end
  end

  context "#canonical_data_present?" do
    test "passes when the milestone does NOT exist" do
      message = milestone_delete_message
      @milestone_1.destroy
      assert MemexProjectColumn::Interface::Indexable::Processor::MilestoneDelete.new(message).canonical_data_present?
    end

    test "does not pass when the milestone DOES exist" do
      message = milestone_delete_message
      refute MemexProjectColumn::Interface::Indexable::Processor::MilestoneDelete.new(message).canonical_data_present?
    end
  end

  context "#update" do
    test "removes matching field value across project items when a milestone has been deleted", es_8_only: true do
      control_issue = create(:issue, repository: @repo)
      control_issue.update(milestone: @milestone_2)
      control_project_item = create(:memex_project_item, content: control_issue, memex_project: @project)
      @open_issue.update(milestone: @milestone_1)
      @pull.issue.update(milestone: @milestone_1)
      populate_elasticsearch_index!(@items + [control_project_item])

      # Verify that the milestone has been indexed properly for all items
      @items.each do |item|
        doc = get_doc(item.id)
        assert_equal field_value(doc, @milestone_field), @milestone_1.slice(:id, :repository_id, :title), "Milestone id #{@milestone_1.id} not indexed for item id #{item.id}"
      end
      assert_equal field_value(get_doc(control_project_item.id), @milestone_field), @milestone_2.slice(:id, :repository_id, :title)

      message = milestone_delete_message
      MemexProjectColumn::Interface::Indexable::Processor::MilestoneDelete.new(message).update(es_client)
      @index.refresh

      # Verify that the milestone is now gone from all but our control item
      @items.each do |item|
        doc = get_doc(item.id)
        refute field(doc, @milestone_field.id), "Milestone id #{@milestone_1.id} was not deleted for item id #{item.id}"
      end
      assert_equal field_value(get_doc(control_project_item.id), @milestone_field), @milestone_2.slice(:id, :repository_id, :title)
    end

    test "does not refresh the index", es_8_only: true do
      message = milestone_delete_message
      index.docs.expects(:update_by_query)
        .returns(sample_update_by_query_response.to_hash)
        .with(anything, has_entries(refresh: "false"))
      MemexProjectColumn::Interface::Indexable::Processor::MilestoneDelete.new(message).update(es_client)
    end
  end

  test "provides correct project ids for resyncing on failure" do
    @open_issue.update(milestone: @milestone_1)
    populate_elasticsearch_index!(@items)
    message = milestone_delete_message
    processor = MemexProjectColumn::Interface::Indexable::Processor::MilestoneDelete.new(message)
    assert_equal [@issue_item.memex_project_id], processor.project_ids_to_resync_on_failure
  end

  test "provides correct updated models" do
    message = milestone_delete_message
    processor = MemexProjectColumn::Interface::Indexable::Processor::MilestoneDelete.new(message)
    assert_empty processor.updated_models
  end

  private def milestone_delete_message(milestone = @milestone_1)
    build_message(
      {
        actor: Hydro::EntitySerializer.user(@actor),
        milestone: Hydro::EntitySerializer.milestone(milestone),
      },
      schema: "github.v1.MilestoneDelete"
    )
  end
end
