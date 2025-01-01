# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueUpdateMilestoneTest < GitHub::TestCase
  include MemexHelpers
  include HydroTestHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    @actor = create(:user)
    @repo = create(:repository, owner: @actor)
    @user = create(:user)
    @repo.add_member(@user)
    @project = create(:memex_project, owner: @actor, title: "test project")
    @milestone_field = @project.columns.find(&:milestone?).to_field
    @issue = create(:issue, repository: @repo)
    @pull = create(:pull_request, :disable_disk_access, repository: @repo)
    @milestone = create(:milestone, repository: @repo)
    @issue_item = create(:memex_project_item, content: @issue, memex_project: @project)
    @pr_item = create(:memex_project_item, content: @pull, memex_project: @project)
  end

  setup do
    setup_search
  end

  teardown do
    teardown_search
  end

  context "#subscriptions" do
    test "invoked when a milestone is updated on an issue" do
      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateMilestone, "github.v1.IssueUpdateMilestone") do
        @issue.update(milestone: @milestone)
      end
    end

    test "invoked when a milestone is updated on a pull request" do
      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateMilestone, "github.v1.IssueUpdateMilestone") do
        @pull.issue.update(milestone: @milestone)
      end
    end
  end

  context "project_ids_to_resync_on_failure" do
    test "provides correct project ids for resyncing on failure" do
      project_2 = create(:memex_project, owner: @actor, title: "project 2")
      issue_item_2 = create(:memex_project_item, memex_project: project_2, content: @issue)
      @issue.update(milestone: @milestone)

      message = issue_update_milestone_message
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateMilestone.new(message)
      assert_equal [@project.id, project_2.id].sort, processor.project_ids_to_resync_on_failure.sort
    end
  end

  context "updated_models" do
    test "provides corrrect models" do
      project_2 = create(:memex_project, owner: @actor, title: "project 2")
      issue_item_2 = create(:memex_project_item, memex_project: project_2, content: @issue)
      @issue.update(milestone: @milestone)

      message = issue_update_milestone_message
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateMilestone.new(message)
      assert_same_elements [@issue, @issue_item, issue_item_2], processor.updated_models
    end
  end

  context "#update" do
    test "updates when the milestone is changed on an issue", es_8_only: true do
      target_project_item = @issue_item
      control_project_item = @pr_item

      # populate ES with two items that do not have milestone set
      initial_value = create(:milestone_column_value, column: @milestone_field, item: target_project_item)
      populate_elasticsearch_index!([target_project_item, control_project_item])
      refute_equal @milestone, target_project_item.column_value(@milestone_field)

      # Update an item to have a milestone
      @issue.update!(milestone: @milestone)
      message = issue_update_milestone_message(issue: @issue, milestone: @milestone)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateMilestone.new(message)
      response = processor.update(es_client)

      # Confirm that the expected milestone was updated
      target_result = get_doc(target_project_item.id)
      assert_equal field_value(target_result, @milestone_field), @milestone.slice(:id, :repository_id, :title)
      control_result = get_doc(control_project_item.id)
      assert_nil field(control_result, @milestone_field.id)
    end

    test "removes the field from field_values when the milestone is removed from an issue", es_8_only: true do
      # set up an issue containing a milestone
      @issue.update!(milestone: @milestone)
      populate_elasticsearch_index!([@issue_item])
      assert_equal @milestone, @issue.milestone
      doc = get_doc(@issue_item.id)
      assert field_value(doc, @milestone_field)

      # remove the milestone and emit a hydro message
      @issue.update!(milestone: nil)

      message = issue_update_milestone_message(issue: @issue, milestone: nil)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateMilestone.new(message)
      response = processor.update(es_client)
      assert_equal 1, response.items.size
      assert_equal Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Updated, response.items.first&.update&.result
      doc = get_doc(@issue_item.id)
      refute field(doc, @milestone_field.id)
    end

    test "noops when the value of the milestone has not changed", es_8_only: true do
      # set up an issue containing a milestone
      @issue.update!(milestone: @milestone)
      populate_elasticsearch_index!([@issue_item])
      # assert that attempting to update to the same value is a noop
      message = issue_update_milestone_message
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateMilestone.new(message)
      response = processor.update(es_client)
      assert_equal 1, response.items.size
      assert_equal Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Noop, response.items.first&.update&.result
    end

    test "only updates expected documents", es_8_only: true do
      # setup three items
      draft_issue = create(:draft_issue)
      draft_issue_item = create(:memex_project_item, content: draft_issue, memex_project: @project)
      items = [@issue_item, @pr_item, draft_issue_item]

      create(:milestone_column_value, column: @milestone_field, item: @issue_item)
      populate_elasticsearch_index!(items)
      new_milestone = create(:milestone, repository: @repo)

      # set the milestone value on the issue item
      @issue.update!(milestone: new_milestone)

      # assert that only the issue item was updated
      message = issue_update_milestone_message(milestone: new_milestone)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateMilestone.new(message)
      response = processor.update(es_client)
      @index.refresh
      assert_equal 1, response.items.size
      assert_equal Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Updated, response.items.first&.update&.result
    end

    test "updates matching issues across projects" do
      project2 = create(:memex_project, owner: @actor, title: "my other project")
      issue_item2 = create(:memex_project_item, content: @issue, memex_project: project2)
      populate_elasticsearch_index!([@issue_item, issue_item2])

      new_milestone = create(:milestone, repository: @repo)
      @issue.update!(milestone: new_milestone)

      message = issue_update_milestone_message(issue: @issue, milestone: new_milestone)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateMilestone.new(message)
      response = processor.update(es_client)

      assert_equal 2, response.items.size
      assert_equal Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Updated, response.items.first&.update&.result
      assert_equal Elastomer::Interfaces::Api::Bulk::Response::ItemResult::Result::Updated, response.items.second&.update&.result
    end

    test "raises canonical data missing error if project items are no longer present during update" do
      @issue_item.destroy!
      assert_raises(MemexProjectColumn::Interface::Indexable::CanonicalDataMissingError) do
        MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateMilestone.new(issue_update_milestone_message).update(es_client)
      end
    end
  end

  context "#dependent_mysql_replication_cluster" do
    test "returns the Issues cluster" do
      message = issue_update_milestone_message
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateMilestone.new(message)
      assert_equal Issue.cluster_name, processor.dependent_mysql_replication_cluster
    end
  end

  context "#canonial_data_present?" do
    test "returns true when the issue is present" do
      message = issue_update_milestone_message

      passes_through_canonical_data_gate = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateMilestone.new(message).canonical_data_present?
      assert passes_through_canonical_data_gate
    end

    test "returns false when the issue is not present" do
      message = issue_update_milestone_message
      @issue.delete
      passes_through_canonical_data_gate = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateMilestone.new(message).canonical_data_present?
      refute passes_through_canonical_data_gate
    end
  end

  context "#matching_elasticsearch_documents?" do
    test "returns true when there are matching documents" do
      @issue.update!(milestone: @milestone)
      populate_elasticsearch_index!([@issue_item])

      message = issue_update_milestone_message(issue: @issue, milestone: @milestone)
      assert MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateMilestone.new(message).matching_elasticsearch_documents?
    end

    test "returns false when there are no matching documents" do
      @issue.update!(milestone: @milestone)
      populate_elasticsearch_index!([@issue_item])
      # Create a different issue item
      issue2 = create(:issue, repository: @repo)

      # Message for issue2, which is not a memex item
      message = issue_update_milestone_message(issue: issue2, milestone: @milestone)
      refute MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateMilestone.new(message).matching_elasticsearch_documents?
    end
  end

  def issue_update_milestone_message(issue: @issue, milestone: @milestone)
    build_message(
      {
        actor: Hydro::EntitySerializer.user(@actor),
        repository: Hydro::EntitySerializer.repository(@repo),
        milestone: Hydro::EntitySerializer.milestone(milestone),
        issue: Hydro::EntitySerializer.issue(issue),
      },
      schema: "github.v1.IssueUpdateMilestone"
    )
  end
end
