# typed: true
# frozen_string_literal: true

require "test_helper"

class MilestoneUpdateTest < GitHub::TestCase
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
    test "invoked in response to a milestone title update" do
      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::MilestoneUpdate, "github.v1.MilestoneUpdate") do
        @milestone_1.update(title: "#{@milestone_1.title} copy")
      end
    end
  end

  context "#valid_message?" do
    test "passes when the milestone title has changed" do
      previous_title = @milestone_1.title
      @milestone_1.update(title: "#{@milestone_1.title} copy")
      message = milestone_update_message(@milestone_1, previous_title)
      assert MemexProjectColumn::Interface::Indexable::Processor::MilestoneUpdate.new(message).valid_message?
    end

    test "returns false when the milestone title has not changed" do
      previous_title = @milestone_1.title
      message = milestone_update_message(@milestone_1, previous_title)
      refute MemexProjectColumn::Interface::Indexable::Processor::MilestoneUpdate.new(message).valid_message?
    end
  end

  context "#matching_elasticsearch_documents?" do
    test "returns true when there are matching documents in the index" do
      @open_issue.update(milestone: @milestone_1)
      populate_elasticsearch_index!(@items)
      message = milestone_update_message
      assert MemexProjectColumn::Interface::Indexable::Processor::MilestoneUpdate.new(message).matching_elasticsearch_documents?
    end

    test "returns false when there are no matching documents in the index" do
      populate_elasticsearch_index!(@items)
      message = milestone_update_message
      refute MemexProjectColumn::Interface::Indexable::Processor::MilestoneUpdate.new(message).matching_elasticsearch_documents?
    end
  end

  context "#canonical_data_present?" do
    test "passes when the milestone exists" do
      message = milestone_update_message
      assert MemexProjectColumn::Interface::Indexable::Processor::MilestoneUpdate.new(message).canonical_data_present?
    end

    test "does not pass when the milestone does not exist" do
      message = milestone_update_message
      @milestone_1.destroy
      refute MemexProjectColumn::Interface::Indexable::Processor::MilestoneUpdate.new(message).canonical_data_present?
    end
  end

  context "#update" do
    test "updates matching field value when a milestone title changes", es_8_only: true do
      # arrange
      target_project_item = @issue_item
      control_project_item = @pr_item
      @open_issue.update(milestone: @milestone_1)
      populate_elasticsearch_index!(@items)

      doc = get_doc(target_project_item.id)
      assert_equal field_value(doc, @milestone_field), @milestone_1.slice(:id, :repository_id, :title)

      previous_title = @milestone_1.title
      new_title = "#{@milestone_1.title} copy"
      @milestone_1.update(title: new_title)
      assert_equal @milestone_1.reload.title, new_title
      message = milestone_update_message(@milestone_1, previous_title)

      # act
      MemexProjectColumn::Interface::Indexable::Processor::MilestoneUpdate.new(message).update(es_client)
      @index.refresh

      # assert
      target_result = get_doc(target_project_item.id)
      assert_equal field_value(target_result, @milestone_field), @milestone_1.slice(:id, :repository_id, :title)
      control_result = get_doc(control_project_item.id)
      assert_nil field(control_result, @milestone_field.id)
    end

    test "noops when the milestone title already exists in the index", es_8_only: true do
      target_project_item = @issue_item
      @open_issue.update(milestone: @milestone_1)
      populate_elasticsearch_index!(@items)

      indexed_document = get_doc(target_project_item.id)

      message = milestone_update_message
      response = MemexProjectColumn::Interface::Indexable::Processor::MilestoneUpdate.new(message).update(es_client)
      assert_equal 1, response.noops
      assert_equal 0, response.updated
    end

    test "does not refresh the index", es_8_only: true do
      message = milestone_update_message
      index.docs.expects(:update_by_query)
        .returns(sample_update_by_query_response.to_hash)
        .with(anything, has_entries(refresh: "false"))
      MemexProjectColumn::Interface::Indexable::Processor::MilestoneUpdate.new(message).update(es_client)
    end
  end

  test "provides correct project ids for resyncing on failure" do
    @open_issue.update(milestone: @milestone_1)
    populate_elasticsearch_index!(@items)
    message = milestone_update_message
    processor = MemexProjectColumn::Interface::Indexable::Processor::MilestoneUpdate.new(message)
    assert_equal [@issue_item.memex_project_id], processor.project_ids_to_resync_on_failure
  end

  test "provides correct updated models" do
    @open_issue.update(milestone: @milestone_1)
    populate_elasticsearch_index!(@items)
    message = milestone_update_message
    processor = MemexProjectColumn::Interface::Indexable::Processor::MilestoneUpdate.new(message)
    assert_equal [@milestone_1], processor.updated_models
  end

  private def milestone_update_message(milestone = @milestone_1, previous_title = milestone.title)
    build_message(
      {
        actor: Hydro::EntitySerializer.user(@actor),
        milestone: Hydro::EntitySerializer.milestone(milestone),
        previous_title:
      },
      schema: "github.v1.MilestoneUpdate"
    )
  end
end
