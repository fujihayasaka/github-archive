# frozen_string_literal: true

require "rails_helper"

RSpec.describe MarkGitHubJobErrored do
  subject(:action) do
    described_class.new(update_job: job, error_hash: error_hash)
  end

  let(:job) { FactoryBot.create(:update_job, github_request_id: 123) }
  let(:dependency_update_body) do
    fixture fixture_path_for("success")
  end

  let(:error_hash) do
    { "error-type" => error_type, "error-detail" => error_detail }
  end
  let(:error_type) { "dependency_file_not_found" }
  let(:error_detail) { { "file-path" => "Gemfile" } }

  let(:github_graphql_endpoint) { Dependabot::Application.target_github_graphql_endpoint }

  def fixture_path_for(scenario)
    "github_responses/mark_github_job_errored/#{scenario}.json"
  end

  before do
    allow(GitHubHelpers).to receive(:installation_access_token_for).
      and_return("token")
    stub_request(:post, github_graphql_endpoint).
      to_return(
        status: 200,
        body: dependency_update_body,
        headers: { "Content-Type" => "application/json" },
      )
  end

  context "happy path" do
    it "returns a truthy value" do
      expect(action.run).to be_truthy
    end
  end

  context "with a dry run update job" do
    let(:job) { FactoryBot.create(:update_job, dry_run: true) }

    before { action.run }

    it "does not notify GitHub" do
      expect(WebMock).
        not_to have_requested(:post, github_graphql_endpoint)
    end
  end

  context "with an inactive account" do
    before do
      account = job.update_config.repo.account
      current_installation_id = account.current_installation_id
      account.transition_to!(
        :inactive,
        installation_id: current_installation_id,
      )
    end

    it "does not notify GitHub" do
      action.run
      expect(WebMock).
        not_to have_requested(:post, github_graphql_endpoint)
    end
  end

  context "when the install id is no longer valid" do
    before do
      allow(GitHubHelpers).
        to receive(:installation_access_token_for).
        and_raise(GitHubHelpers::InvalidInstallationId.new(1))
    end

    it "syncronises repo and does not notify GitHub" do
      result = SynchronizeRepoState::SynchronizeRepoStateResult.error(
        reason: SynchronizeRepoState::ACCOUNT_OUT_OF_SYNC
      )
      dummy_repo_synchronizer = double(run: result)
      expect(SynchronizeRepoState).
        to receive(:new).
        with(repo: job.update_config.repo,
             event_source: "action.mark_github_job_errored").
        and_return(dummy_repo_synchronizer)
      expect(WebMock).
        not_to have_requested(:post, github_graphql_endpoint)
      action.run
    end
  end

  context "with an update job without a github_request_id" do
    let(:job) { FactoryBot.create(:update_job, github_request_id: nil) }

    before { action.run }

    it "does not notify GitHub" do
      expect(WebMock).
        not_to have_requested(:post, github_graphql_endpoint)
    end
  end

  context "when the response contains unexpected validation errors" do
    let(:dependency_update_body) do
      fixture fixture_path_for("errors")
    end

    it "raises an exception" do
      expect { action.run }.
        to raise_error(described_class::GitHubValidationError)
    end
  end

  context "when the response is unprocessible" do
    context "as the app isn't installed" do
      let(:dependency_update_body) do
        fixture fixture_path_for("unprocessable_app_not_installed")
      end

      it "raises an exception" do
        expect { action.run }.
          to raise_error(described_class::GitHubAppError, /not installed/)
      end
    end

    context "as the job is not found" do
      let(:dependency_update_body) do
        fixture fixture_path_for("unprocessable_job_not_found")
      end

      it "does not raise an exception" do
        expect { action.run }.
          not_to raise_error
      end
    end

    context "as the job is already complete" do
      let(:dependency_update_body) do
        fixture fixture_path_for("unprocessable_already_complete")
      end

      it "raises an exception" do
        expect { action.run }.
          to raise_error(described_class::StateError,
                         "Update ID 'X' cannot be marked as errored " \
                         "as it is currently 'complete'.")
      end
    end

    context "as the job is already errored" do
      let(:dependency_update_body) do
        fixture fixture_path_for("unprocessable_already_errored")
      end

      it "raises an exception" do
        expect { action.run }.
          to raise_error(described_class::StateError,
                         "Update ID 'X' has already received an error.")
      end
    end

    context "as the query was invalid" do
      let(:dependency_update_body) do
        fixture fixture_path_for("graphql_query_error")
      end

      it "raises an exception" do
        expect { action.run }.
          to raise_error(
            described_class::GraphQLQueryError,
            "Variable databaseId of type Int! was provided invalid value",
          )
      end
    end
  end
end
