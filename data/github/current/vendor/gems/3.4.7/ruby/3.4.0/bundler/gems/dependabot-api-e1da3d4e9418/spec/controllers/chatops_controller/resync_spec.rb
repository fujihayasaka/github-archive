# frozen_string_literal: true

require "rails_helper"
require "chatops/controller/rspec"

RSpec.describe ChatopsController, :cloud do
  include ActiveSupport::Testing::TimeHelpers

  include_context "chatops controller"

  context "resync" do
    let!(:account) do
      FactoryBot.create(
        :account,
        github_login: "rails"
      )
    end

    let!(:repository) do
      FactoryBot.create(:repo, :active, account: account, name: "rails")
    end

    let!(:another_repository) do
      FactoryBot.create(:repo, :active, account: account, name: "another_repo")
    end

    context "when given just an account name" do
      it "explains when an account doesn't exist" do
        chat "dependabot resync django", "user", "#dependabot-ops"

        expect(chatop_error).to include(
          "Account `django` not found, do you need to specify a `--tenant`?"
        )
      end

      it "enqueues a job to resync the account when it exists" do
        chat "dependabot resync rails", "user", "#dependabot-ops"

        expect(chatop_response).to include(
          "Enqueued a resync job for the account 'rails'"
        )

        expect(Stafftools::ResyncAccountJob).to have_been_enqueued.with(account: account)
      end
    end

    context "when given a name with owner" do
      it "explains when an account doesn't exist" do
        chat "dependabot resync django/django", "user", "#dependabot-ops"

        expect(chatop_error).to include(
          "Account `django` not found, do you need to specify a `--tenant`?"
        )
      end

      it "explains when a repository doesn't exist" do
        chat "dependabot resync rails/django", "user", "#dependabot-ops"

        expect(chatop_error).to include(
          "Repository `rails/django` not found."
        )
      end

      it "enqueues a job to resync repository when it exists" do
        chat "dependabot resync rails/rails", "user", "#dependabot-ops"

        expect(chatop_response).to include(
          "Enqueued a resync job for the repository 'rails/rails'"
        )

        expect(Stafftools::ResyncRepoJob).to have_been_enqueued.with(account: account, github_id: repository.github_id)
      end

      it "resets the configuration when given the --force flag" do
        chat "dependabot resync rails/rails --force", "user", "#dependabot-ops"

        expect(chatop_response).to include(
          "Enqueued a resync job for the repository 'rails/rails'"
        )
        expect(ResetConfigFileJob).to have_been_enqueued.with(repo: repository)
        expect(Stafftools::ResyncRepoJob).to have_been_enqueued.with(account: account, github_id: repository.github_id)
      end
    end

    context "when given multiple names with owners" do
      it "enqueues jobs to resync all repositories when they exist" do
        chat "dependabot resync rails/rails,rails/another_repo", "user", "#dependabot-ops"

        expect(chatop_response).to include(
          "Enqueued a resync job for the repository 'rails/rails'"
        )
        expect(chatop_response).to include(
          "Enqueued a resync job for the repository 'rails/another_repo'"
        )

        expect(Stafftools::ResyncRepoJob).to have_been_enqueued.with(account: account, github_id: repository.github_id)
        expect(Stafftools::ResyncRepoJob).to have_been_enqueued.with(account: account,
                                                                     github_id: another_repository.github_id)
      end

      it "resets the configuration for all repositories when given the --force flag" do
        chat "dependabot resync rails/rails,rails/another_repo --force", "user", "#dependabot-ops"

        expect(chatop_response).to include(
          "Enqueued a resync job for the repository 'rails/rails'"
        )
        expect(chatop_response).to include(
          "Enqueued a resync job for the repository 'rails/another_repo'"
        )
        expect(ResetConfigFileJob).to have_been_enqueued.with(repo: repository)
        expect(ResetConfigFileJob).to have_been_enqueued.with(repo: another_repository)

        expect(Stafftools::ResyncRepoJob).to have_been_enqueued.with(account: account, github_id: repository.github_id)
        expect(Stafftools::ResyncRepoJob).to have_been_enqueued.with(account: account,
                                                                     github_id: another_repository.github_id)
      end
    end
  end
end
