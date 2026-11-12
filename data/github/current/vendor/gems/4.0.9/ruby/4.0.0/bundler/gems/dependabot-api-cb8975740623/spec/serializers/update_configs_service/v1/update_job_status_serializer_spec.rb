# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdateConfigsService::V1::UpdateJobStatusSerializer,
               type: :serializer do
  let(:update_job) do
    FactoryBot.create(:update_job)
  end

  let(:serialized_job) do
    described_class.new(update_job)
  end

  describe "#errors" do
    subject(:errors) { serialized_job.to_h[:errors] }

    context "for a successful job" do
      it "is empty" do
        expect(errors).to be_empty
      end
    end

    context "for a failed job" do
      let(:update_job) do
        FactoryBot.create(:update_job).tap do |job|
          error = FactoryBot.create(:update_job_error,
                                    update_job: job,
                                    error_type: "dependency_file_not_evaluatable",)
          job.update_job_errors << error
        end
      end

      it "contains the job's errors" do
        expect(errors.length).to eq(1)
        expect(errors.first[:type]).to eq("dependency_file_not_evaluatable")
      end
    end
  end

  describe "#package_ecosystem" do
    it "is present in the serialized hash" do
      expect(serialized_job.to_h.keys).to include(:package_ecosystem)
    end

    it "includes high-level info for the ecosystem" do
      expect(serialized_job.to_h[:package_ecosystem]).
        to eq({
                name: "BUNDLER",
                support: "BETA",
                is_repository_access_supported: false,
              })
    end
  end

  describe "#state" do
    let(:update_config_wrapper) do
      DependabotApi::V1::UpdateJobStatus.new(serialized_job.to_h)
    end

    before do
      # Let's temporarily let any transition work.
      allow_any_instance_of(UpdateJobStateMachine). # rubocop:disable RSpec/AnyInstance
        to receive(:validate_transition).and_return(true)
    end

    UpdateJobStateMachine.states.each do |state_name|
      context "for a job in #{state_name}" do
        let(:state) { state_name }

        before do
          update_job.transition_to!(state)
        end

        if state_name == "abandoned"
          it "substitutes :CANCELLED as the state" do
            expect(update_config_wrapper.state).
              to be(:CANCELLED)
          end
        else
          it "correctly serializes the job" do
            expect(update_config_wrapper.state).
              to eql(state.upcase.to_sym)
          end
        end
      end
    end
  end

  describe "#finished_at" do
    let(:update_config_wrapper) do
      DependabotApi::V1::UpdateJobStatus.new(serialized_job.to_h)
    end

    UpdateJobStateMachine.states.each do |state_name|
      context "for a job in #{state_name}" do
        let(:state) { state_name }

        let(:update_job) do
          FactoryBot.create(:update_job, state_name.to_sym)
        end

        if UpdateJob::TERMINAL_UPDATE_JOB_STATES.include?(state_name.to_sym)
          it "includes finished_at" do
            expect(update_config_wrapper.finished_at).to be_a(Google::Protobuf::Timestamp)
          end
        else
          it "doesn't include finished_at" do
            expect(update_config_wrapper.finished_at).to be(nil)
          end
        end
      end
    end
  end

  describe "#runner_type" do
    it "includes the runner_type" do
      expect(serialized_job.to_h.keys).to include(:runner_type)
      expect(serialized_job.to_h[:runner_type]).to eql(update_job.runner_type)
    end
  end

  describe "#actions_external_id" do
    it "includes the actions_external_id" do
      update_job.actions_external_id = SecureRandom.uuid

      expect(serialized_job.to_h.keys).to include(:actions_external_id)
      expect(serialized_job.to_h[:actions_external_id]).to eql(update_job.actions_external_id)
    end
  end

  describe "#actions_workflow_run_id" do
    it "includes the actions_workflow_run_id" do
      update_job.actions_workflow_run_id = 9876543210

      expect(serialized_job.to_h.keys).to include(:actions_workflow_run_id)
      expect(serialized_job.to_h[:actions_workflow_run_id]).to eql(update_job.actions_workflow_run_id)
    end
  end
end
