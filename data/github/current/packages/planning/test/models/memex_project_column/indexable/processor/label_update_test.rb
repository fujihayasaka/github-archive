# typed: true
# frozen_string_literal: true

require "test_helper"

class LabelUpdateProcessorTest < GitHub::TestCase
  include MemexHelpers
  include HydroTestHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    @actor = create(:verified_user)
    @repo = create(:repository, owner: @actor)
    @label = create(:label, repository: @repo)
    @user = create(:user)
    @repo.add_member(@user)
    @issue = create(:issue, repository: @repo,  state: "open", assignee: @user).tap { |issue| issue.labels << @label }
    @project = create(:memex_project, owner: @actor, title: "test project")
    @project_item = create(:memex_project_item, content: @issue, memex_project: @project)
  end

  setup do
    setup_search
  end

  context "#subscriptions" do
    test "invoked on label rename event" do
      assert_consumes(MemexProjectColumn::Indexable::Processor::LabelUpdate, "github.v1.LabelUpdate") do
        @label.update(name: "new name")
      end
    end
  end

  context "#matching_elasticsearch_documents?" do
    test "returns true when there is at least one memex project item document in elasticsearch matching the label" do
      populate_elasticsearch_index!([@project_item])

      message = label_update_message(@user, @label)

      assert MemexProjectColumn::Indexable::Processor::LabelUpdate.new(message).matching_elasticsearch_documents?
    end

    test "returns false when there are no memex project item documents in elasticsearch matching the label" do
      other_label = create(:label, repository: @repo)
      other_issue = create(:issue, repository: @repo,  state: "open", assignee: @user).tap { |issue| issue.labels << other_label }
      project_item = create(:memex_project_item, content: other_issue, memex_project: @project)
      populate_elasticsearch_index!([project_item])

      message = label_update_message(@actor, @label)

      refute MemexProjectColumn::Indexable::Processor::LabelUpdate.new(message).matching_elasticsearch_documents?
    end
  end

  context "#update" do
    test "updates project item doc field_values across projects when a label is renamed" do
      issue = create(:issue, repository: @repo, assignee: @user).tap { |issue| issue.labels << @label }
      item_in_another_project = create(:memex_project_item, content: issue)
      populate_elasticsearch_index!([@project_item, item_in_another_project])

      message = label_update_message(@user, @label)

      response = MemexProjectColumn::Indexable::Processor::LabelUpdate.new(message).update(es_client)
      index.refresh

      assert_equal 2, response.updated
    end

    test "does not change order of field_values when a label is renamed" do
      labels_column = @project.find_column_by_name_or_id(MemexProjectColumn::LABELS_COLUMN_NAME)
      labels_field = labels_column.to_field
      unchanged_label = create(:label, repository: @repo, name: "b")
      renamed_label = create(:label, repository: @repo, name: "z")
      issue = create(:issue, repository: @repo, assignee: @user)
      issue.labels << unchanged_label
      issue.labels << renamed_label
      issue_item = create(:memex_project_item, memex_project: @project, content: issue)
      populate_elasticsearch_index!([issue_item])

      renamed_label.update!(name: "a")
      message = label_update_message(@user, renamed_label)

      to = [
        {
          "id" => unchanged_label.id,
          "name" => unchanged_label.name,
          "repository_id" => unchanged_label.repository_id,
        },
        {
          "id" => renamed_label.id,
          "name" => renamed_label.name,
          "repository_id" => renamed_label.repository_id,
        }
      ]

      assert_changes -> { field_value(get_doc(issue_item.id), labels_field) }, to: do
        response = MemexProjectColumn::Indexable::Processor::LabelUpdate.new(message).update(es_client)
        index.refresh

        assert_equal 1, response.updated
      end
    end
  end

  context "project_ids_to_resync_on_failure" do
    test "provides correct project ids for resyncing on failure", es_8_only: true do
      issue = create(:issue, repository: @repo, assignee: @user).tap { |issue| issue.labels << @label }
      item_in_another_project = create(:memex_project_item, content: issue)
      populate_elasticsearch_index!([@project_item, item_in_another_project])

      message = label_update_message(@user, @label)
      processor = MemexProjectColumn::Indexable::Processor::LabelUpdate.new(message)
      assert_equal [@project.id, item_in_another_project.memex_project_id].sort, processor.project_ids_to_resync_on_failure.sort
    end
  end

  context "#dependent_mysql_replication_cluster" do
    test "returns the Issues cluster" do
      message = label_update_message(@user, @label)
      processor = MemexProjectColumn::Indexable::Processor::LabelUpdate.new(message)
      assert_equal Issue.cluster_name, processor.dependent_mysql_replication_cluster
    end
  end

  context "#canonical data fetching" do
    test "returns true when the model is present" do
      message = label_update_message(@user, @label)

      passes_through_canonical_data_gate = MemexProjectColumn::Indexable::Processor::LabelUpdate.new(message).canonical_data_present?
      assert passes_through_canonical_data_gate
    end

    test "returns false when the model is not present" do
      message = label_update_message(@user, @label)
      @label.delete
      passes_through_canonical_data_gate = MemexProjectColumn::Indexable::Processor::LabelUpdate.new(message).canonical_data_present?
      refute passes_through_canonical_data_gate
    end
  end


  private

  def label_update_message(user = @actor, label = @label)
    build_message(
      {
        actor: Hydro::EntitySerializer.user(user),
        label: Hydro::EntitySerializer.label(label)
      },
      schema: "hydro.schemas.github.v1.LabelUpdate"
    )
  end
end
