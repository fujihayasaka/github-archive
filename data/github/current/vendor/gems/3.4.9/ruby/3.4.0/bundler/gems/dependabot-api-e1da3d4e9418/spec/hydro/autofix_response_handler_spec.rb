# frozen_string_literal: true

require "rails_helper"
require "json"

RSpec.describe AutofixResponseHandler do
  let(:hydro_payload) do
    hydro_fixture(
      name: hydro_fixture_name,
      schema: "code_scanning.v0.DependabotAutofixResult"
    )
  end

  let(:original_message) do
    instance_double(
      Hydro::Consumer::ConsumerMessage,
      value: hydro_payload,
      timestamp: Time.now.utc,
      headers: { "X-GitHub-Tenant-ID" => "1234", "X-GitHub-Tenant" => "lugman-inc" },
    )
  end

  let(:ai_model) { "gpt-4-o" }

  let(:ai_version) { "1.0.0" }

  let(:suggested_fix) do
    ::HydroHandlers::CodeScanning::SuggestedFix.from_message(original_message)
  end

  let(:state) { original_message.value.fetch(:state) }

  let(:autofix_suggestion_job) do
    FactoryBot.create(:autofix_suggestion_job)
  end

  let(:request_id) { autofix_suggestion_job.id }

  let(:autofix_response_handler) do
    described_class.new(
      request_id: request_id,
      ai_model: ai_model,
      ai_version: ai_version,
      suggested_fix: suggested_fix,
      state: state,
    )
  end

  describe "#run" do
    let(:hydro_fixture_name) { "push_js_fix" }

    let(:run) do
      autofix_response_handler.run
    end

    before do
      allow(AutofixSuggestionJob).to receive(:find).and_call_original
      allow(AutofixSuggestionJob).to receive(:find).
        with(autofix_suggestion_job.id).
        and_return(autofix_suggestion_job)
      allow(autofix_suggestion_job).to receive(:complete_github_check_run)
    end

    context "when dependabot receives an autofix hydro event" do
      before do
        autofix_suggestion_job
        allow(CreateAutofixAnnotationJob).to receive(:perform_later).and_return(nil)
      end

      context "and the message has a suggested fix" do
        it "creates a suggested fix" do
          expect(autofix_response_handler).to receive(:run).and_call_original

          expect { run }.to change(SuggestedFix, :count).by(1)

          autofix_suggested_fix = SuggestedFix.find_by(autofix_suggestion_job_id: autofix_suggestion_job.id)

          expect(autofix_suggested_fix).not_to be_nil
          expect(JSON.parse(autofix_suggested_fix.dependency_metadata).first["name"]).to eq("escape-html")
          expect(JSON.parse(autofix_suggested_fix.dependency_metadata).first["version"]).to eq("1.0.3")
        end

        it "parses the suggested fix files correctly" do
          expect { run }.to change(SuggestedFixFile, :count).by(1)

          autofix_suggested_fix_file = SuggestedFixFile.joins(suggested_fix: :autofix_suggestion_job).
                                       find_by(autofix_suggestion_jobs: { id: autofix_suggestion_job.id })

          expect(autofix_suggested_fix_file).not_to be_nil
          expect(autofix_suggested_fix_file.file_path).to eq("index.js")
        end

        context "and the message does not have dependency_metadata" do
          let(:hydro_fixture_name) { "push_js_fix_no_dependency_metadata" }

          it "creates a suggested fix" do
            expect(autofix_response_handler).to receive(:run).and_call_original

            expect { run }.to change(SuggestedFix, :count).by(1)

            autofix_suggested_fix = SuggestedFix.find_by(autofix_suggestion_job_id: autofix_suggestion_job.id)

            expect(autofix_suggested_fix).not_to be_nil
            expect(autofix_suggested_fix.dependency_metadata).to eq("[]")
          end
        end

        it "records a stage success" do
          # in order to set an expectation on the test object we need to
          # also stub the DB lookup to return this exact object
          allow(AutofixSuggestionJob).to receive(:find).
            with(autofix_suggestion_job.id).
            and_return(autofix_suggestion_job)
          expect(autofix_suggestion_job).to receive(:observe_stage).
            with(stage: AutofixSuggestionJob::Stages::RECORD_AUTOFIX_RESPONSE).
            and_call_original

          expect(AutofixSuggestionJob::Stages).to receive(:record_success).
            with(stage: AutofixSuggestionJob::Stages::RECORD_AUTOFIX_RESPONSE)

          run
        end
      end

      context "and the message does not have a suggested fix" do
        let(:hydro_fixture_name) { "push_js_no_fix" }

        it "does not create a suggested fix" do
          expect(autofix_response_handler).to receive(:run).and_call_original

          expect { run }.to raise_error(AutofixResponseHandler::SuggestedFixInvalidError).
            and change(SuggestedFix, :count).by(0)
        end

        it "records a stage failure" do
          expect(AutofixSuggestionJob::Stages).to receive(:record_error).
            with(hash_including(stage: AutofixSuggestionJob::Stages::RECORD_AUTOFIX_RESPONSE))
          expect(AutofixSuggestionJob::Stages).not_to receive(:record_success)
          expect { run }.to raise_error(AutofixResponseHandler::SuggestedFixInvalidError)
        end

        it "marks the autofix check run as failed" do
          expect(autofix_suggestion_job).to receive(:complete_github_check_run).with(
            conclusion: GitHub::CheckRun::Conclusion::FAILURE
          )
          expect { run }.to raise_error(AutofixResponseHandler::SuggestedFixInvalidError)
        end
      end

      context "and the event has an unknown state" do
        let(:hydro_fixture_name) { "push_js_unknown_state" }

        it "does not create a suggested fix" do
          expect(autofix_response_handler).to receive(:run).and_call_original

          expect { run }.to raise_error(AutofixResponseHandler::SuggestedFixUnknownError).
            and change(SuggestedFix, :count).by(0)
        end

        it "records a stage failure" do
          expect(AutofixSuggestionJob::Stages).to receive(:record_error).
            with(hash_including(stage: AutofixSuggestionJob::Stages::RECORD_AUTOFIX_RESPONSE))
          expect(AutofixSuggestionJob::Stages).not_to receive(:record_success)

          expect { run }.to raise_error(AutofixResponseHandler::SuggestedFixUnknownError)
        end

        it "marks the autofix check run as failed" do
          expect(autofix_suggestion_job).to receive(:complete_github_check_run).with(
            conclusion: GitHub::CheckRun::Conclusion::FAILURE
          )
          expect { run }.to raise_error(AutofixResponseHandler::SuggestedFixUnknownError)
        end
      end
    end

    context "When the autofix job does not exist" do
      let(:request_id) { autofix_suggestion_job.id + 2 }

      it "records a stage failure" do
        expect(AutofixSuggestionJob::Stages).to receive(:record_error).
          with(hash_including(stage: AutofixSuggestionJob::Stages::RECORD_AUTOFIX_RESPONSE))
        expect(AutofixSuggestionJob::Stages).not_to receive(:record_success)

        expect { run }.to raise_error(AutofixResponseHandler::MissingAutofixSuggestionJobError)
      end

      it "raises an error" do
        expect { run }.to raise_error(AutofixResponseHandler::MissingAutofixSuggestionJobError).
          and change(SuggestedFix, :count).by(0)
      end
    end
  end
end
