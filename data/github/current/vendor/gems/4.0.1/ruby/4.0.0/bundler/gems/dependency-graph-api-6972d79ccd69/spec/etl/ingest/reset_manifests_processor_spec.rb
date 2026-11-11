require "rails_helper"

module Ingest
  describe ResetManifestsProcessor do
    include ActiveJob::TestHelper

    let(:config)    { Rails.application.config_for(:kafka).with_indifferent_access }
    let(:processor) { described_class.new }
    let(:repo_id_enabled) { 12345 }
    let(:repo_id_disabled) { 67890 }
    let(:repo_not_found) { 99999 }

    def hydro_message(repo_id:, action:, trigger:)
      # Create sample repository entity
      repository = Hydro::Schemas::Github::V1::Entities::Repository.new(
        id: repo_id,
        name: "test-org/test-repo"
      )

      # Create sample user/actor entity
      actor = Hydro::Schemas::Github::V1::Entities::User.new(
        id: 5678,
        login: "test-user"
      )

      # Create sample owner entity
      owner = Hydro::Schemas::Github::V1::Entities::User.new(
        id: 9012,
        login: "test-org"
      )

      # Create request context
      request_context = Hydro::Schemas::Github::V1::Entities::RequestContext.new(
        request_id: "test-request-id"
      )

      # Create the main ResetManifests message
      Hydro::Schemas::Github::Dependencygraph::V1::ResetManifests.new(
        request_context: request_context,
        actor: actor,
        repository: repository,
        owner: owner,
        action: action,
        trigger: trigger
      )
    end

    let(:hydro_message_processed) {
      hydro_message(repo_id: repo_id_enabled, action: :RESET_ACTION_CLEAR, trigger: :RESET_TRIGGER_MASS_OFFBOARD)
    }

    let(:hydro_message_not_processed) {
      hydro_message(repo_id: repo_id_enabled, action: :RESET_ACTION_REDETECT, trigger: :RESET_TRIGGER_USER)
    }

    let(:hydro_message_ff_disabled) {
      hydro_message(repo_id: repo_id_disabled, action: :RESET_ACTION_CLEAR, trigger: :RESET_TRIGGER_MASS_OFFBOARD)
    }

    let(:user_triggered_hydro_message_processed) {
      hydro_message(repo_id: repo_id_enabled, action: :RESET_ACTION_CLEAR, trigger: :RESET_TRIGGER_REPO_SETTINGS)
    }

    let(:repo_does_not_exist) {
      hydro_message(repo_id: repo_not_found, action: :RESET_ACTION_CLEAR, trigger: :RESET_TRIGGER_USER)
    }

    def process
      run_consumer(processor)
    end

    before do
      processor.spec_reset
      allow(Instrument).to receive(:increment)
      ActiveJob::Base.queue_adapter = :test

      # Add test repos
      factory.given_repository(github_repository_id: repo_id_enabled, public: true)
      factory.given_repository(github_repository_id: repo_id_disabled, public: false)
    end

    it "does not enqueue any jobs if the action is not RESET_ACTION_CLEAR" do
      processor.publish(hydro_message_not_processed.to_h)

      expect {
        process
      }.not_to have_enqueued_job(ClearDependenciesJob)

      expect {
        process
      }.not_to have_enqueued_job(ClearDependenciesBackfillJob)

      expect(Instrument).to have_received(:increment).with("etl.reset_manifests", {
        action: :RESET_ACTION_REDETECT,
        trigger: :RESET_TRIGGER_USER,
        result: "skipped",
        backfill: nil,
        public: nil
      })
    end

    it "does not enqueue any jobs if the repo doesn't exist" do
      processor.publish(repo_does_not_exist.to_h)

      expect {
        process
      }.not_to have_enqueued_job(ClearDependenciesJob)

      expect {
        process
      }.not_to have_enqueued_job(ClearDependenciesBackfillJob)

      expect(Instrument).to have_received(:increment).with("etl.reset_manifests", {
        action: :RESET_ACTION_CLEAR,
        trigger: :RESET_TRIGGER_USER,
        result: "repo_not_found",
        backfill: nil,
        public: nil
      })
    end

    describe "when the action is RESET_ACTION_CLEAR" do
      describe "when the trigger is RESET_TRIGGER_MASS_OFFBOARD" do
        it "enqueues ClearDependenciesBackfillJob when the ff is enabled" do
          processor.publish(hydro_message_processed.to_h)

          expect {
            process
          }.to have_enqueued_job(ClearDependenciesBackfillJob).with(repo_id_enabled, log_context: anything)

          expect {
            process
          }.not_to have_enqueued_job(ClearDependenciesJob)

          expect(Instrument).to have_received(:increment).with("etl.reset_manifests", {
            action: :RESET_ACTION_CLEAR,
            trigger: :RESET_TRIGGER_MASS_OFFBOARD,
            result: "success",
            backfill: true,
            public: true
          })
        end
      end

      it "enqueues ClearDependenciesJob when the trigger is not RESET_TRIGGER_MASS_OFFBOARD" do
        processor.publish(user_triggered_hydro_message_processed.to_h)

        expect {
          process
        }.to have_enqueued_job(ClearDependenciesJob).with(repo_id_enabled, log_context: anything)

        expect {
          process
        }.not_to have_enqueued_job(ClearDependenciesBackfillJob)

        expect(Instrument).to have_received(:increment).with("etl.reset_manifests", {
          action: :RESET_ACTION_CLEAR,
          trigger: :RESET_TRIGGER_REPO_SETTINGS,
          result: "success",
          backfill: false,
          public: true
        })
      end
    end

    it "handles debug message properly" do
      message = double("message", inspect: "test_debug_message")
      expect { processor.consume_debug_message(message) }.to output("test_debug_message\n").to_stdout
    end
  end
end
