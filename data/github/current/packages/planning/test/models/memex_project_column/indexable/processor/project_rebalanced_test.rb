# typed: true
# frozen_string_literal: true

require "test_helper"

class ProjectRebalancedTest < GitHub::TestCase
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
    @closed_issue = create(:issue, repository: @repo,  state: "closed")
    @pull = create(:pull_request, :disable_disk_access, repository: @repo)
    @issue_items = [
      @open_issue,
      @pull,
      @closed_issue,
    ].map.with_index do |content, n|
      create(
        :memex_project_item,
        content: content, memex_project: @project, repository: @repo,
        priority: n + 1, priority_numerator: 2 * n + 1, priority_denominator: 3,
      )
    end
  end

  setup do
    setup_search
    @index = Elastomer::Indexes::MemexProjectItems.new
  end

  context "#subscriptions" do
    test "invoked in response to a project rebalanced event" do
      assert_consumes(MemexProjectColumn::Indexable::Processor::ProjectRebalanced, "github.prioritizable.v0.PrioritizableContextRebalanced") do
        @project.rebalance!(association: :memex_project_items, mode: GitHub::Prioritizable::Context::RebalanceMode::Dual)
      end
    end
  end

  context "#update" do
    test "updates items with rebalanced priorities" do
      populate_elasticsearch_index!(@issue_items)
      initial_priorities = @issue_items.map(&:stringified_virtual_priority)

      reset_hydro
      @project.rebalance!(association: :memex_project_items, mode: GitHub::Prioritizable::Context::RebalanceMode::Dual)
      run_processor(Projects::DenormalizationProcessor.new)

      @index.refresh
      @issue_items.map { |item| get_doc(item.id)["_source"]["virtual_priority"] }.tap do |result|
        refute_equal initial_priorities, result
        assert result.all?(&:present?)
      end
    end

    test "updates in batches" do
      project = create(:memex_project, owner: @actor, title: "batch project")
      project_items = 6.times.map { |n| create(:memex_project_item, memex_project: project, priority: n + 1) }

      populate_elasticsearch_index!(project_items)

      assert project_items.all? { |item| get_doc(item.id)["_source"]["virtual_priority"].nil? }

      MemexProjectColumn::Indexable::Processor::ProjectRebalanced.stub_const(:BATCH_SIZE, 5) do
        reset_hydro
        project.rebalance!(association: :memex_project_items, mode: GitHub::Prioritizable::Context::RebalanceMode::Dual)
        run_processor(Projects::DenormalizationProcessor.new)

        @index.refresh

        # verifies the first batch of 5 items were updated correctly
        5.times.map { |n| get_doc(project_items[n].id)["_source"]["virtual_priority"] }.tap do |result|
          assert result.all?(&:present?)
        end

        # verfies the last batch of 1 item was updated correctly
        last_es_project_item = get_doc(project_items.last.id)
        assert last_es_project_item["_source"]["virtual_priority"].present?
      end
    end

    context "filters and combines responses" do
      test "does not remove successful updates from bulk responses" do
        project = create(:memex_project, owner: @actor)
        project_items = 6.times.map { create(:memex_project_item, memex_project: project) }

        populate_elasticsearch_index!(project_items)

        message = prioritizable_context_rebalanced_message(context_id: project.id, context_type: ::MemexProject.name)
        processor = MemexProjectColumn::Indexable::Processor::ProjectRebalanced.new(message)

        assert processor
        processor.update(es_client).tap do |response|
          response_data = response.first

          refute response_data.errors
          assert_equal project_items.size, response_data.items.size
        end
      end

      test "filters all failures from the update response" do
        project = create(:memex_project, owner: @actor)
        item = create(:memex_project_item, memex_project: project)

        populate_elasticsearch_index!([item])

        document_update_failure = {
          "update" => {
            "status" => 404,
            "error" => { "type" => "document_missing_exception" },
            "_index" => "",
          }
        }

        document_updates = {
          "took" => 1,
          "errors" => false,
          "items" => [
            document_update_failure,
            document_update_failure,
            document_update_failure,
          ]
        }

        reset_hydro

        message = prioritizable_context_rebalanced_message(context_id: project.id, context_type: ::MemexProject.name)
        rebalanced_processor = processor.new(message)

        ElastomerClient::Client::Docs.any_instance.stubs(:bulk).returns(document_updates)
        rebalanced_processor.stubs(:memex_project_items).returns([])

        rebalanced_processor.update(es_client).tap do |response|
          response_data = response.first

          refute response_data.errors
          assert_empty response_data.items
        end
      end

      test "removes document_missing_exception errors from the final bulk update response" do
        project = create(:memex_project, owner: @actor)
        item = create(:memex_project_item, memex_project: project)

        populate_elasticsearch_index!([item])

        document_update_failure = {
          "update" => {
            "status" => 404,
            "error" => { "type" => "document_missing_exception" },
            "_index" => "",
          }
        }

        document_updates = {
          "took" => 1,
          "errors" => false,
          "items" => [
            # Actual document details excluded for brevity...
            { "update" => { "status" => 200, "_index" => "" } },
            document_update_failure,
            { "update" => { "status" => 200, "_index" => "" } },
          ]
        }

        reset_hydro

        message = prioritizable_context_rebalanced_message(context_id: project.id, context_type: ::MemexProject.name)
        rebalanced_processor = processor.new(message)

        ElastomerClient::Client::Docs.any_instance.stubs(:bulk).returns(document_updates)
        rebalanced_processor.stubs(:memex_project_items).returns([])

        rebalanced_processor.update(es_client).tap do |response|
          response_data = response.first

          assert response_data
          refute response_data.errors
          assert_equal document_updates["items"].size - 1, response_data.items.size
          refute response_data.items.any? { |item| item.update.status == 404 }
        end
      end

      test "does not remove other exception types from the final bulk update response" do
        project = create(:memex_project, owner: @actor)
        item = create(:memex_project_item, memex_project: project)

        populate_elasticsearch_index!([item])

        document_update_failure = {
          "update" => {
            "status" => 404,
            "error" => { "type" => "other_404_exception" },
            "_index" => "",
          }
        }

        document_updates = {
          "took" => 1,
          "errors" => false,
          "items" => [
            # Actual document details excluded for brevity...
            { "update" => { "status" => 200, "_index" => "" } },
            document_update_failure,
            { "update" => { "status" => 200, "_index" => "" } },
          ]
        }

        reset_hydro

        message = prioritizable_context_rebalanced_message(context_id: project.id, context_type: ::MemexProject.name)
        rebalanced_processor = processor.new(message)

        ElastomerClient::Client::Docs.any_instance.stubs(:bulk).returns(document_updates)
        rebalanced_processor.stubs(:memex_project_items).returns([])

        rebalanced_processor.update(es_client).tap do |response|
          response_data = response.first
          assert response_data.errors
          assert_equal document_updates["items"].size, response_data.items.size
          assert response_data.items.any? { |item| item.update.status == 404 }
        end
      end
    end
  end

  context "#valid_message?" do
    test "returns true when the message contains a valid context" do
      message = prioritizable_context_rebalanced_message(context_id: @project.id, context_type: ::MemexProject.name)
      assert MemexProjectColumn::Indexable::Processor::ProjectRebalanced.new(message).valid_message?
    end

    test "returns false when the message contains a context type not equal to MemexProject" do
      message = prioritizable_context_rebalanced_message(context_id: @project.id, context_type: ::Milestone.name)
      refute MemexProjectColumn::Indexable::Processor::ProjectRebalanced.new(message).valid_message?
    end
  end

  context "#matching_elasticsearch_documents?" do
    test "returns true when the project referenced by context_id points to one or more documents in ElasticSearch" do
      populate_elasticsearch_index!(@issue_items)
      message = prioritizable_context_rebalanced_message(context_id: @project.id, context_type: ::MemexProject.name)
      assert MemexProjectColumn::Indexable::Processor::ProjectRebalanced.new(message).matching_elasticsearch_documents?
    end

    test "returns false when the project referenced by context_id does not point to any documents in ElasticSearch" do
      project = create(:memex_project, owner: @actor, title: "es project")
      message = prioritizable_context_rebalanced_message(context_id: project.id, context_type: ::MemexProject.name)
      refute MemexProjectColumn::Indexable::Processor::ProjectRebalanced.new(message).matching_elasticsearch_documents?
    end
  end

  context "#canonical_data_present?" do
    test "returns true when the project referenced by context_id is not empty" do
      message = prioritizable_context_rebalanced_message(context_id: @project.id, context_type: ::MemexProject.name)
      assert MemexProjectColumn::Indexable::Processor::ProjectRebalanced.new(message).canonical_data_present?
    end

    test "returns false when the project referenced by context_id is empty" do
      project = create(:memex_project, owner: @actor, title: "test project")
      message = prioritizable_context_rebalanced_message(context_id: project.id, context_type: ::MemexProject.name)
      refute MemexProjectColumn::Indexable::Processor::ProjectRebalanced.new(message).canonical_data_present?
    end
  end

  private def processor
    MemexProjectColumn::Indexable::Processor::ProjectRebalanced
  end

  private def prioritizable_context_rebalanced_message(context_id:, context_type:)
    build_message(
      {
        context_id:,
        context_type:,
        actor: Hydro::EntitySerializer.user(@actor),
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        performed_at: Time.now
      },
      schema: "github.prioritizable.v0.PrioritizableContextRebalanced"
    )
  end
end
