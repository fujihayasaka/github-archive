# typed: true
# frozen_string_literal: true

require "test_helper"

class ProcessProjectItemTest < GitHub::TestCase
  include HydroTestHelpers
  include MemexHelpers
  include ProjectsProcessorTestHelpers

  fixtures do
    @actor = create(:user)
    @repo = create(:repository, owner: @actor)
    @user = create(:user)
    @repo.add_member(@user)
    @open_issue = create(:issue, repository: @repo,  state: "open")
    @closed_issue = create(:issue, repository: @repo,  state: "closed")
  end

  setup do
    setup_search
    @index = Elastomer::Indexes::MemexProjectItems.new
    @es_client = Search::Memex::Client.new(@index)
  end

  context "#subscriptions" do
    test "invoked in response to a project item create event" do
      project = create(:memex_project, owner: @actor, title: "test project")
      project_item = build(:memex_project_item, memex_project: project, content: @open_issue, repository: @repo)
      reset_hydro

      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::ProcessProjectItem, "github.memex.v0.ProjectItemCreate") do
        project.prioritize_dependent!(
          project_item,
          dual_write: project.prioritize(
            item: project_item,
            position: GitHub::Prioritizable::SBT::Position.from_options(position: :top),
            association: :memex_project_items,
          ),
        )
      end
    end

    test "invoked in response to convert to issue event" do
      draft_issue = create(:draft_issue)
      project = create(:memex_project, owner: @actor, title: "test project")
      project_item = create(:memex_project_item, memex_project: project, content: draft_issue, repository: @repo)

      populate_elasticsearch_index!([project_item])
      reset_hydro

      assert_consumes(MemexProjectColumn::Interface::Indexable::Processor::ProcessProjectItem, "github.memex.v0.DraftIssueConvertToIssue") do
        MemexProjectItem::ConvertToIssue.call(memex_project_item: project_item, actor: @actor, repository: @repo)
      end
    end
  end

  context "#update" do
    context "#project item create" do
      test "adds new project item to the index", es_8_only: true do
        project_item = create(:memex_project_item)
        message = item_create_message(project_item)
        response = MemexProjectColumn::Interface::Indexable::Processor::ProcessProjectItem.new(message).update(@es_client)
        assert_equal Elastomer::Interfaces::Api::Update::Response::Result::Created, response.result
      end

      test "noops if document already exists", es_8_only: true do
        project_item = create(:memex_project_item)
        populate_elasticsearch_index!([project_item])

        message = item_create_message(project_item)
        response = MemexProjectColumn::Interface::Indexable::Processor::ProcessProjectItem.new(message).update(@es_client)
        assert_equal Elastomer::Interfaces::Api::Update::Response::Result::Noop, response.result
      end

      test "forces refresh", es_8_only: true do
        project_item = create(:memex_project_item)
        message = item_create_message(project_item)
        response = MemexProjectColumn::Interface::Indexable::Processor::ProcessProjectItem.new(message).update(@es_client)
        assert_equal true, response.forced_refresh
      end
    end
  end

  context "draft issue conversion" do
    test "updates project item doc content with the converted issue metadata", es_8_only: true do
      draft_issue = create(:draft_issue)
      project = create(:memex_project, owner: @actor, title: "test project")
      project_item = create(:memex_project_item, memex_project: project, content: draft_issue, repository: @repo)

      populate_elasticsearch_index!([project_item])

      current_document_state = get_doc(project_item.id)["_source"]
      assert_equal "DraftIssue", current_document_state["content"]["type"]
      assert current_document_state["content"]["is_draft"]

      reset_hydro

      MemexProjectItem::ConvertToIssue.call(memex_project_item: project_item, actor: @actor, repository: @repo)
      assert_hydro_messages(count: 1, schema: "github.memex.v0.DraftIssueConvertToIssue")

      run_processor(Projects::DenormalizationProcessor.new)

      target_result = get_doc(project_item.id)["_source"]
      assert_equal "Issue", target_result["content"]["type"]
      refute target_result["content"]["is_draft"]
    end
  end

  test "provides the correct updated models", es_8_only: true do
    project_item = create(:memex_project_item)
    message = item_create_message(project_item)
    processor = MemexProjectColumn::Interface::Indexable::Processor::ProcessProjectItem.new(message)
    assert_same_elements [project_item], processor.updated_models
  end

  private def item_create_message(item)
    build_message(
      {
        actor: Hydro::EntitySerializer.user(@actor),
        memex_project: Hydro::EntitySerializer.memex_project(item.memex_project),
        memex_project_item: Hydro::EntitySerializer.memex_project_item(item),
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      },
      schema: "github.memex.v0.ProjectItemCreate"
    )
  end
end
