# typed: true
# frozen_string_literal: true

require "test_helper"

class LabelDeleteProcessorTest < GitHub::TestCase
  include MemexHelpers
  include HydroTestHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    @actor = create(:verified_user)
    @repo = create(:repository, owner: @actor)
    @label_a = create(:label, repository: @repo)
    @label_b = create(:label, repository: @repo)
    @user = create(:user)
    @repo.add_member(@user)
    @issue = create(:issue, repository: @repo,  state: "open", assignee: @user).tap { |issue| issue.labels << @label_a << @label_b }
    @project = create(:memex_project, owner: @actor, title: "test project")
    @project_item = create(:memex_project_item, content: @issue, memex_project: @project)
    @labels_field = @project.memex_project_columns.find(&:labels?).to_field
  end

  setup do
    setup_search
  end

  context "#subscriptions" do
    test "invoked on label delete event" do
      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::LabelDelete, "github.v1.LabelDelete") do
        @label_a.destroy!
      end
    end
  end

  context "#matching_elasticsearch_documents?" do
    test "returns true when there is at least one memex project item document in elasticsearch matching the label" do
      populate_elasticsearch_index!([@project_item])

      message = label_delete_message(@user, @label_a)

      assert MemexProjectColumn::Interface::Indexable::Processor::LabelDelete.new(message).matching_elasticsearch_documents?
    end

    test "returns false when there are no memex project item documents in elasticsearch matching the label" do
      other_label = create(:label, repository: @repo)
      other_issue = create(:issue, repository: @repo,  state: "open", assignee: @user).tap { |issue| issue.labels << other_label }
      project_item = create(:memex_project_item, content: other_issue, memex_project: @project)
      populate_elasticsearch_index!([project_item])

      message = label_delete_message(@actor, @label_a)

      refute MemexProjectColumn::Interface::Indexable::Processor::LabelDelete.new(message).matching_elasticsearch_documents?
    end
  end

  context "#update" do
    test "updates project item doc field_values across projects when a label is deleted" do
      # arrange
      issue_a = create(:issue, repository: @repo, assignee: @user).tap { |issue| issue.labels << @label_b << @label_a }
      another_project_item = create(:memex_project_item, content: issue_a, memex_project: @project)

      issue_b = create(:issue, repository: @repo, assignee: @user).tap { |issue| issue.labels << @label_a }
      item_in_another_project = create(:memex_project_item, content: issue_b)

      populate_elasticsearch_index!([@project_item, another_project_item, item_in_another_project])

      # act
      message = label_delete_message(@user, @label_a)
      response = MemexProjectColumn::Interface::Indexable::Processor::LabelDelete.new(message).update(es_client)
      index.refresh

      # assert
      results = index.search_all({ "query": { "match_all": {} } })
      remaining_label_ids = results.dig("hits", "hits")
        .map { |result_item| result_item["_source"] }
        .map do |item|
          item["field_values"]
            .select { _1["field_type"] == "labels" }
            .map { _1["labels_value"] }.flatten
            .map { _1["id"] }
        end.flatten

      refute remaining_label_ids.include?(@label_a.id)
      assert_equal 2, remaining_label_ids.count { _1 == @label_b.id }

      assert_equal 3, response.updated
    end

    test "removes the field from field_values when the last label is removed" do
      populate_elasticsearch_index!([@project_item])
      doc = get_doc(@project_item.id)
      assert field(doc, @labels_field.id)
      message = label_delete_message(@user, @label_a)

      # When 1 of the 2 labels is destroyed, the field is still present in the index
      @label_a.destroy
      MemexProjectColumn::Interface::Indexable::Processor::LabelDelete.new(message).update(es_client)
      doc = get_doc(@project_item.id)
      assert field(doc, @labels_field.id)

      # When the last label is destroyed, the field is removed from the index
      message = label_delete_message(@user, @label_b)
      @label_b.destroy
      @index.refresh
      MemexProjectColumn::Interface::Indexable::Processor::LabelDelete.new(message).update(es_client)
      doc = get_doc(@project_item.id)
      refute field(doc, @labels_field.id)
    end
  end

  context "project_ids_to_resync_on_failure" do
    test "provides correct project ids for resyncing on failure", es_8_only: true do
      issue = create(:issue, repository: @repo, assignee: @user).tap { |issue| issue.labels << @label_a }
      item_in_another_project = create(:memex_project_item, content: issue)
      populate_elasticsearch_index!([@project_item, item_in_another_project])

      message = label_delete_message(@user, @label_a)
      processor = MemexProjectColumn::Interface::Indexable::Processor::LabelDelete.new(message)
      assert_equal [@project.id, item_in_another_project.memex_project_id].sort, processor.project_ids_to_resync_on_failure.sort
    end
  end

  context "updated_models" do
    test "provides correct updated models" do
      message = label_delete_message(@user, @label_a)
      processor = MemexProjectColumn::Interface::Indexable::Processor::LabelDelete.new(message)
      assert_empty processor.updated_models
    end
  end

  context "#dependent_mysql_replication_cluster" do
    test "returns the Issues cluster" do
      message = label_delete_message(@user, @label_a)
      processor = MemexProjectColumn::Interface::Indexable::Processor::LabelDelete.new(message)
      assert_equal Issue.cluster_name, processor.dependent_mysql_replication_cluster
    end
  end

  context "#canonical_data_present?" do
    test "returns true when the label is deleted" do
      message = label_delete_message(@user, @label_a)
      @label_a.delete

      passes_through_canonical_data_gate = MemexProjectColumn::Interface::Indexable::Processor::LabelDelete.new(message).canonical_data_present?
      assert passes_through_canonical_data_gate
    end

    test "returns false when the label is not deleted" do
      message = label_delete_message(@user, @label_a)

      passes_through_canonical_data_gate = MemexProjectColumn::Interface::Indexable::Processor::LabelDelete.new(message).canonical_data_present?
      refute passes_through_canonical_data_gate
    end
  end


  private

  def label_delete_message(user = @actor, label = @label_a)
    build_message(
      {
        actor: Hydro::EntitySerializer.user(user),
        label: Hydro::EntitySerializer.label(label)
      },
      schema: "hydro.schemas.github.v1.LabelDelete"
    )
  end
end
