# typed: true
# frozen_string_literal: true

require "test_helper"

module Projects
  module DenormalizationProcessorSharedTest
    extend T::Helpers
    extend ActiveSupport::Concern

    requires_ancestor { DenormalizationProcessorBaseTest }

    included do
      T.bind(self, T.class_of(DenormalizationProcessorBaseTest))

      test "sets a custom max retry count" do
        assert_equal 3, Projects::DenormalizationProcessor.new.send(:transient_error_max_retries)
      end

      test "sets a custom pause duration when flag is set" do
        assert_equal 10.seconds, Projects::DenormalizationProcessor.new.send(:transient_error_pause_duration)
      end

      test "allows setting of the value via env var when value is set" do
        stub_env("MEMEX_DENORMALIZATION_PAUSE_DURATION", "5") do
          assert_equal 5.seconds, Projects::DenormalizationProcessor.new.send(:transient_error_pause_duration)
        end
      end

      test "falls back to const when value is not set" do
        assert_equal 10.seconds, Projects::DenormalizationProcessor.new.send(:transient_error_pause_duration)
      end

      test "falls back to const when value is not compatiable with a duration type" do
        stub_env("MEMEX_DENORMALIZATION_PAUSE_DURATION", "dowhat?") do
          assert_equal 10.seconds, Projects::DenormalizationProcessor.new.send(:transient_error_pause_duration)
        end
      end

      context "#process_message" do
        test "skips messages that do not match any documents in Elasticsearch", es_8_only: true do
          assert_equal 0, @index.count_all(content_query(@unaffiliated_issue))

          @unaffiliated_issue.close(@actor)

          run_processor(Projects::DenormalizationProcessor.new)

          assert_message_skipped(MemexProjectColumn::Interface::Indexable::Processor::FailureReason::NO_MATCHING_DOCS)
        end

        test "updates issue state across multiple Elasticsearch documents", es_8_only: true do
          populate_elasticsearch_index!(@issue_items)
          assert_equal 3, @index.count_all(content_query(@issue, state: "open"))

          @issue.close(@actor, attributes: { state_reason: "not_planned" })
          run_processor(Projects::DenormalizationProcessor.new)
          @index.refresh

          assert_message_succeeded
          assert_equal 0, @index.count_all(content_query(@issue, state: "open"))
          assert_equal 3, @index.count_all(content_query(@issue, state: "closed", state_reason: "not_planned"))
        end

        test "updates pull request open/close state across multiple Elasticsearch documents", es_8_only: true do
          populate_elasticsearch_index!(@pull_items)
          assert_equal 2, @index.count_all(content_query(@pull, state: "open"))

          @pull.close(@actor)
          run_processor(Projects::DenormalizationProcessor.new)
          @index.refresh

          assert_message_succeeded
          assert_equal 0, @index.count_all(content_query(@pull, state: "open"))
          assert_equal 2, @index.count_all(content_query(@pull, state: "closed"))
        end

        test "updates pull request draft state across multiple Elasticsearch documents", es_8_only: true do
          populate_elasticsearch_index!(@pull_items)
          assert_equal 0, @index.count_all(content_query(@pull, is_draft: true))

          @pull.convert_to_draft(user: @actor)
          run_processor(Projects::DenormalizationProcessor.new)
          @index.refresh

          assert_message_succeeded
          assert_equal 2, @index.count_all(content_query(@pull, is_draft: true))
        end

        test "reports version conflicts", es_8_only: true do
          enable_feature_flag(:memex_resync_on_conflict)
          issue = create(:issue, repository: @repo)
          create(:memex_project_item, memex_project: @memex, content: issue)
          example_schema = "github.v1.PullRequestMerge"
          message = build_message({}, schema: example_schema)
          indexable_processor = DenormalizationProcessorBaseTest::TestProcessorReturnsVersionConflict.new(message)

          MemexProjectColumn::Interface::Indexable::Processor.expects(:for_message).returns([indexable_processor])

          processor = Projects::DenormalizationProcessor.new
          processor
            .expects(:start_resync_job!)
            .with(has_entries(
              message: message,
              exception: instance_of(Projects::DenormalizationProcessor::VersionConflictError),
              processor: indexable_processor,
            ))

          processor.process_message(message)

          assert_dogstats_increment(
            prefixed_metric("version_conflict"),
            tags: ["topic:#{example_schema}", "scope:S"]
          )
        end

        test "recovers from an Elastomer client request failure by kicking off a resync job", es_8_only: true do
          issue = create(:issue, repository: @repo)
          create(:memex_project_item, memex_project: @memex, content: issue)

          # Emulate a server error (status: 500)
          expected_exception = ElastomerClient::Client::ServerError.new
          ElastomerClient::Client.any_instance.stubs(:post).raises(expected_exception)

          process_messages!
          assert_enqueued_with(job: ResyncMemexProjectItemsIndexJob)
        end

        test "logs and fails silently if no project ids are found to resync", es_8_only: true do
          example_schema = "github.v1.PullRequestMerge"
          message = build_message({}, schema: example_schema)

          expected_exception = ElastomerClient::Client::ServerError
          DenormalizationProcessorBaseTest::TestProcessorProvidesNoProjectIds
            .any_instance
            .expects(:matching_elasticsearch_documents?)
            .raises(expected_exception)

          MemexProjectColumn::Interface::Indexable::Processor.expects(:for_message).returns([
            DenormalizationProcessorBaseTest::TestProcessorProvidesNoProjectIds.new(message)
          ])

          processor = Projects::DenormalizationProcessor.new
          expected_log_keys = {
            Body: "No project ids to resync",
            "exception.type": expected_exception.name,
          }
          assert_logged(**expected_log_keys) do
            processor.process_message(message)
          end
        end

        test "logs job status and remaining tries", es_8_only: true do
          example_schema = "github.v1.PullRequestMerge"
          message = build_message({}, schema: example_schema)
          processor = DenormalizationProcessorBaseTest::TestProcessorReturnsVersionConflict.new(message)
          MemexProjectColumn::Interface::Indexable::Processor.expects(:for_message).returns([processor])
          processor.expects(:matching_elasticsearch_documents?).raises(StandardError)

          status = ResyncMemexProjectItemsIndexJobStatus.create(123)
          status.error!
          ResyncMemexProjectItemsIndexJobStatus.expects(:create).returns(status).times(3)

          expected_log_keys = {
            "gh.memex.denormalization_processor.tries_remaining" => 2,
            "gh.memex.resync_memex_project_items_index_job.status" => status.to_json,
          }
          assert_raises(StandardError) do
            assert_logged(**expected_log_keys) do
              Projects::DenormalizationProcessor.new.process_message(message)
            end
          end
        end

        test "logs project ids for resyncing", es_8_only: true do
          issue = create(:issue, repository: @repo)
          project_item = create(:memex_project_item, memex_project: @memex, content: issue)

          # Emulate a server error (status: 500)
          expected_exception = ElastomerClient::Client::ServerError.new
          ElastomerClient::Client.any_instance.stubs(:post).raises(expected_exception)

          expected_log_keys = {
            "gh.memex.denormalization_processor.context" => [project_item.memex_project_id],
            "code.function" => "start_resync_job!"
          }

          assert_logged(**expected_log_keys) do
            process_messages!
          end
        end

        test "starts resync job if processor project ids are found", es_8_only: true do
          example_schema = "github.v1.PullRequestMerge"
          message = build_message({}, schema: example_schema)
          test_processor = DenormalizationProcessorBaseTest::TestProcessorProvidesNoProjectIds.new(message)
          expected_exception = ElastomerClient::Client::ServerError

          test_processor
            .expects(:matching_elasticsearch_documents?)
            .raises(expected_exception)

          test_processor
            .expects(:project_ids_to_resync_on_failure)
            .returns([@memex.id])

          MemexProjectColumn::Interface::Indexable::Processor.expects(:for_message).returns([test_processor])

          Projects::DenormalizationProcessor.new.process_message(message)
          assert_enqueued_with(job: ResyncMemexProjectItemsIndexJob, args: -> (job_args) { job_args[0] == @memex.id })
        end

        test "broadcasts live updates for relevant results" do
          example_schema = "github.v1.PullRequestMerge"
          message = build_message({}, schema: example_schema)

          processors = [
            DenormalizationProcessorBaseTest::TestProcessor.new(message),
            DenormalizationProcessorBaseTest::TestProcessorDoesNotBroadcastResult.new(message),
          ]

          MemexProjectColumn::Interface::Indexable::Processor.expects(:for_message).returns(processors)

          dispatcher = Projects::DenormalizationProcessor.new
          dispatcher.expects(:broadcast_live_update).with do |kwargs|
            assert_equal ["TestProcessor"], kwargs[:results].map { |r| r.outcome.dig("_raw", 0, "_id") }
          end

          dispatcher.process_message(message)
        end

        test "does not broadcast live updates at all if everyone declines them" do
          example_schema = "github.v1.PullRequestMerge"
          message = build_message({}, schema: example_schema)

          processors = [
            DenormalizationProcessorBaseTest::TestProcessorDoesNotBroadcastResult.new(message),
          ]

          MemexProjectColumn::Interface::Indexable::Processor.expects(:for_message).returns(processors)

          dispatcher = Projects::DenormalizationProcessor.new
          dispatcher.expects(:broadcast_live_update).with do |kwargs|
            assert_equal 0, kwargs[:results].length
          end

          dispatcher.process_message(message)
        end
      end

      context "replicating waiting" do
        test "replication error pauses processor", es_8_only: true do
          # Avoid WaitForReplication#wait! being invoked via LogAuditEntryJob performed inline
          GitHub.audit.stubs(:inline?).returns(false)

          processor = Projects::DenormalizationProcessor.new(rescue_from_standard_error: true)
          populate_elasticsearch_index!(@pull_items)

          WaitForReplication
            .any_instance
            .expects(:wait!)
            .raises(
              WaitForReplication::DataUnavailable.new(
                store_name: Issue.cluster_name,
                wait_required: 5.0,
                max_wait: 8.0
              )
            )

          @pull.close(@actor)
          assert_raises(GitHub::StreamProcessors::ProcessorPausedError) do
            run_processor(processor)
          end
        end

        test "replication error from a column settings change pauses processor", es_8_only: true do
          processor = Projects::DenormalizationProcessor.new(rescue_from_standard_error: true)

          WaitForReplication
            .any_instance
            .expects(:wait!)
            .raises(
              WaitForReplication::DataUnavailable.new(
                store_name: MemexProjectColumnValue.cluster_name,
                wait_required: 5.0,
                max_wait: 8.0
              )
            )

          single_select_option = @single_select_field.settings["options"].first
          project_item = @issue_items[0]
          project_item.set_column_value(@single_select_field, single_select_option["id"], @actor)
          populate_elasticsearch_index!([project_item])
          reset_hydro

          single_select_option["name"] = "#{single_select_option} and more!"
          @single_select_field.save

          assert_raises(::GitHub::StreamProcessors::ProcessorPausedError) do
            run_processor(processor)
          end

          assert processor.paused?
        end

        test "issue update assignee waits for replication", es_8_only: true do
          processor = Projects::DenormalizationProcessor.new(rescue_from_standard_error: false)
          populate_elasticsearch_index!(@issue_items)

          WaitForReplication
            .any_instance
            .expects(:wait!)
            .raises(
              WaitForReplication::DataUnavailable.new(
                store_name: Issue.cluster_name,
                wait_required: 5.0,
                max_wait: 8.0
              )
            )

          reset_hydro
          @issue.assignees = [@actor]

          assert_raises(WaitForReplication::DataUnavailable) do
            run_processor(processor)
          end
        end

        test "content processor waits for replication", es_8_only: true do
          # Avoid WaitForReplication#wait! being invoked via LogAuditEntryJob performed inline
          GitHub.audit.stubs(:inline?).returns(false)

          processor = Projects::DenormalizationProcessor.new(rescue_from_standard_error: false)
          populate_elasticsearch_index!(@pull_items)

          WaitForReplication
            .any_instance
            .expects(:wait!)
            .raises(
              WaitForReplication::DataUnavailable.new(
                store_name: Issue.cluster_name,
                wait_required: 5.0,
                max_wait: 8.0
              )
            )

          reset_hydro
          @pull.close

          assert_raises(WaitForReplication::DataUnavailable) do
            run_processor(processor)
          end
        end

        test "project item processor waits for replication", es_8_only: true do
          # Avoid WaitForReplication#wait! being invoked via LogAuditEntryJob performed inline
          GitHub.audit.stubs(:inline?).returns(false)

          processor = Projects::DenormalizationProcessor.new(rescue_from_standard_error: false)

          WaitForReplication
            .any_instance
            .expects(:wait!)
            .raises(
              WaitForReplication::DataUnavailable.new(
                store_name: Issue.cluster_name,
                wait_required: 5.0,
                max_wait: 8.0
              )
            )

          reset_hydro
          create(:memex_project_item)

          assert_raises(WaitForReplication::DataUnavailable) do
            run_processor(processor)
          end
        end

        test "account rename processor waits for replication", es_8_only: true do
          processor = Projects::DenormalizationProcessor.new(rescue_from_standard_error: false)

          issue = create(:assigned_issue, repository: @repo, assignee: @actor)
          user = issue.assignee
          project_item = create(:memex_project_item, content: issue, memex_project: @memex)
          populate_elasticsearch_index!([project_item])

          suffix = @business&.shortcode ? "_#{@business.shortcode}" : ""
          new_login = "hello#{suffix}"
          reset_hydro
          rename_account(user, new_login)

          WaitForReplication
            .any_instance
            .expects(:wait!)
            .raises(
              WaitForReplication::DataUnavailable.new(
                store_name: Issue.cluster_name,
                wait_required: 5.0,
                max_wait: 8.0
              )
            )

          assert_raises(WaitForReplication::DataUnavailable) do
            run_processor(processor)
          end
        end
      end

      test "indexes project item on create", es_8_only: true do
        project_item = create(:memex_project_item)
        result = get_doc(project_item.id)
        refute result["found"]

        process_messages!

        result = get_doc(project_item.id)
        assert result["found"]
      end

      test "skips invalid project item messages", es_8_only: true do
        # This message is missing the required item ID attribute.
        invalid_message = build_message({}, schema: "github.memex.v0.ProjectItemCreate")

        processor = Projects::DenormalizationProcessor.new
        processor.process_message(invalid_message)

        assert invalid_message.skipped?
        assert_equal invalid_message.cause, MemexProjectColumn::Interface::Indexable::Processor::FailureReason::MESSAGE_IGNORED
      end

      test "updates project item doc when a single-select column value changes in ES5", es_8_only: true, es_5_only: true do
        project_item = create(:memex_project_item, memex_project: @memex)
        populate_elasticsearch_index!([project_item])

        single_select_option = @single_select_field.settings["options"].first
        project_item.set_column_value(@single_select_field, single_select_option["id"], @actor)

        result = get_doc(project_item.id)
        refute field_value(result, @single_select_field)

        process_messages!

        result = get_doc(project_item.id)
        assert_equal field_value(result, @single_select_field), single_select_option.slice("id", "name")
      end

      test "updates project item doc when a single-select column value changes in ES8", es_8_only: true do
        project_item = create(:memex_project_item, memex_project: @memex)
        populate_elasticsearch_index!([project_item])

        single_select_option = @single_select_field.settings["options"].first
        project_item.set_column_value(@single_select_field, single_select_option["id"], @actor, skip_elasticsearch_updates: true)

        result = get_doc(project_item.id)
        refute field(result, @single_select_field.id)

        process_messages!

        result = get_doc(project_item.id)
        assert_equal field_value(result, @single_select_field), single_select_option.slice("id", "name")
      end

      test "removes single select field value when a matching column value is destroyed", es_8_only: true do
        project_item = create(:memex_project_item, memex_project: @memex)
        single_select_option = @single_select_field.settings["options"].first
        project_item.set_column_value(@single_select_field, single_select_option["id"], @actor)
        populate_elasticsearch_index!([project_item])

        reset_hydro

        result = get_doc(project_item.id)
        assert_equal field_value(result, @single_select_field), single_select_option.slice("id", "name")

        project_item.set_column_value(@single_select_field, "", @actor)

        process_messages!

        result = get_doc(project_item.id)
        refute field(result, @single_select_field)
      end

      test "matching item docs are updated when a single-select column's options change", es_8_only: true do
        project_item = @issue_items[0]
        project_item_2 = create(:memex_project_item, memex_project: @memex)
        project_item_3 = create(:memex_project_item, memex_project: @memex)

        # 2 items will have the option we are going to change
        single_select_option = @single_select_field.settings["options"].first
        project_item.set_column_value(@single_select_field, single_select_option["id"], @actor)
        project_item_2.set_column_value(@single_select_field, single_select_option["id"], @actor)

        # 1 item will have a different option that should not change
        single_select_option_2 = @single_select_field.settings["options"].second
        project_item_3.set_column_value(@single_select_field, single_select_option_2["id"], @actor)

        populate_elasticsearch_index!([project_item, project_item_2, project_item_3])
        reset_hydro

        # change the option name
        new_value = "testing/different!"
        single_select_option["name"] = new_value
        @single_select_field.save

        # verify that before running the processor the index shows the old values
        result = get_doc(project_item.id)
        refute_equal field_value(result, @single_select_field), single_select_option.slice("id", "name")
        result = get_doc(project_item_2.id)
        refute_equal field_value(result, @single_select_field), single_select_option.slice("id", "name")
        result = get_doc(project_item_3.id)
        assert_equal field_value(result, @single_select_field), single_select_option_2.slice("id", "name")

        process_messages!

        # validate that after running the processor, the 2 matching items have been updated, while the other has not
        result = get_doc(project_item.id)
        assert_equal field_value(result, @single_select_field), single_select_option.slice("id", "name")
        result = get_doc(project_item_2.id)
        assert_equal field_value(result, @single_select_field), single_select_option.slice("id", "name")
        result = get_doc(project_item_3.id)
        assert_equal field_value(result, @single_select_field), single_select_option_2.slice("id", "name")
      end

      test "creates project item doc field values when a single-select column value changes", es_8_only: true do
        project_item = create(:memex_project_item, memex_project: @memex)
        populate_elasticsearch_index!([project_item])

        single_select_option = @single_select_field.settings["options"].first
        new_value = single_select_option["id"]

        # since the column value is nil, this should trigger a
        # github.memex.v0.MemexProjectColumnValueCreate topic as part of the hydro message
        project_item.set_column_value(@single_select_field, new_value, @actor, skip_elasticsearch_updates: true)

        result = get_doc(project_item.id)
        assert_nil field(result, @single_select_field.id)

        process_messages!

        result = get_doc(project_item.id)
        assert_equal field_value(result, @single_select_field), single_select_option.slice("id", "name")
      end

      test "updates project item doc field values when a single-select column value changes", es_8_only: true do
        project_item = create(:memex_project_item, memex_project: @memex)
        # populate the single select field with a value
        single_select_option_2 = @single_select_field.settings["options"].second
        current_value = single_select_option_2["id"]
        create(:memex_project_column_value, column: @single_select_field, value: current_value, item: project_item)
        populate_elasticsearch_index!([project_item])
        single_select_option_1 = @single_select_field.settings["options"].first
        new_value = single_select_option_1["id"]
        # since the column was previously populated, should trigger a
        # github.memex.v0.MemexProjectColumnValueUpdate topic as part of the hydro message
        project_item.set_column_value(@single_select_field, new_value, @actor, skip_elasticsearch_updates: true)
        result = get_doc(project_item.id)
        assert_equal field_value(result, @single_select_field), single_select_option_2.slice("id", "name")
        process_messages!
        result = get_doc(project_item.id)
        assert_equal field_value(result, @single_select_field), single_select_option_1.slice("id", "name")
      end

      test "similar but separate option names are ignored when a single select column's options change", es_8_only: true do
        # This test exercises keyword vs. text matching. In other words, for columns with KeywordMultiField
        # mappings, you can choose to query either by exact match (keyword) or by partial match (text).
        # In our case we want exact/keyword, so this test creates conditions where inexact option matches
        # would get updated if we aren't querying by keyword.
        option_value = "testing"
        similar_value = "testing similar"
        changed_value = "testing changed"


        # Change the name of the single select field's first and second options to be similar to each other
        single_select_option = @single_select_field.settings["options"].first
        single_select_option["name"] = option_value
        single_select_option_2 = @single_select_field.settings["options"].second
        single_select_option_2["name"] = similar_value
        @single_select_field.save

        # Create a project item and set its single select value to the first option
        project_item = create(:memex_project_item, memex_project: @memex)
        project_item.set_column_value(@single_select_field, single_select_option["id"], @actor)

        # Create another project item and set its single select value to the second option
        project_item_2 = create(:memex_project_item, memex_project: @memex)
        project_item_2.set_column_value(@single_select_field, single_select_option_2["id"], @actor)

        populate_elasticsearch_index!([project_item, project_item_2])
        reset_hydro

        # Update the single select field's first option to the new value
        @single_select_field.settings["options"].first["name"] = changed_value
        @single_select_field.save

        process_messages!

        # validate that after running the processor, the first item has been updated with the new value,
        # but the second item still has its original value
        result = get_doc(project_item.id)
        assert_equal field_value(result, @single_select_field), @single_select_field.settings["options"].first.slice("id", "name")
        result = get_doc(project_item_2.id)
        assert_equal field_value(result, @single_select_field), single_select_option_2.slice("id", "name")
      end

      test "matching item docs are updated when multiple options for a single-select column are changed", es_8_only: true do
        project_item = @issue_items[0]
        project_item_2 = create(:memex_project_item, memex_project: @memex)
        project_item_3 = create(:memex_project_item, memex_project: @memex)

        single_select_option = @single_select_field.settings["options"].first
        project_item.set_column_value(@single_select_field, single_select_option["id"], @actor)

        single_select_option_2 = @single_select_field.settings["options"].second
        project_item_2.set_column_value(@single_select_field, single_select_option_2["id"], @actor)

        # 1 item will have a different option that should not change
        single_select_option_3 = @single_select_field.settings["options"].third
        project_item_3.set_column_value(@single_select_field, single_select_option_3["id"], @actor)

        populate_elasticsearch_index!([project_item, project_item_2, project_item_3])
        reset_hydro

        # change the option names
        new_value_1 = "testing different 1"
        single_select_option["name"] = new_value_1
        new_value_2 = "testing different 2"
        single_select_option_2["name"] = new_value_2
        @single_select_field.save

        # verify that before running the processor the index shows the old values
        result = get_doc(project_item.id)
        refute_equal field_value(result, @single_select_field), single_select_option.slice("id", "name")
        result = get_doc(project_item_2.id)
        refute_equal field_value(result, @single_select_field), single_select_option_2.slice("id", "name")

        process_messages!

        # validate that after running the processor, the 2 matching items have been updated
        result = get_doc(project_item.id)
        assert_equal field_value(result, @single_select_field), single_select_option.slice("id", "name")
        result = get_doc(project_item_2.id)
        assert_equal field_value(result, @single_select_field), single_select_option_2.slice("id", "name")

        # validate that the 3rd item has not been updated
        result = get_doc(project_item_3.id)
        assert_equal field_value(result, @single_select_field), single_select_option_3.slice("id", "name")
      end

      test "single-select values are removed when their corresponding option is deleted from column settings", es_8_only: true do
        project_item = @issue_items[0]
        project_item_2 = create(:memex_project_item, memex_project: @memex)

        single_select_option = @single_select_field.settings["options"].first
        project_item.set_column_value(@single_select_field, single_select_option["id"], @actor)
        project_item_2.set_column_value(@single_select_field, single_select_option["id"], @actor)

        populate_elasticsearch_index!([project_item, project_item_2])
        result = get_doc(project_item.id)
        reset_hydro

        # remove the option
        @single_select_field.settings["options"].delete(single_select_option)
        @single_select_field.save

        # verify that before running the processor the index has values
        result = get_doc(project_item.id)
        refute_nil field_value(result, @single_select_field)
        result = get_doc(project_item_2.id)
        refute_nil field_value(result, @single_select_field)

        process_messages!

        # validate that after running the processor, the the values have been removed/nulled
        result = get_doc(project_item.id)
        assert_nil field(result, @single_select_field.id)
        result = get_doc(project_item_2.id)
        assert_nil field(result, @single_select_field.id)
      end

      test "skips column update when single-select settings haven't changed", es_8_only: true do
        project_item = @issue_items[0]

        single_select_option = @single_select_field.settings["options"].first
        project_item.set_column_value(@single_select_field, single_select_option["id"], @actor)

        populate_elasticsearch_index!([project_item])
        reset_hydro

        # change the name but nothing else
        @single_select_field.name = "my new name for testing!"
        @single_select_field.save

        process_messages!

        assert_message_skipped(MemexProjectColumn::Interface::Indexable::Processor::FailureReason::MESSAGE_IGNORED)
      end

      test "skips column update when settings changed for an unsupported column", es_8_only: true do
        iteration_column = create(:iteration_memex_column, memex_project: @memex)
        iteration_options = iteration_column.settings.dig("configuration", "iterations")
        project_item = create(:memex_project_item, memex_project: @memex)
        project_item.set_column_value(iteration_column, iteration_options[0]["id"], @actor)

        populate_elasticsearch_index!([project_item])
        reset_hydro

        old_width = iteration_column["settings"]["width"]
        iteration_column["settings"]["width"] = old_width + 1
        iteration_column.save

        process_messages!

        assert_message_skipped(MemexProjectColumn::Interface::Indexable::Processor::FailureReason::MESSAGE_IGNORED)
      end

      test "single select settings processor skips message when the project is no longer present", es_8_only: true do
        schema = "github.memex.v1.MemexProjectColumnUpdate"
        message = { memex_project: nil }
        hydro_publisher.publish(message, schema: schema, topic: schema)

        process_messages!

        assert_message_skipped(MemexProjectColumn::Interface::Indexable::Processor::FailureReason::MESSAGE_IGNORED)
      end

      test "updates project item doc when a column is added and then populated", es_8_only: true do
        project_item = @issue_items[0]
        populate_elasticsearch_index!([project_item])

        value = "bar"
        text_field = create(:memex_project_column, memex_project: @memex, user_defined: true, data_type: :text).to_field
        project_item.set_column_value(text_field, value, @actor, skip_elasticsearch_updates: true)
        result = get_doc(project_item.id)
        refute field(result, text_field.id)

        process_messages!
        result = get_doc(project_item.id)
        assert_equal field_value(result, text_field), value
      end

      test "removes text field value when a matching column value is destroyed", es_8_only: true do
        project_item = create(:memex_project_item, memex_project: @memex)

        new_value = "bar"
        project_item.set_column_value(@text_field, new_value, @actor)
        populate_elasticsearch_index!([project_item])

        reset_hydro

        result = get_doc(project_item.id)
        assert_equal field_value(result, @text_field), new_value

        project_item.set_column_value(@text_field, "", @actor)

        process_messages!

        result = get_doc(project_item.id)
        refute field(result, @text_field)
      end

      test "updates project item doc when a column is added and then populated in ES8", es_8_only: true do
        project_item = create(:memex_project_item, memex_project: @memex)
        populate_elasticsearch_index!([project_item])

        value = "bar"
        text_field = create(:memex_project_column, memex_project: @memex, user_defined: true, data_type: :text).to_field
        project_item.set_column_value(text_field, value, @actor, skip_elasticsearch_updates: true)
        result = get_doc(project_item.id)
        refute field(result, text_field.id)

        process_messages!
        result = get_doc(project_item.id)
        assert_equal field_value(result, text_field), value
      end

      context "#broadcast_live_update" do
        test "requires that the flag be enabled", es_8_only: true do
          disable_feature_flag(:memex_table_without_limits)
          disable_feature_flag(:memex_project_without_limits_public_beta)
          disable_feature_flag(:memex_live_update_gids)

          populate_elasticsearch_index!(@issue_items)
          reset_hydro
          @issue.close(@actor, attributes: { state_reason: "not_planned" })

          MemexProject.any_instance.expects(:notify_memex_channel).never
          process_messages!
        end

        test "calls `notify_memex_channel` for associated projects with the correct timestamp, and updated content", es_8_only: true do
          enable_feature_flag(:memex_table_without_limits)
          disable_feature_flag(:memex_project_without_limits_public_beta)
          enable_feature_flag(:memex_live_update_gids)

          timestamp = Time.now.to_i
          request_id = SecureRandom.uuid
          model_gids = [@issue.global_relay_id]

          Timecop.freeze(Time.at(timestamp)) do
            populate_elasticsearch_index!(@issue_items)
            reset_hydro

            GitHub.context.push(actor_ip: "1.2.3.4")
            GitHub.context.push(request_id:)
            @issue.update!(title: @issue.title + " and more!")

            # One notify_memex_channel call will occur for each project. The call will include
            # all issue items that were updated that belong to each project.
            @issue_items.group_by(&:memex_project).each do |_project, items|
              item_ids = items.map do |item|
                { id: item.id, gid: item.global_relay_id }
              end

              MemexProject.any_instance.expects(:notify_memex_channel).at_least_once.with({
                type: "memex_item_denormalized_to_elasticsearch",
                timestamp:,
                models: model_gids,
                items: item_ids,
                source_type: "github.v2.IssueUpdate",
                request_id:,
              })
            end

            process_messages!
          end
        end

        test "does not call `notify_memex_channel` when all message processing fails in limited beta", es_8_only: true do
          enable_feature_flag(:memex_table_without_limits)
          enable_feature_flag(:memex_live_update_gids)

          project = create(:memex_project)
          project_item = create(:memex_project_item, memex_project: project)
          project_item.destroy!

          project.expects(:notify_memex_channel).never
          process_messages!
        end

        test "does not call `notify_memex_channel` when all message processing fails in public beta", es_8_only: true do
          org = create(:organization)

          disable_feature_flag(:memex_table_without_limits)
          enable_feature_flag(:memex_project_without_limits_public_beta, org)
          enable_feature_flag(:memex_live_update_gids)

          project = create(:memex_project, owner: org)
          project_item = create(:memex_project_item, memex_project: project)
          project_item.destroy!

          project.expects(:notify_memex_channel).never
          process_messages!
        end
      end

      context "observability" do
        test "logs successful on item create on ES5", es_8_only: true do
          create(:memex_project_item)
          Projects::DenormalizationProcessor.any_instance.expects(:success).once.with(
            "process_message",
            instance_of(GitHub::StreamProcessors::Message),
            includes(has_entries("result" => "created"))
          )
          process_messages!
        end

        test "logs successful on item delete", es_8_only: true do
          project_item = @issue_items[0]
          populate_elasticsearch_index!([project_item])
          project_item.destroy!
          Projects::DenormalizationProcessor.any_instance.expects(:success).once.with(
            "process_message",
            instance_of(GitHub::StreamProcessors::Message),
            includes(has_entries("result" => "deleted"))
          )
          process_messages!
        end

        test "logs response.body for content processing successes", es_8_only: true do
          populate_elasticsearch_index!(@issue_items)
          reset_hydro
          @issue.close(@actor, attributes: { state_reason: "not_planned" })
          GitHub.logger.expects(:info).with do |msg, data|
            assert_equal "process_message processed message with result: success.", msg
            assert_equal :success, data[:result]

            # We should have a stringified response that shows 3 items were updated
            assert_equal @issue_items.count, data[:"gh.memex.denormalization_processor.context"].scan({ "result" => "updated" }.inspect[1..-2]).count
            assert_equal "process_message", data[:"code.function"]
            assert_equal "Projects::DenormalizationProcessor", data[:"code.namespace"]
            refute_nil data[:"message.error.context"]
            refute_nil data[:"message.timestamp"]
            assert_nil data[:"code.error.msg"]
          end
          process_messages!
        end
      end

      test "skips processing when the project item is not found", es_8_only: true do
        project_item = create(:memex_project_item)
        project_item.destroy!

        process_messages!

        assert_message_skipped(MemexProjectColumn::Interface::Indexable::Processor::FailureReason::CONTENT_MISSING)
      end

      test "skips processing when the project is not found", es_8_only: true do
        project_item = create(:memex_project_item)
        project_item.memex_project.destroy!

        process_messages!

        assert_message_skipped(MemexProjectColumn::Interface::Indexable::Processor::FailureReason::CONTENT_MISSING)
      end

      test "skips processing project item when the adapter fails to hash the document due to missing content", es_8_only: true do
        issue = create(:issue, repository: @repo)
        create(:memex_project_item, memex_project: @memex, content: issue)

        Elastomer::Adapters::MemexProjectItem.any_instance.expects(:content_exists?).returns(false)
        Rails.env.stubs(:development?).returns(true)
        GitHub.logger.expects(:info).with do |_, data|
          assert_equal "content-missing", data[:"gh.memex.denormalization_processor.context"]
          assert_equal "process_message", data[:"code.function"]
        end

        process_messages!
        assert_message_skipped(MemexProjectColumn::Interface::Indexable::Processor::FailureReason::CONTENT_MISSING, 1)
      end

      test "stats triggering of resync job when processing raises a non-transient error", es_8_only: true do
        issue = create(:issue, repository: @repo)
        create(:memex_project_item, memex_project: @memex, content: issue)
        expected_error_msg = "boom"

        Elastomer::Adapters::MemexProjectItem.any_instance.stubs(:to_hash)
          .raises(StandardError, expected_error_msg)

        process_messages!

        assert_dogstats_increment(prefixed_metric("resync"), tags: [
          "error:StandardError",
          "topic:github.memex.v0.ProjectItemCreate"
        ])
      end

      test "updates draft issue assignees when a new assignment is created", es_8_only: true do
        project_item = @memex.build_draft_issue(creator: @user, title: "An idea").tap(&:save!)
        populate_elasticsearch_index!([project_item])
        project_item.content.assignees = [@user]
        project_item.save!

        result = get_doc(project_item.id)
        refute field(result, @assignees_field.id)

        process_messages!
        result = get_doc(project_item.id)
        assert field_value(result, @assignees_field).any? { |assignee| assignee["id"] == @user.id }
      end

      test "updates draft issue assignees when one assignee is replaced with another", es_8_only: true do
        project_item = @memex.build_draft_issue(creator: @actor, title: "An idea").tap(&:save!)
        project_item.content.assignees = [@actor]
        project_item.save!
        populate_elasticsearch_index!([project_item])
        reset_hydro

        result = get_doc(project_item.id)
        assert field_value(result, @assignees_field).any? { |assignee| assignee["id"] == @actor.id }

        project_item.content.update(assignees: [@user])
        project_item.save!

        result = get_doc(project_item.id)
        refute field_value(result, @assignees_field).any? { |assignee| assignee["id"] == @user.id }

        process_messages!
        result = get_doc(project_item.id)
        assert field_value(result, @assignees_field).any? { |assignee| assignee["id"] == @user.id }
        refute field_value(result, @assignees_field).any? { |assignee| assignee["id"] == @actor.id }
      end

      test "updates draft issue assignees when an existing assignment is deleted", es_8_only: true do
        project_item = @memex.build_draft_issue(creator: @actor, title: "An idea").tap(&:save!)
        project_item.content.assignees = [@actor]
        project_item.save!
        populate_elasticsearch_index!([project_item])
        reset_hydro

        project_item.content.assignees = []
        project_item.save!

        result = get_doc(project_item.id)
        assert field_value(result, @assignees_field).any? { |assignee| assignee["id"] == @actor.id }

        process_messages!
        result = get_doc(project_item.id)
        refute field(result, @assignees_field.id)
      end

      test "messages are ignored when the processor has implemented an ignore message method", es_8_only: true do
        example_schema = "github.v1.PullRequestMerge"
        message = build_message({}, schema: example_schema)

        MemexProjectColumn::Interface::Indexable::Processor.expects(:for_message).returns([
          DenormalizationProcessorBaseTest::TestProcessorIgnoresMessages.new(message),
        ])

        processor = Projects::DenormalizationProcessor.new
        processor.process_message(message)

        assert message.skipped?
        assert_equal message.cause, MemexProjectColumn::Interface::Indexable::Processor::FailureReason::MESSAGE_IGNORED
      end

      test "replication waiting is skipped when a processor does not declare a dependent cluster", es_8_only: true do
        example_schema = "github.v1.Request"
        message = build_message({}, schema: example_schema)

        MemexProjectColumn::Interface::Indexable::Processor.expects(:for_message).returns([
          DenormalizationProcessorBaseTest::TestProcessorBypassesReplicationWaiting.new(message),
        ])

        processor = Projects::DenormalizationProcessor.new
        processor.expects(:wait_for_replication!).never
        processor.process_message(message)
      end

      test "attempts resync 3 times when there is a JobStatus error" do
        status_with_error = ResyncMemexProjectItemsIndexJobStatus.create(1).tap { _1.error! }
        ResyncMemexProjectItemsIndexJobStatus.expects(:create).returns(status_with_error).times(3)

        example_schema = "github.v1.PullRequestMerge"
        message = build_message({}, schema: example_schema)
        test_processor = DenormalizationProcessorBaseTest::TestProcessorReturnsVersionConflict.new(message)
        exception = StandardError.new("boom")
        test_processor.expects(:update).throws(exception)
        MemexProjectColumn::Interface::Indexable::Processor.expects(:for_message).returns([test_processor])

        assert_raises(exception.class) do
          Projects::DenormalizationProcessor.new.process_message(message)
        end
      end

      test "attempts resync 3 times when there is a job queuing error" do
        exception = StandardError.new("boom")
        ResyncMemexProjectItemsIndexJob.expects(:perform_later).throws(exception).times(3)

        example_schema = "github.v1.PullRequestMerge"
        message = build_message({}, schema: example_schema)
        test_processor = DenormalizationProcessorBaseTest::TestProcessorReturnsVersionConflict.new(message)
        test_processor.expects(:update).throws(exception)
        MemexProjectColumn::Interface::Indexable::Processor.expects(:for_message).returns([test_processor])

        assert_raises(exception.class) do
          Projects::DenormalizationProcessor.new.process_message(message)
        end
      end
    end
  end

  class DenormalizationProcessorBaseTest < GitHub::TestCase
    include HydroTestHelpers
    include DogstatsTestHelpers
    include MemexHelpers
    include GitHub::LoggerHelper

    private def stub_env(key, value)
      old_value = ENV[key]
      ENV[key] = value
      yield if block_given?
    ensure
      ENV[key] = old_value
    end

    class TestProcessor < MemexProjectColumn::Interface::Indexable::Processor::Base
      def self.topics; end

      def dependent_mysql_replication_cluster; end

      def matching_elasticsearch_documents? = true

      def update(es_client)
        Elastomer::Interfaces::Api::Update::Response.from_es_response({
          _index: "test",
          _id: T.must(self.class.name).demodulize,
          _primary_term: 1,
          _shards: {
            total: 1,
            successful: 1,
            failed: 0
          },
          _seq_no: 1,
          _version: 1,
          result: "updated",
        })
      end

      def canonical_data_present? = true

      def project_ids_to_resync_on_failure = []

      def updated_models = []
    end

    class TestProcessorIgnoresMessages < TestProcessor
      def valid_message?
        false
      end
    end

    class TestProcessorBypassesReplicationWaiting < TestProcessor
      def dependent_mysql_replication_cluster
        nil
      end
    end

    class TestProcessorProvidesNoProjectIds < TestProcessor
      def project_ids_to_resync_on_failure
        []
      end
    end

    class TestProcessorReturnsVersionConflict < TestProcessor
      def update(es_client)
        Elastomer::Interfaces::Api::UpdateByQuery::Response.from_es_response(
          "took" => 9,
          "timed_out" => false,
          "total" => 1,
          "updated" => 0,
          "deleted" => 0,
          "batches" => 1,
          "version_conflicts" => 1,
          "noops" => 1,
          "retries" => { "bulk" => 0, "search" => 0 },
          "throttled_millis" => 0,
          "requests_per_second" => -1.0,
          "throttled_until_millis" => 0,
          "failures" => []
        )
      end

      def project_ids_to_resync_on_failure
        [1]
      end
    end

    class TestProcessorDoesNotBroadcastResult < TestProcessor
      def broadcast_result? = false
    end

    private def rename_account(user, new_login, actor = @actor)
      serialized_request_context = Hydro::EntitySerializer.request_context(GitHub.context.to_hash)
      spamurai_form_signals = {
        load_to_submit_in_milliseconds: 0,
        load_to_submit_timestamp_hacked: false,
        load_to_submit_timestamp_missing: true,
        load_to_submit_timestamp_secret_missing: true,
        honeypot_failure: true,
      }
      UserRenameJob.perform_now(user, new_login, actor, serialized_request_context, spamurai_form_signals)
    end

    private def serializer
      Hydro::EntitySerializer
    end

    private def get_doc(item_id)
      @index.docs.get(type: "memex_project_item", routing: item_id, id: item_id)
    end

    private def process_messages!
      run_processor(Projects::DenormalizationProcessor.new, allowed_primary_query_count: 0)
    end

    private def field(doc, field_id)
      doc["_source"]["field_values"].find { |field| field["field_id"] == field_id }
    end

    private def field_value(doc, db_field)
      es_field = field(doc, db_field.id)
      es_field[db_field.class.value_name.to_s]
    end

    # Some values that can be different in different environments is added as part of the base processor. Since such values are not
    # relevant to our test coverage, this helper method removes them from the context hash before comparison.
    private def assertable_error_context(context)
      context.symbolize_keys.except(:hydro_msg_partition, :hydro_msg_offset, :catalog_service)
    end

    private def failbot_context(content, content_type = "PullRequest", topic = "cp1-iad.ingest.github.v1.PullRequestClose")
      {
        "gh.actor.id": @actor.id,
        "gh.memex.item.content.id": content.id,
        "gh.memex.item.content.type": content_type,
        "gh.repo.id": @repo.id,
        "gh.processor.name": "Projects::DenormalizationProcessor",
        "gh.exception.is_critical": true,
        "gh.hydro.msg.topic": topic,
      }
    end

    private def update_by_query_failure_response(status = 500)
      # See https://www.elastic.co/guide/en/elasticsearch/reference/8.6/docs-update-by-query.html#docs-update-by-query-api-response-body
      # for reference
      failures = case status
      when 409
        [{
            "index": "failed-my_index",
            "type": "_doc",
            "id": "1002109",
            "cause": {
              "type": "version_conflict_engine_exception",
              "reason": "[1002109]: version conflict, required seqNo [37265539], primary term [20]. but no document was found",
              "index_uuid": "JMepgCegQamU8WDqQuFJ3Q",
              "shard": "0",
              "index": "failed-my_index"
            },
            "status": status
        }]
      else
        []
      end
      {
        "took": 276,
        "timed_out": false,
        "total": 1,
        "updated": 0,
        "deleted": 0,
        "batches": 1,
        "version_conflicts": 1,
        "noops": 0,
        "retries": {
          "bulk": 0,
          "search": 0
        },
        "throttled_millis": 0,
        "requests_per_second": -1,
        "throttled_until_millis": 0,
        "failures": failures
      }
    end

    private def assert_message_skipped(reason, times = 1)
      assert_dogstats_increment(times, prefixed_metric("message_skipped"), tags: ["reason:#{reason}"])
    end

    private def assert_message_succeeded
      assert_dogstats_increment(1, prefixed_metric("message_processed"))
    end

    private def prefixed_metric_processor_specific
      MemexProjectColumn::Interface::Indexable::Processor::Base::METRIC_NAME_INDEX_TIME
    end

    private def prefixed_metric(metric_name)
      "#{Projects::DenormalizationProcessor::METRIC_PREFIX}.#{metric_name}"
    end

    private def content_query(content, state: nil, state_reason: nil, is_draft: nil)
      extra_clauses = []
      extra_clauses << { "term": { "content.state": state } } if state.present?
      extra_clauses << { "term": { "content.state_reason": state_reason } } if state_reason.present?
      extra_clauses << { "term": { "content.is_draft": is_draft } } if is_draft.present?

      {
        "query": {
          "bool": {
            "filter": {
              "bool": {
                "must": [
                  {
                    "term": {
                      "content.repository_id": content.repository_id,
                    }
                  },
                  {
                    "term": {
                      "content.id": content.id,
                    }
                  },
                  {
                    "term": {
                      "content.type": content.class.name,
                    }
                  }
                ] + extra_clauses.compact
              }
            }
          }
        }
      }
    end
  end

  class DenormalizationProcessorTest < DenormalizationProcessorBaseTest
    include DenormalizationProcessorSharedTest

    fixtures do
      @actor = create(:user)
      @repo = create(:repository, owner: @actor)
      @user = create(:user)
      @repo.add_member(@user)
      @memex = create(:memex_project, owner: @actor, title: "My Memex Project")
      @single_select_field = create(:single_select_memex_column, memex_project: @memex).to_field
      @text_field = create(:memex_project_column, memex_project: @memex, user_defined: true, data_type: :text).to_field
      @date_field = create(:date_memex_column, memex_project: @memex).to_field
      @assignees_field = @memex.columns.find(&:assignees?).to_field
      @unaffiliated_issue = create(:issue, repository: @repo, state: "open")
      @issue = create(:issue, repository: @repo,  state: "open")
      @pull = create(:pull_request, :disable_disk_access, repository: @repo)
      @issue_items = [
        create(:memex_project_item, content: @issue, memex_project: @memex),
        create(:memex_project_item, content: @issue),
        create(:memex_project_item, content: @issue)
      ]
      @pull_items = create_list(:memex_project_item, 2, content: @pull)
    end

    setup do
      GitHub.dogstats.reset
      setup_search
      @index = Elastomer::Indexes::MemexProjectItems.new
      RedisRateLimiter::Result.any_instance.stubs(:at_limit?).returns(false)
    end

    teardown_once do
      teardown_search
    end
  end

  class DenormalizationProcessorMultiTenantTest < DenormalizationProcessorBaseTest
    include DenormalizationProcessorSharedTest

    fixtures do
      on_multi_tenant_enterprise { @business = create :business, :enterprise_managed_business }
      on_multi_tenant_enterprise tenant: @business do
        @actor = create(:emu, :owner, business: @business)
        org = create :organization, business: @business, admin: @actor
        @repo = create(:repository, owner: org)
        @user = create(:emu, business: @business)
        org.add_member(@user)
        @repo.add_member(@user)
        @repo.add_member(@actor)
        @memex = GitHub::CurrentTenant.unscope { create(:memex_project, owner: org, creator: @actor, title: "My Memex Project") }
        @single_select_field = create(:single_select_memex_column, memex_project: @memex).to_field
        @text_field = create(:memex_project_column, memex_project: @memex, user_defined: true, data_type: :text).to_field
        @date_field = create(:date_memex_column, memex_project: @memex).to_field
        @assignees_field = @memex.columns.find(&:assignees?).to_field
        @unaffiliated_issue = create(:issue, repository: @repo, state: "open")
        @issue = create(:issue, repository: @repo,  state: "open")
        @pull = create(:pull_request, :disable_disk_access, repository: @repo)
        @issue_items = [
          create(:memex_project_item, content: @issue, memex_project: @memex),
          create(:memex_project_item, content: @issue),
          create(:memex_project_item, content: @issue)
        ]
        @pull_items = create_list(:memex_project_item, 2, content: @pull)
      end
    end

    setup do
      on_multi_tenant_enterprise tenant: @business
      GitHub.dogstats.reset
      setup_search
      @index = Elastomer::Indexes::MemexProjectItems.new
      RedisRateLimiter::Result.any_instance.stubs(:at_limit?).returns(false)
    end

    teardown_once do
      teardown_search
    end

    test "processor is marked for unscoped queries in multi tenant environment", es_8_only: true do
      assert_predicate Projects::DenormalizationProcessor, :stream_processor_marked_for_unscoped_queries?
    end
  end
end
