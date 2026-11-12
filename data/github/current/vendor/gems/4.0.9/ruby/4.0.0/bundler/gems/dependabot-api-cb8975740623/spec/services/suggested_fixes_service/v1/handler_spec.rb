# frozen_string_literal: true

require "rails_helper"

RSpec.describe SuggestedFixesService::V1::Handler do
  let(:handler) { described_class.new }
  let(:service) { DependabotApi::V1::SuggestedFixesService.new(handler) }

  let(:suggested_fix) do
    create(:suggested_fix, :with_suggested_fix_files, files_count: 2, dependency_metadata_count: 2)
  end
  let(:autofix_job) { suggested_fix.autofix_suggestion_job }
  let(:params) do
    {
      autofix_job_id: autofix_job.id,
      github_repo_id: autofix_job.pull_request.repo.github_id,
      github_pull_request_number: autofix_job.pull_request.github_number,
    }
  end

  shared_examples "when the autofix job doesn't exist" do
    context "when the autofix job doesn't exist" do
      before { autofix_job.delete }

      it "returns a not found error" do
        expect(response).to be_a(Twirp::Error)
        expect(response.code).to be(:not_found)
        expect(response.msg).to eql("AutofixSuggestionJob ##{autofix_job.id} was not found")
      end

      it "records a stage error" do
        expect(AutofixSuggestionJob::Stages).to receive(:record_error).
          with(hash_including(stage: stage))
        expect(AutofixSuggestionJob::Stages).not_to receive(:record_success)

        response
      end
    end
  end

  shared_examples "when the autofix job id is not given" do
    context "when the autofix job id is not given" do
      let(:params) do
        {
          github_repo_id: autofix_job.pull_request.repo.github_id,
          github_pull_request_number: autofix_job.pull_request.github_number,
        }
      end

      it "returns an invalid argument error" do
        expect(response).to be_a(Twirp::Error)
        expect(response.code).to be(:invalid_argument)
        expect(response.msg).to eql("autofix_job_id is required")
      end

      it "records a stage error" do
        expect(AutofixSuggestionJob::Stages).to receive(:record_error).
          with(hash_including(stage: stage))
        expect(AutofixSuggestionJob::Stages).not_to receive(:record_success)

        response
      end
    end
  end

  shared_examples "when the suggested fix doesn't exist" do
    context "when the suggested fix doesn't exist" do
      before { suggested_fix.delete }

      it "returns a not found error" do
        expect(response).to be_a(Twirp::Error)
        expect(response.code).to be(:not_found)
        expect(response.msg).to eql("SuggestedFix for job #{autofix_job.id} was not found")
      end

      it "records a stage error" do
        expect(AutofixSuggestionJob::Stages).to receive(:record_error).
          with(hash_including(stage: stage))
        expect(AutofixSuggestionJob::Stages).not_to receive(:record_success)

        response
      end
    end
  end

  shared_context "when the pull request number isn't given" do
    context "when the pull request number isn't given" do
      let(:params) do
        {
          autofix_job_id: autofix_job.id,
          github_repo_id: autofix_job.pull_request.repo.github_id,
        }
      end

      it "returns an invalid argument error" do
        expect(response).to be_a(Twirp::Error)
        expect(response.code).to be(:invalid_argument)
        expect(response.msg).to eql("github_pull_request_number is required")
      end

      it "records a stage error" do
        expect(AutofixSuggestionJob::Stages).to receive(:record_error).
          with(hash_including(stage: stage))
        expect(AutofixSuggestionJob::Stages).not_to receive(:record_success)

        response
      end
    end
  end

  shared_context "when the autofix job doesn't match the pull request number" do
    context "when the autofix job doesn't match the pull request number" do
      let(:params) do
        {
          autofix_job_id: autofix_job.id,
          github_repo_id: autofix_job.pull_request.repo.github_id,
          github_pull_request_number: autofix_job.pull_request.github_number + 1,
        }
      end

      it "returns a not found error" do
        expect(response).to be_a(Twirp::Error)
        expect(response.code).to be(:not_found)
        expect(response.msg).to eql("AutofixSuggestionJob ##{autofix_job.id} was not found")
      end

      it "records a stage error" do
        expect(AutofixSuggestionJob::Stages).to receive(:record_error).
          with(hash_including(stage: stage))
        expect(AutofixSuggestionJob::Stages).not_to receive(:record_success)

        response
      end
    end
  end

  shared_context "when the repository id isn't given" do
    context "when the repository id isn't given" do
      let(:params) do
        {
          autofix_job_id: autofix_job.id,
          github_pull_request_number: autofix_job.pull_request.github_number,
        }
      end

      it "returns an invalid argument error" do
        expect(response).to be_a(Twirp::Error)
        expect(response.code).to be(:invalid_argument)
        expect(response.msg).to eql("github_repo_id is required")
      end
    end
  end

  shared_context "when the autofix job doesn't match the repository id" do
    context "when the autofix job doesn't match the repository id" do
      let(:params) do
        {
          autofix_job_id: autofix_job.id,
          github_repo_id: autofix_job.pull_request.repo.github_id + 1,
          github_pull_request_number: autofix_job.pull_request.github_number,
        }
      end

      it "returns a not found error" do
        expect(response).to be_a(Twirp::Error)
        expect(response.code).to be(:not_found)
        expect(response.msg).to eql("AutofixSuggestionJob ##{autofix_job.id} was not found")
      end

      it "records a stage error" do
        expect(AutofixSuggestionJob::Stages).to receive(:record_error).
          with(hash_including(stage: stage))
        expect(AutofixSuggestionJob::Stages).not_to receive(:record_success)

        response
      end
    end
  end

  shared_examples "records a stage success" do
    it "records a stage success" do
      # in order to set an expectation on the test object we need to
      # also stub the DB lookup to return this exact object
      allow(handler).to receive(:find_autofix_job).
        and_return(autofix_job)
      expect(autofix_job).to receive(:observe_stage).
        with(stage: stage).
        and_call_original

      expect(AutofixSuggestionJob::Stages).to receive(:record_success).
        with(stage: stage)

      response
    end
  end

  describe "#get_suggested_fix" do
    subject(:response) do
      service.call_rpc :GetSuggestedFix, params
    end

    let(:stage) { AutofixSuggestionJob::Stages::VIEW_ANNOTATION }

    it "returns suggested fixes for the autofix job" do
      expect(response.suggested_fix.autofix_job_id).to be(autofix_job.id)
      expect(response.suggested_fix.id).to be(suggested_fix.id)
    end

    it "includes suggested fix files" do
      expected_files_attrs = suggested_fix.suggested_fix_files.map do |f|
        { file_path: f.file_path, diff_content: f.diff_content }
      end
      response_files_attrs = response.suggested_fix.files.map do |f|
        { file_path: f.file_path, diff_content: f.diff_content }
      end

      expect(response_files_attrs).to match_array(expected_files_attrs)
    end

    it "includes dependency metadata" do
      expected_dependency_attrs = JSON.parse(suggested_fix.dependency_metadata)
      response_dependency_attrs = response.suggested_fix.dependency_metadata.map do |metadata|
        { "name" => metadata.name, "version" => metadata.version }
      end

      expect(response_dependency_attrs).to match_array(expected_dependency_attrs)
    end

    it "returns an error for invalid JSON in dependency metadata" do
      suggested_fix.update(dependency_metadata: "[")

      expect(response).to be_a(Twirp::Error)
      expect(response.code).to be(:internal)
    end

    include_examples "records a stage success"
    include_examples "when the autofix job doesn't exist"
    include_examples "when the autofix job id is not given"
    include_examples "when the suggested fix doesn't exist"
    include_examples "when the pull request number isn't given"
    include_examples "when the autofix job doesn't match the pull request number"
    include_examples "when the repository id isn't given"
    include_examples "when the autofix job doesn't match the repository id"
  end

  describe "#apply_suggested_fix" do
    subject(:response) do
      service.call_rpc :ApplySuggestedFix, params
    end

    let(:stage) { AutofixSuggestionJob::Stages::APPROVE_FIX }

    it "marks the suggested fix as applied" do
      expect(response.success).to be(true)

      suggested_fix.reload
      expect(suggested_fix.review_status_approved?).to be(true)
    end

    include_examples "records a stage success"
    include_examples "when the autofix job doesn't exist"
    include_examples "when the autofix job id is not given"
    include_examples "when the suggested fix doesn't exist"
    include_examples "when the pull request number isn't given"
    include_examples "when the autofix job doesn't match the pull request number"
    include_examples "when the repository id isn't given"
    include_examples "when the autofix job doesn't match the repository id"
  end

  describe "#dismiss_suggested_fix" do
    subject(:response) do
      service.call_rpc :DismissSuggestedFix, params
    end

    let(:stage) { AutofixSuggestionJob::Stages::DISMISS_FIX }

    it "marks the suggested fix as dismissed" do
      expect(response.success).to be(true)

      suggested_fix.reload
      expect(suggested_fix.review_status_dismissed?).to be(true)
    end

    include_examples "records a stage success"
    include_examples "when the autofix job doesn't exist"
    include_examples "when the autofix job id is not given"
    include_examples "when the suggested fix doesn't exist"
    include_examples "when the pull request number isn't given"
    include_examples "when the autofix job doesn't match the pull request number"
    include_examples "when the repository id isn't given"
    include_examples "when the autofix job doesn't match the repository id"
  end
end
