# frozen_string_literal: true

require "rails_helper"
require "chatops/controller/rspec"

RSpec.describe ChatopsController, :cloud do
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper

  include_context "chatops controller"

  context "setup" do
    let!(:account) do
      FactoryBot.create(
        :account,
        :active,
        github_login: "rails",
        account_type: "user"
      )
    end

    let!(:repository) do
      FactoryBot.create(:repo, :active, account: account, name: "rails")
    end

    let!(:another_repository) do
      FactoryBot.create(:repo, :active, account: account, name: "another_repo")
    end

    let(:github_client) { instance_double("Octokit::Client") }
    let(:find_or_create_account) { instance_double("FindOrCreateAccount") }
    let(:find_or_create_repo) { instance_double("FindOrCreateRepo") }
    let(:process_config_file) { instance_double("ProcessConfigFile") }
    let(:activate_account) { instance_double("ActivateAccount") }

    before do
      clear_enqueued_jobs

      allow(GitHubHelpers::ClientWithRetries).to receive(:new).and_return(github_client)
      allow(github_client).to receive(:find_repository_installation).with("rails/rails").and_return(repository)
      allow(github_client).to receive(:find_repository_installation).with("rails/another_repo").
        and_return(another_repository)
      allow(github_client).to receive(:find_repository_installation).with("django/django").and_raise(Octokit::NotFound)
      allow(github_client).to receive(:repo).and_return(repository)

      allow(ActivateAccount).to receive(:new).and_return(activate_account)
      allow(activate_account).to receive(:run)

      allow(ProcessConfigFile).to receive(:new).and_return(process_config_file)
      allow(process_config_file).to receive(:run)
    end

    context "when given just an account name" do
      it "explains when an account doesn't exist" do
        chat "dependabot setup django", "user", "#dependabot-ops"

        expect(chatop_error).to include(
          "`django` is not a valid repository name."
        )
      end
    end

    context "when given a name with owner" do
      it "explains when an account doesn't exist on the monolith" do
        chat "dependabot setup django/django", "user", "#dependabot-ops"

        allow(FindOrCreateAccount).to receive(:new).and_return(find_or_create_account)
        allow(find_or_create_account).to receive(:run).and_raise(Octokit::NotFound)

        expect(chatop_error).to include(
          "Dependabot is not enabled for `django/django`."
        )
      end

      it "enqueues a job to onboard the account when it exists" do
        allow(FindOrCreateAccount).to receive(:new).and_return(find_or_create_account)
        allow(find_or_create_account).to receive(:run).and_return(account)
        allow(FindOrCreateRepo).to receive(:new).and_return(find_or_create_repo)
        allow(find_or_create_repo).to receive(:run).and_return(repository)

        chat "dependabot setup rails/rails", "user", "#dependabot-ops"

        expect(chatop_response).to include(
          "Enqueued a setup job for the repository `rails/rails`"
        )
      end
    end

    context "when given multiple names with owners" do
      it "enqueues jobs to setup all repositories when they exist" do
        allow(FindOrCreateAccount).to receive(:new).and_return(find_or_create_account)
        allow(find_or_create_account).to receive(:run).and_return(account)
        allow(FindOrCreateRepo).to receive(:new).with(github_repo: repository).and_return(find_or_create_repo)
        allow(FindOrCreateRepo).to receive(:new).with(github_repo: another_repository).and_return(find_or_create_repo)
        allow(find_or_create_repo).to receive(:run).and_return(repository)

        chat "dependabot setup rails/rails,rails/another_repo", "user", "#dependabot-ops"

        expect(chatop_response).to include(
          "Enqueued a setup job for the repository `rails/rails`.",
          "Enqueued a setup job for the repository `rails/another_repo`."
        )
      end
    end
  end
end
