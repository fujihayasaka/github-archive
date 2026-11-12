# frozen_string_literal: true

require "rails_helper"

RSpec.describe AutofixSuggestionJob, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  subject(:autofix_suggestion_job) { FactoryBot.build_stubbed(:autofix_suggestion_job) }

  describe "validations" do
    it "is expected to be valid" do
      expect(autofix_suggestion_job).to be_valid
    end

    describe "#pull_request" do
      it "is required" do
        autofix_suggestion_job.pull_request = nil
        expect(autofix_suggestion_job).not_to be_valid
      end

      it "validates uniqueness scoped to #target_sha" do
        first = create(:autofix_suggestion_job)
        second = build(:autofix_suggestion_job, pull_request: first.pull_request, target_sha: first.target_sha)

        expect(second).not_to be_valid
        expect(second.errors[:pull_request_id]).to include("has already been taken")
      end
    end

    describe "#target_sha" do
      it "is required" do
        autofix_suggestion_job.target_sha = nil
        expect(autofix_suggestion_job).not_to be_valid

        autofix_suggestion_job.target_sha = ""
        expect(autofix_suggestion_job).not_to be_valid
      end
    end

    describe "#sarif_content" do
      it "can be nil" do
        autofix_job = build_stubbed(:autofix_suggestion_job, sarif_content: nil)

        expect(autofix_job).to be_valid
      end

      it "is expected to be a Hash" do
        sarif_as_hash = JSON.parse(fixture("sarif/styled-components.sarif"))
        autofix_job = build_stubbed(:autofix_suggestion_job, sarif_content: sarif_as_hash)

        expect(autofix_job).to be_valid
      end
    end
  end

  describe "#sarif_content=" do
    it "casts String contents to Hash" do
      sarif_as_string = fixture("sarif/styled-components.sarif")
      expect(sarif_as_string).to be_a(String)

      autofix_suggestion_job.sarif_content = sarif_as_string

      expect(autofix_suggestion_job.sarif_content).to be_a(Hash)
      expect(autofix_suggestion_job.sarif_content).to eq(JSON.parse(sarif_as_string))
    end

    it "passes Hash values through" do
      sarif_as_hash = JSON.parse(fixture("sarif/styled-components.sarif"))
      expect(sarif_as_hash).to be_a(Hash)

      autofix_suggestion_job.sarif_content = sarif_as_hash

      expect(autofix_suggestion_job.sarif_content).to be_a(Hash)
      expect(autofix_suggestion_job.sarif_content).to eq(sarif_as_hash)
    end

    it "passes Nil through" do
      autofix_suggestion_job.sarif_content = nil

      expect(autofix_suggestion_job.sarif_content).to be_nil
    end

    it "raises an ArgumentError when another value is provided" do
      bogus_sarif = %w(not a String or Hash)

      expect { autofix_suggestion_job.sarif_content = bogus_sarif }.
        to raise_error(ArgumentError)
    end
  end

  describe "#sarif" do
    it "returns a Sarif" do
      sarif_content = fixture("sarif/styled-components.sarif")
      autofix_suggestion_job.sarif_content = sarif_content

      expect(autofix_suggestion_job.sarif).to be_a(Sarif)
    end
  end

  describe "#dependency_declaration_location" do
    it "delegates to Sarif" do
      sarif = fixture("sarif/styled-components.sarif")
      autofix_suggestion_job.sarif_content = sarif

      expect(autofix_suggestion_job.sarif).to receive(:dependency_declaration_location)
      autofix_suggestion_job.dependency_declaration_location
    end
  end

  describe "#affected_file_paths" do
    it "delegates to Sarif" do
      sarif = fixture("sarif/styled-components.sarif")
      autofix_suggestion_job.sarif_content = sarif

      expect(autofix_suggestion_job.sarif).to receive(:affected_file_paths)
      autofix_suggestion_job.affected_file_paths
    end
  end

  describe "#message" do
    it "delegates to Sarif" do
      sarif = fixture("sarif/styled-components.sarif")
      autofix_suggestion_job.sarif_content = sarif

      expect(autofix_suggestion_job.sarif).to receive(:message)
      autofix_suggestion_job.message
    end
  end

  describe "#level" do
    it "delegates to Sarif" do
      sarif = fixture("sarif/styled-components.sarif")
      autofix_suggestion_job.sarif_content = sarif

      expect(autofix_suggestion_job.sarif).to receive(:level)
      autofix_suggestion_job.level
    end
  end

  describe "#observe_stage" do
    let(:stage) { described_class::Stages::START }

    it "raises an error when an invalid stage is provided" do
      expect do
        autofix_suggestion_job.observe_stage(stage: nil) {}
      end.to raise_error("Unexpected autofix stage")

      expect do
        autofix_suggestion_job.observe_stage(stage: :unknown_stage) {}
      end.to raise_error("Unexpected autofix stage")
    end

    it "raises an error when a block isn't given" do
      expect do
        autofix_suggestion_job.observe_stage(stage:)
      end.to raise_error("Stage block not provided")
    end

    it "logs a stage success" do
      expect(AutofixSuggestionJob::Stages).to receive(:record_success).with(
        hash_including(stage: stage)
      )
      autofix_suggestion_job.observe_stage(stage: stage) {}
    end

    it "logs a stage failure on error" do
      expect(AutofixSuggestionJob::Stages).to receive(:record_error).with(
        hash_including(stage: stage, error: an_instance_of(RuntimeError))
      )

      expect do
        autofix_suggestion_job.observe_stage(stage: stage) do
          raise "test"
        end
      end.to raise_error("test")
    end

    it "includes the stage and autofix job telemetry attributes in logger context" do
      expect(Dependabot::Logger).to receive(:log_context).with(
        hash_including(stage: stage, **autofix_suggestion_job.telemetry_attributes)
      )
      autofix_suggestion_job.observe_stage(stage: stage) {}
    end
  end

  describe "#complete_github_check_run" do
    subject(:autofix_suggestion_job) { create(:autofix_suggestion_job) }

    let(:json_header) { { "Content-Type" => "application/json" } }
    let(:check_run_data) { fixture("github_responses/check_run_created.json") }
    let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
    let(:repo_url) { github_url + "repositories/#{autofix_suggestion_job.repo.github_id}" }
    let(:check_run_url) { repo_url + "/check-runs/#{autofix_suggestion_job.check_run_id}" }

    before do
      github_token = "top secret"
      allow(GitHubHelpers).
        to receive(:installation_access_token_for).
        and_return(github_token)

      stub_request(:patch, check_run_url).
        and_return(status: 200, body: check_run_data, headers: json_header)
    end

    it "returns nil if the job does not have a check_run_id" do
      autofix_suggestion_job.check_run_id = nil
      expect(autofix_suggestion_job.complete_github_check_run(conclusion: GitHub::CheckRun::Conclusion::FAILURE)).
        to be_nil
    end

    it "raises an error with a disallowed check run conclusion" do
      expect { autofix_suggestion_job.complete_github_check_run(conclusion: GitHub::CheckRun::Conclusion::STALE) }.
        to raise_error("Unexpected autofix check run conclusion")
      expect { autofix_suggestion_job.complete_github_check_run(conclusion: nil) }.
        to raise_error("Unexpected autofix check run conclusion")
      expect { autofix_suggestion_job.complete_github_check_run(conclusion: "some other value") }.
        to raise_error("Unexpected autofix check run conclusion")
    end

    it "makes an API call to set a check run conclusion" do
      autofix_suggestion_job.complete_github_check_run(conclusion: GitHub::CheckRun::Conclusion::FAILURE)

      expect(WebMock).to have_requested(:patch, check_run_url).with(
        body: hash_including(
          status: GitHub::CheckRun::Status::COMPLETED,
          conclusion: GitHub::CheckRun::Conclusion::FAILURE
        )
      )
    end
  end
end
