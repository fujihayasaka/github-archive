# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityCenter
  module AlertPrioritization
    module CopilotPromptExperiments
      class OwnerTriggerEmbeddingsIndexingJobTest < GitHub::TestCase
        include JobTestHelper
        include ::SecurityCenter::TestFixtures

        fixtures do
          create_org_level_fixtures
          @actor = @owner
        end

        setup do
          ::SecurityCenter::FeatureFlagHelper.stubs(:disable_alert_prioritization_owner_trigger_embeddings_indexing_job?).returns(false)
        end

        context 'when feature flag "disable_alert_prioritization_owner_trigger_embeddings_indexing_job" is enabled' do
          test "it does not process any repos" do
            ::SecurityCenter::FeatureFlagHelper.stubs(:disable_alert_prioritization_owner_trigger_embeddings_indexing_job?).returns(true)
            OwnerTriggerEmbeddingsIndexingJob.any_instance.expects(:trigger_embeddings_indexing).never
            OwnerTriggerEmbeddingsIndexingJob.perform_now(actor: @actor, owner: @org)
          end
        end

        test "it triggers indexing" do
          OwnerTriggerEmbeddingsIndexingJob.any_instance.expects(:trigger_embeddings_indexing).times(@org.repositories.count).returns(:ok)
          OwnerTriggerEmbeddingsIndexingJob.perform_now(actor: @actor, owner: @org)
        end

        test "it does not trigger indexing for repos that are already indexed" do
          @org.repositories.find_each do |repo|
            CopilotIndexedRepositories.find_or_create_by(repository_id: repo.id)
          end

          OwnerTriggerEmbeddingsIndexingJob.any_instance.expects(:trigger_embeddings_indexing).never
          OwnerTriggerEmbeddingsIndexingJob.perform_now(actor: @actor, owner: @org)
        end

        test "it stops processing once max_sequence_num_processed_items is reached" do
          max_sequence_num_processed_items = 1_000
          OwnerTriggerEmbeddingsIndexingJob.any_instance.stubs(:sequence_num_processed_items).returns(max_sequence_num_processed_items)
          OwnerTriggerEmbeddingsIndexingJob.any_instance.expects(:trigger_embeddings_indexing).never
          OwnerTriggerEmbeddingsIndexingJob.perform_now(actor: @actor, owner: @org, max_sequence_num_processed_items:)
        end
      end
    end
  end
end
