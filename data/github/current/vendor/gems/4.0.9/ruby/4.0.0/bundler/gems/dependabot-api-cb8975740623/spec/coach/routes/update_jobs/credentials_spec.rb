# frozen_string_literal: true

require "rails_helper"

RSpec.describe Routes::UpdateJobs::Credentials do
  include ProximaHelpers

  subject(:instance) { described_class.new(context) }

  let(:context) do
    { request: request, update_job: update_job, token: token }
  end

  let(:request) { instance_double(ActionDispatch::Request) }
  let(:token) { RbNaCl::Random.random_bytes(RbNaCl::SecretBox.key_bytes) }

  let(:update_job) { FactoryBot.create(:update_job, :enqueued) }
  let(:account) { update_job.update_config.account }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:json_header) { { "Content-Type" => "application/json" } }

  before do
    allow(GitHubHelpers).to receive(:access_token_for)

    stub_proxima_repo_request(repo_id: update_job.repo.github_id, fixture: "proxima_repo")

    allow_any_instance_of(DotcomRegistry).to receive(:credentials).and_return(nil) # rubocop:disable RSpec/AnyInstance
  end

  context "for an enqueued update job" do
    it { is_expected.to respond_with_status(200) }

    context "when the access token request returns a 422 error" do
      let(:access_token_url) do
        github_url + "app/global/access_tokens"
      end

      let(:response) do
        fixture(
          "github_responses/installation_access_token_unprocessable.json"
        )
      end

      let(:expected_error) do
        /No repositories were provided/
      end

      before do
        stub_request(:post, access_token_url).
          to_return(status: 422, headers: json_header, body: response)

        allow(GitHubHelpers).to receive(:access_token_for).
          and_call_original
      end

      it { is_expected.to respond_with_status(422) }
      it { is_expected.to respond_with_body_that_matches expected_error }

      it "creates an update job error" do
        expect { instance.call }.to change(UpdateJobError, :count).by(1)

        update_job_error = UpdateJobError.last
        expect(update_job_error.error_type).to eq("runner_error")
        expect(update_job_error.error_details).
          to eq({
                  "message" => "POST #{github_url}app/global/access_tokens: 422 - No repositories were provided. "\
                  "// See: https://developer.github.com/v3/apps/#create-a-new-installation-token",
                })
      end
    end

    context "the credentials reference a missing secret" do
      before do
        update_config = update_job.update_config
        update_config.update!(all_registries: true)
        FactoryBot.create(
          :registry,
          source: update_config.repo,
        )
        stub_request(:get, github_url + "user/#{update_config.account.github_id}").
          to_return(status: 200, body: fixture("github_responses/user_by_id.json"), headers: json_header)

        stub_request(:get, github_url + "repositories/#{update_config.repo.github_id}").
          to_return(status: 200, body: fixture("github_responses/repo.json"), headers: json_header)

        allow_any_instance_of(SecretFetcher). # rubocop:disable RSpec/AnyInstance
          to receive(:fetch).and_raise(SecretFetcher::SecretNotFound, "MISSING_SECRET_NAME")
      end

      it { is_expected.to respond_with_status(422) }
      it { is_expected.to respond_with_body_that_matches(/MISSING_SECRET_NAME/) }

      it "creates an update job error" do
        expect { instance.call }.to change(UpdateJobError, :count).by(1)

        update_job_error = UpdateJobError.last
        expect(update_job_error.error_type).to eq("secret_not_found")
        expect(update_job_error.error_details).to eq({ "secret-name" => "MISSING_SECRET_NAME" })
      end
    end

    context "the credentials could not retrieved a secret" do
      before do
        update_config = update_job.update_config
        update_config.update!(all_registries: true)
        FactoryBot.create(
          :registry,
          source: update_config.repo,
        )
        stub_request(:get, github_url + "user/#{update_config.account.github_id}").
          to_return(status: 200, body: fixture("github_responses/user_by_id.json"), headers: json_header)

        stub_request(:get, github_url + "repositories/#{update_config.repo.github_id}").
          to_return(status: 200, body: fixture("github_responses/repo.json"), headers: json_header)

        allow_any_instance_of(SecretFetcher). # rubocop:disable RSpec/AnyInstance
          to receive(:fetch).and_raise(SecretFetcher::SecretNotRetrieved, "Failed to fetch secrets for repository")
      end

      it { is_expected.to respond_with_status(422) }
      it { is_expected.to respond_with_body_that_matches(/Failed to fetch secrets for/) }

      it "creates an update job error" do
        expect { instance.call }.to change(UpdateJobError, :count).by(1)

        update_job_error = UpdateJobError.last
        expect(update_job_error.error_type).to eq("secret_not_retrieved")
        expect(update_job_error.error_details).to eq({ "secret-name" => "Failed to fetch secrets for repository" })
      end
    end

    context "the credentials reference an invalid secret" do
      before do
        update_config = update_job.update_config
        update_config.update!(all_registries: true)
        FactoryBot.create(
          :registry,
          source: update_config.repo,
        )
        stub_request(:get, github_url + "user/#{update_config.account.github_id}").
          to_return(status: 200, body: fixture("github_responses/user_by_id.json"), headers: json_header)

        stub_request(:get, github_url + "repositories/#{update_config.repo.github_id}").
          to_return(status: 200, body: fixture("github_responses/repo.json"), headers: json_header)

        allow_any_instance_of(SecretFetcher). # rubocop:disable RSpec/AnyInstance
          to receive(:fetch).and_raise(SecretFetcher::SecretNotValid, "INVALID_SECRET_NAME")
      end

      it { is_expected.to respond_with_status(422) }
      it { is_expected.to respond_with_body_that_matches(/INVALID_SECRET_NAME/) }

      it "creates an update job error" do
        expect { instance.call }.to change(UpdateJobError, :count).by(1)

        update_job_error = UpdateJobError.last
        expect(update_job_error.error_type).to eq("secret_not_valid")
        expect(update_job_error.error_details).to eq({ "secret-name" => "INVALID_SECRET_NAME" })
      end
    end

    context "the credentials reference an invalid value" do
      before do
        update_config = update_job.update_config
        update_config.update!(all_registries: true)
        FactoryBot.create(
          :registry,
          source: update_config.repo,
        )
        stub_request(:get, github_url + "user/#{update_config.account.github_id}").
          to_return(status: 200, body: fixture("github_responses/user_by_id.json"), headers: json_header)

        stub_request(:get, github_url + "repositories/#{update_config.repo.github_id}").
          to_return(status: 200, body: fixture("github_responses/repo.json"), headers: json_header)

        allow_any_instance_of(UpdateJobCredentialsSerializer). # rubocop:disable RSpec/AnyInstance
          to receive(:credentials).and_raise(UpdateJobCredentialsSerializer::CredentialsInvalid)
      end

      it { is_expected.to respond_with_status(422) }
      it { is_expected.to respond_with_body_that_matches(/Registry credentials invalid/) }

      it "creates an update job error" do
        expect { instance.call }.to change(UpdateJobError, :count).by(1)

        update_job_error = UpdateJobError.last
        expect(update_job_error.error_type).to eq("config_not_valid")
        expect(update_job_error.error_details).to eq({ "message" => "Registry credentials invalid" })
      end
    end

    context "the installation has reached the rate limit" do
      let(:json_limit_header) { { "Content-Type" => "application/json", "X-RateLimit-Reset" => "500" } }

      before do
        update_config = update_job.update_config
        update_config.update!(all_registries: true)
        FactoryBot.create(
          :registry,
          source: update_config.repo,
        )
        stub_request(:get, github_url + "user/#{update_config.account.github_id}").
          to_return(status: 403,
                    body: fixture("github_responses/forbidden_rate_limited.json"),
                    headers: json_limit_header)
      end

      it { is_expected.to respond_with_status(422) }
      it { is_expected.to respond_with_body_that_matches(/API rate limit exceeded/) }

      it "creates an update job error" do
        expect { instance.call }.to change(UpdateJobError, :count).by(1)

        update_job_error = UpdateJobError.last
        expect(update_job_error.error_type).to eq("octokit_rate_limited")
        expect(update_job_error.error_details).to eq({ "rate-limit-reset" => "500" })
      end
    end

    context "the GitHub API responds with a 404 on repo lookup" do
      before do
        update_config = update_job.update_config
        update_config.update!(all_registries: true)
        FactoryBot.create(
          :registry,
          source: update_config.repo,
        )
        stub_request(:get, github_url + "user/#{update_config.account.github_id}").
          to_return(status: 200, body: fixture("github_responses/user_by_id.json"), headers: json_header)

        stub_request(:get, github_url + "repositories/#{update_config.repo.github_id}").
          to_return(status: 404)
      end

      it { is_expected.to respond_with_status(500) }
      it { is_expected.to respond_with_body_that_matches(/Target repository was not available from the GitHub API/) }
    end

    context "the installation is unavailable" do
      before do
        update_config = update_job.update_config
        update_config.update!(all_registries: true)
        FactoryBot.create(
          :registry,
          source: update_config.repo,
        )
        fixture = fixture("github_responses/forbidden_unavailable_to_integration.json")
        stub_request(:get, github_url + "user/#{update_config.account.github_id}").
          to_return(status: 403, body: fixture, headers: json_header)
      end

      it { is_expected.to respond_with_status(403) }
      it { is_expected.to respond_with_body_that_matches(/Resource not accessible by installation/) }

      it "creates an update job error" do
        expect { instance.call }.to change(UpdateJobError, :count).by(1)

        update_job_error = UpdateJobError.last
        expect(update_job_error.error_type).to eq("resource_unavailable_to_installation")
        expect(update_job_error.error_details["message"]).to include("Resource not accessible by integration")
      end
    end
  end

  context "for a processed update job" do
    let(:update_job) { FactoryBot.create(:update_job, :processed) }

    it { is_expected.to respond_with_status(400) }
  end
end
