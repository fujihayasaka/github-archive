# typed: true
# frozen_string_literal: true

require "test_helper"

module MemexProjectColumn::Interface::Indexable::Processor
  class ResyncProjectsStrategyTest < GitHub::TestCase
    include MemexHelpers
    include HydroTestHelpers

    class TestProcessor < MemexProjectColumn::Interface::Indexable::Processor::Base
      include ResyncProjectsStrategy

      def self.topics
        []
      end

      def matching_elasticsearch_documents?
        true
      end

      def canonical_data_present?
        true
      end

      def dependent_mysql_replication_cluster
        :fake_cluster
      end

      def project_ids_to_resync
        owner.memex_projects.pluck(:id)
      end

      def updated_models
        []
      end

      private

      def owner_id
        message.dig(:actor, :id)
      end

      def owner
        User.find_by(id: owner_id)
      end
    end

    fixtures do
      @admin = create(:verified_user)
      @organization = create(:organization, admin: @admin)
    end

    setup do
      @message = memex_event_message(actor: @organization)
    end

    context "#consume" do
      test "returns a projects sync result" do
        first_memex_project = create(:memex_project, owner: @organization)
        second_memex_project = create(:memex_project, owner: @organization)
        processor = TestProcessor.new(@message)

        assert_enqueued_jobs 2, only: ResyncMemexProjectItemsIndexJob do
          results = processor.consume
          result = T.must(results.first)

          assert_equal 1, results.size
          assert_kind_of MemexProjectColumn::Interface::Indexable::Processor::ResyncProjectsResult, result
          refute_predicate result, :failure_reason?
          assert_equal [first_memex_project.id, second_memex_project.id].sort, result.updated_memex_ids.sort, "Expected all successful resynced projects in updated_memex_ids"
        end
      end

      test "returns partial_resync failure reason when not all projects were successfully resynced" do
        first_memex_project = create(:memex_project, owner: @organization)
        second_memex_project = create(:memex_project, owner: @organization)
        first_job_status = ResyncMemexProjectItemsIndexJobStatus.create(first_memex_project.id)
        second_job_status = ResyncMemexProjectItemsIndexJobStatus.create(second_memex_project.id)
        first_job_status.error!
        ResyncMemexProjectItemsIndexJobStatus.stubs(:create).with(first_memex_project.id).returns(first_job_status)
        ResyncMemexProjectItemsIndexJobStatus.stubs(:create).with(second_memex_project.id).returns(second_job_status)
        processor = TestProcessor.new(@message)

        assert_enqueued_jobs 1, only: ResyncMemexProjectItemsIndexJob do
          results = processor.consume
          result = T.must(results.first)

          assert_equal 1, results.size
          assert_kind_of MemexProjectColumn::Interface::Indexable::Processor::ResyncProjectsResult, result
          assert_predicate result, :failure_reason?
          assert_predicate result, :partial_resync?
          assert_equal [second_memex_project.id], result.updated_memex_ids, "Expected only successful resynced projects in updated_memex_ids"
        end
      end
    end

    context "#project_ids_to_resync" do
      test "returns an array of project IDs" do
        memex_project = create(:memex_project, owner: @organization)
        processor = TestProcessor.new(@message)

        assert_equal [memex_project.id], processor.project_ids_to_resync
      end
    end

    context "#project_ids_to_resync_on_failure" do
      test "returns same array of project IDs needing resyncing by default" do
        memex_project = create(:memex_project, owner: @organization)
        processor = TestProcessor.new(@message)

        assert_equal [memex_project.id], processor.project_ids_to_resync
        assert_equal processor.project_ids_to_resync, processor.project_ids_to_resync_on_failure
      end

      test "returns no projects if all projects enqueued resyncs successfully" do
        memex_project = create(:memex_project, owner: @organization)
        processor = TestProcessor.new(@message)

        assert_enqueued_with job: ResyncMemexProjectItemsIndexJob do
          processor.consume
        end

        assert_equal [memex_project.id], processor.project_ids_to_resync, "Expected to resync at least one project"
        assert_empty processor.project_ids_to_resync_on_failure, "Expected no projects needing to resync on a failure"
      end

      test "returns only failed projects when some projects were resynced successfully" do
        first_memex_project = create(:memex_project, owner: @organization)
        second_memex_project = create(:memex_project, owner: @organization)
        first_job_status = ResyncMemexProjectItemsIndexJobStatus.create(first_memex_project.id)
        second_job_status = ResyncMemexProjectItemsIndexJobStatus.create(second_memex_project.id)
        first_job_status.error!
        ResyncMemexProjectItemsIndexJobStatus.stubs(:create).with(first_memex_project.id).returns(first_job_status)
        ResyncMemexProjectItemsIndexJobStatus.stubs(:create).with(second_memex_project.id).returns(second_job_status)
        processor = TestProcessor.new(@message)

        assert_enqueued_jobs 1, only: ResyncMemexProjectItemsIndexJob do
          processor.consume
        end

        assert_equal [first_memex_project.id, second_memex_project.id].sort, processor.project_ids_to_resync.sort
        assert_equal [first_memex_project.id], processor.project_ids_to_resync_on_failure, "Expected one projects needing to resync"
      end
    end

    private

    def memex_event_message(actor:)
      build_message({
        actor: Hydro::EntitySerializer.user(actor),
      }, schema: "github.memex.v1.Event")
    end
  end
end
