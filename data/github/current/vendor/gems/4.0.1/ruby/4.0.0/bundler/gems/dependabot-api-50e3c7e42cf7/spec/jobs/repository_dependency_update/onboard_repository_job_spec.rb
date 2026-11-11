# frozen_string_literal: true

require "rails_helper"

RSpec.describe RepositoryDependencyUpdate::OnboardRepositoryJob do
  include ActiveJob::TestHelper

  let(:access_token_url) do
    "https://internal-api.service.iad.github.net/app/installations/#{installation_id}/access_tokens"
  end

  let(:owner_github_id) { 27347476 }
  let(:owner_type) { "org" }
  let(:repository_github_id) { 88632334 }
  let(:installation_id) { 42 }

  let(:hydro_payload) do
    hydro_fixture(
      name: "push",
      schema: "github.v1.RepositoryVulnerabilityAlertCreate"
    )
  end

  let(:original_message) do
    instance_double(
      Hydro::Consumer::ConsumerMessage,
      value: hydro_payload,
      timestamp: Time.now.utc,
      headers: { "X-GitHub-Tenant-ID" => "1234", "X-GitHub-Tenant" => "lugman-inc" }
    )
  end

  let(:dependency_update) do
    ::HydroHandlers::GitHub::DependencyUpdate.from_message(original_message)
  end

  let(:advisory) do
    ::HydroHandlers::GitHub::SecurityVulnerability.from_message(original_message)
  end

  let(:user) do
    ::HydroHandlers::GitHub::User.from_message(original_message)
  end

  let(:repository) do
    ::HydroHandlers::GitHub::Repository.from_message(original_message, owner: user)
  end

  let(:job) do
    described_class.new(
      dependency_update: dependency_update,
      advisory: advisory,
      user: user,
      repository: repository
    )
  end

  before do
    # We cache access tokens, so let's make sure we clear them out between tests
    Rails.cache.clear
    stub_monolith_feature(
      :dependabot_global_app_onboarding,
      actor: FeatureFlags::Actor::User.new(owner_github_id),
      enabled: false
    )
  end

  context "when the installation is ready" do
    before do
      stub_request(:post, access_token_url).to_return(
        status: 200,
        body: erb_fixture("github_responses/installation_access_token.json"),
        headers: { "Content-Type" => "application/json" }
      )
    end

    it "invokes VulnerabilityAlertHandler" do
      mock_handler = instance_double(VulnerabilityAlertHandler)
      allow(VulnerabilityAlertHandler).to receive(:new).with(
        dependency_update: dependency_update,
        advisory: advisory,
        user: user,
        repository: repository
      ).and_return(mock_handler)
      expect(mock_handler).to receive(:create_security_update_job)

      job.perform_now
    end
  end

  context "when the installation is not ready for the Account" do
    before do
      stub_request(:post, access_token_url).to_return(
        status: 404,
        body: fixture("github_responses/not_found.json"),
        headers: { "Content-Type" => "application/json" }
      )
    end

    it "retries the job" do
      expect { job.perform_now }.to have_enqueued_job(described_class)
    end

    it "raises when retries are exhaused" do
      perform_enqueued_jobs do
        expect do
          job.perform_now
        end.to raise_error(
          described_class::InstallationNotFound,
          "Dependabot is not installed on Organization ID #{owner_github_id}"
        )
      end
    end
  end

  context "without an existing account with global app onboarding" do
    let(:global_access_token_url) { "https://internal-api.service.iad.github.net/app/global/access_tokens" }
    let(:user_url) { "https://internal-api.service.iad.github.net/user/#{owner_github_id}" }
    let(:json_header) { { "Content-Type" => "application/json" } }

    before do
      stub_monolith_feature(
        :dependabot_global_app_onboarding,
        actor: FeatureFlags::Actor::User.new(owner_github_id),
      )

      stub_request(:post, global_access_token_url).
        with(body: { target_id: owner_github_id }.to_json).
        to_return(
          status: 200,
          body: erb_fixture("github_responses/global_access_token.json"),
          headers: json_header,
        )
      stub_request(:get, user_url).
        to_return(
          status: 200,
          body: fixture("github_responses/user_by_id.json").gsub("30846345", owner_github_id.to_s),
          headers: json_header,
        )
    end

    it "invokes VulnerabilityAlertHandler" do
      mock_handler = instance_double(VulnerabilityAlertHandler)
      allow(VulnerabilityAlertHandler).to receive(:new).with(
        dependency_update: dependency_update,
        advisory: advisory,
        user: user,
        repository: repository
      ).and_return(mock_handler)
      expect(mock_handler).to receive(:create_security_update_job)

      job.perform_now
    end
  end

  context "when the installation is not ready for the Repository" do
    before do
      stub_request(:post, access_token_url).to_return(
        status: 422,
        body: fixture("github_responses/installation_access_token_repo_inaccessible.json"),
        headers: { "Content-Type" => "application/json" }
      )
    end

    it "retries the job" do
      expect { job.perform_now }.to have_enqueued_job(described_class)
    end

    it "raises when retries are exhaused" do
      perform_enqueued_jobs do
        expect do
          job.perform_now
        end.to raise_error(
          described_class::InstallationCannotAccessRepo,
          "Dependabot installation on Organization ID #{owner_github_id} " \
          "cannot access Repository ID #{repository_github_id}"
        )
      end
    end
  end

  context "when the installation is not ready for the Repository but the account is global app enabled" do
    before do
      stub_monolith_feature(
        :dependabot_global_app_onboarding,
        actor: FeatureFlags::Actor::User.new(owner_github_id),
      )
      FactoryBot.create(:account, :active,
                        github_id: owner_github_id,
                        account_type: owner_type,
                        installation_id: Account::GLOBAL_APP_INSTALLATION_ID,)
    end

    it "invokes VulnerabilityAlertHandler" do
      mock_handler = instance_double(VulnerabilityAlertHandler)
      allow(VulnerabilityAlertHandler).to receive(:new).with(
        dependency_update: dependency_update,
        advisory: advisory,
        user: user,
        repository: repository
      ).and_return(mock_handler)
      expect(mock_handler).to receive(:create_security_update_job)

      job.perform_now
    end
  end

  context "when the repository has already been onboarded" do
    before do
      account = FactoryBot.create(:account, github_id: owner_github_id, account_type: owner_type)
      FactoryBot.create(:repo, account: account, github_id: repository_github_id)
    end

    it "skips the verification step and invokes VulnerabilityAlertHandler" do
      mock_handler = instance_double(VulnerabilityAlertHandler)
      allow(VulnerabilityAlertHandler).to receive(:new).with(
        dependency_update: dependency_update,
        advisory: advisory,
        user: user,
        repository: repository
      ).and_return(mock_handler)
      expect(mock_handler).to receive(:create_security_update_job)

      job.perform_now
    end
  end
end
