# typed: true
# frozen_string_literal: true
require "test_helper"

class IssueUpdateLabelsTest < GitHub::TestCase
  include MemexHelpers
  include HydroTestHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    @actor = create(:user)
    @repo = create(:repository, owner: @actor)
    @user = create(:user)
    @repo.add_member(@user)
    @label = create(:label, repository: @repo)
    @other_label = create(:label, repository: @repo)
    @project = create(:memex_project, owner: @actor, title: "test project")
    @issue = create(:issue, repository: @repo)
    @labels_field = @project.columns.find(&:labels?).to_field
  end

  context "#subscriptions" do
    test "invoked on update labels event" do
      project_item = create(:memex_project_item, content: @issue, memex_project: @project)
      reset_hydro

      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateLabels, "github.v1.IssueUpdateLabel") do
        @issue.add_labels(@label)
      end
    end
  end

  context "project_ids_to_resync_on_failure" do
    test "provides correct project ids for resyncing on failure" do
      issue = create(:issue, repository: @repo, state: "open")
      create(:memex_project_item, memex_project: @project, content: issue)
      project_2 = create(:memex_project)
      create(:memex_project_item, memex_project: project_2, content: issue)
      issue.add_labels [@label]

      message = issue_update_labels_message(issue: issue, labels: issue.labels)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateLabels.new(message)
      assert_equal [@project.id, project_2.id].sort, processor.project_ids_to_resync_on_failure.sort
    end
  end

  context "updated_models" do
    test "provides correct models" do
      issue = create(:issue, repository: @repo, state: "open")
      item_1 = create(:memex_project_item, memex_project: @project, content: issue)
      project_2 = create(:memex_project)
      item_2 = create(:memex_project_item, memex_project: project_2, content: issue)
      issue.add_labels [@label]

      message = issue_update_labels_message(issue: issue, labels: issue.labels)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateLabels.new(message)
      assert_same_elements [issue, item_1, item_2], processor.updated_models
    end
  end

  context "#update" do
    test "updates with new label", es_8_only: true do
      project_item = create(:memex_project_item, content: @issue, memex_project: @project)
      populate_elasticsearch_index!([project_item])

      @issue.add_labels(@label)

      message = issue_update_labels_message(issue: @issue, labels: [@label])
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateLabels.new(message)
      response = processor.update(es_client)

      successes = response.items.map(&:update).filter_map { |r| r&.status == 200 }
      assert_equal 1, successes.size

      doc = get_doc(project_item.id)
      field_value = field_value(doc, @labels_field)
      assert field_value.find { _1["id"] == @label.id }
    end

    test "updates with 1 removed label but keeps the other in place", es_8_only: true do
      labeled_issue = create(:issue, repository: @repo)
      label_2 = create(:label, repository: @repo)
      labeled_issue.add_labels([@label, label_2])
      project_item = create(:memex_project_item, content: labeled_issue, memex_project: @project)
      populate_elasticsearch_index!([project_item])
      doc = get_doc(project_item.id)
      field_value = field_value(doc, @labels_field)
      [@label, label_2].each do |label|
        assert field_value.find { _1["id"] == label.id }
      end

      labeled_issue.delete_labels [label_2]

      message = issue_update_labels_message(issue: labeled_issue, labels: [], unlabeled: true)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateLabels.new(message)
      response = processor.update(es_client)
      successes = response.items.map(&:update).filter_map { |r| r&.status == 200 }
      assert_equal 1, successes.size

      doc = get_doc(project_item.id)
      field_value = field_value(doc, @labels_field)
      assert field_value.find { _1["id"] == @label.id }
      refute field_value.find { _1["id"] == label_2.id }

    end

    test "removes field from field_values when last label removed", es_8_only: true do
      labeled_issue = create(:issue, repository: @repo)
      labeled_issue.add_labels([@label])
      project_item = create(:memex_project_item, content: labeled_issue, memex_project: @project)
      populate_elasticsearch_index!([project_item])

      labeled_issue.delete_labels [@label]

      message = issue_update_labels_message(issue: labeled_issue, labels: [], unlabeled: true)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateLabels.new(message)
      response = processor.update(es_client)
      successes = response.items.map(&:update).filter_map { |r| r&.status == 200 }
      assert_equal 1, successes.size

      doc = get_doc(project_item.id)
      refute field(doc, @labels_field.id)
    end

    test "noops when matching value already found in any order", es_8_only: true do
      issue = create(:issue, repository: @repo)
      issue.add_labels [@label, @other_label]
      issue.save!
      project_item = create(:memex_project_item, content: issue, memex_project: @project)
      populate_elasticsearch_index!([project_item])

      labels = [@label, @other_label]
      message = issue_update_labels_message(issue: issue, labels: labels)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateLabels.new(message)
      response = processor.update(es_client)
      noops = response.items.map(&:update).filter_map { |r| r&.result&.serialize == "noop" }
      assert_equal 1, noops.size

      message = issue_update_labels_message(issue: issue, labels: labels.reverse)
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateLabels.new(message)
      response = processor.update(es_client)
      noops = response.items.map(&:update).filter_map { |r| r&.result&.serialize == "noop" }
      assert_equal 1, noops.size
    end

    test "raises CanonicalDataMissingError when no related items are found" do
      message = issue_update_labels_message(issue: @issue, labels: [@label])
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateLabels.new(message)
      assert_raises MemexProjectColumn::Interface::Indexable::CanonicalDataMissingError do
        processor.update(es_client)
      end
    end
  end

  context "#dependent_mysql_replication_cluster" do
    test "returns the Issues cluster" do
      message = issue_update_labels_message(issue: @issue, labels: [@label])
      processor = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateLabels.new(message)
      assert_equal Issue.cluster_name, processor.dependent_mysql_replication_cluster
    end
  end

  context "#canonical data fetching" do
    test "returns true when model is present" do
      message = issue_update_labels_message(issue: @issue, labels: [@label])

      passes_through_canonical_data_gate = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateLabels.new(message).canonical_data_present?
      assert passes_through_canonical_data_gate
    end

    test "returns false when the model is not present" do
      message = issue_update_labels_message(issue: @issue, labels: [@label])
      @issue.delete
      passes_through_canonical_data_gate = MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateLabels.new(message).canonical_data_present?
      refute passes_through_canonical_data_gate
    end
  end

  context "#matching elasticsearch documents" do
    test "returns true when there are matching documents" do
      labeled_issue = create(:issue, repository: @repo)
      labeled_issue.add_labels([@label])
      project_item = create(:memex_project_item, content: labeled_issue, memex_project: @project)
      populate_elasticsearch_index!([project_item])

      message = issue_update_labels_message(issue: labeled_issue, labels: [@label])

      assert MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateLabels.new(message).matching_elasticsearch_documents?
    end

    test "returns false when there are no matching documents" do
      labeled_issue = create(:issue, repository: @repo)
      labeled_issue.add_labels([@label])
      project_item = create(:memex_project_item, content: labeled_issue, memex_project: @project)
      populate_elasticsearch_index!([project_item])

      # A message with a different issue in the body
      message = issue_update_labels_message(issue: @issue, labels: [@label])

      refute MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateLabels.new(message).matching_elasticsearch_documents?

    end
  end

  def issue_update_labels_message(issue:, labels:, pull: nil, unlabeled: false)
    build_message(
      {
        actor: Hydro::EntitySerializer.user(@actor),
        repository: Hydro::EntitySerializer.repository(@repo),
        issue: Hydro::EntitySerializer.issue(issue),
        pull_request: Hydro::EntitySerializer.pull_request(pull),
        labels: labels.map { |label| Hydro::EntitySerializer.label(label) },
        action: unlabeled ? "issue.events.unlabeled" : "issue.events.labeled"
      },
      schema: "github.v1.IssueUpdateLabel"
    )
  end
end
