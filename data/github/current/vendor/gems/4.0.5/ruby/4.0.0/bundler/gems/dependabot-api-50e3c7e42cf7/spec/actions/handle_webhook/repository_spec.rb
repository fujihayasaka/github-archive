# frozen_string_literal: true

require "rails_helper"

RSpec.describe HandleWebhook::Repository do
  subject(:action) { described_class.new(webhook_body: webhook_body) }

  describe "given a 'deleted' webhook" do
    let(:webhook_body) do
      hash = json_fixture("github_webhooks/repository_deleted")
      hash.deep_symbolize_keys
    end

    let!(:account) do
      FactoryBot.create(
        :account, :active,
        installation_id: installation_id,
      )
    end

    let(:installation_id) { webhook_body[:installation][:id] }

    context "when the installation is the current one" do
      it "delegates to DeactivateRepoJob" do
        expect { action.run }.
          to have_enqueued_job(DeactivateRepoJob).
          with(
            account: account,
            repo_github_id: 95046787,
            user: { "login" => "greysteil", "id" => 1144873 },
          )
      end
    end

    context "when the installation is not the current one" do
      before do
        account.transition_to!(:inactive, installation_id: installation_id)
        account.transition_to!(:active, installation_id: 123123)
      end

      it "doesn't attempt to deactivate any old update configs" do
        expect { action.run }.
          not_to have_enqueued_job(DeactivateRepoJob)
      end
    end

    context "when the installation is inactive" do
      before do
        account.transition_to!(:inactive, installation_id: installation_id)
      end

      it "doesn't attempt to deactivate any old update configs" do
        expect { action.run }.
          not_to have_enqueued_job(DeactivateRepoJob)
      end
    end

    context "when the webhook doesn't contain installation information" do
      before do
        webhook_body.delete(:installation)
      end

      context "when the repo exists" do
        let(:repo) { create(:repo, account: account, github_id: webhook_body.dig(:repository, :id)) }

        context "and the webhook repo owner id matches the account" do
          before do
            webhook_body[:repository][:owner][:id] = repo.account.github_id
          end

          it "delegates to DeactivateRepoJob" do
            expect { action.run }.
              to have_enqueued_job(DeactivateRepoJob).
              with(
                account: account,
                repo_github_id: 95046787,
                user: { "login" => "greysteil", "id" => 1144873 },
              )
          end
        end

        context "and the webhook repo owner id does not match the account" do
          before do
            webhook_body[:repository][:owner][:id] = repo.account.github_id + 1
          end

          it "doesn't attempt to deactivate any old update configs" do
            expect { action.run }.
              not_to have_enqueued_job(DeactivateRepoJob)
          end
        end
      end

      context "when the repo doesn't exist" do
        it "doesn't attempt to deactivate any old update configs" do
          expect { action.run }.
            not_to have_enqueued_job(DeactivateRepoJob)
        end
      end
    end
  end

  describe "given an 'archived' webhook" do
    let(:webhook_body) do
      hash = json_fixture("github_webhooks/repository_archived")
      hash.deep_symbolize_keys
    end

    let!(:account) do
      FactoryBot.create(
        :account, :active,
        installation_id: installation_id,
      )
    end

    let(:installation_id) { webhook_body[:installation][:id] }

    context "when the installation is the current one" do
      it "delegates to DeactivateRepoJob" do
        expect { action.run }.
          to have_enqueued_job(DeactivateRepoJob).
          with(
            account: account,
            repo_github_id: 95046787,
            user: { "login" => "greysteil", "id" => 1144873 },
          )
      end
    end

    context "when the webhook doesn't contain installation information" do
      before do
        webhook_body.delete(:installation)
      end

      context "when the repo exists" do
        let(:repo) { create(:repo, account: account, github_id: webhook_body.dig(:repository, :id)) }

        context "and the webhook repo owner id matches the account" do
          before do
            webhook_body[:repository][:owner][:id] = repo.account.github_id
          end

          it "delegates to DeactivateRepoJob" do
            expect { action.run }.
              to have_enqueued_job(DeactivateRepoJob).
              with(
                account: account,
                repo_github_id: 95046787,
                user: { "login" => "greysteil", "id" => 1144873 },
              )
          end
        end

        context "and the webhook repo owner id does not match the account" do
          before do
            webhook_body[:repository][:owner][:id] = repo.account.github_id + 1
          end

          it "doesn't attempt to deactivate any old update configs" do
            expect { action.run }.
              not_to have_enqueued_job(DeactivateRepoJob)
          end
        end
      end

      context "when the repo doesn't exist" do
        it "doesn't attempt to deactivate any old update configs" do
          expect { action.run }.
            not_to have_enqueued_job(DeactivateRepoJob)
        end
      end
    end
  end

  describe "given a 'created' webhook" do
    let(:webhook_body) do
      hash = json_fixture("github_webhooks/repository_created")
      hash.deep_symbolize_keys
    end

    let!(:account) do
      FactoryBot.create(
        :account, :active,
        installation_id: installation_id,
      )
    end

    let(:installation_id) { webhook_body[:installation][:id] }

    context "when the installation is the current one" do
      it "delegates to SetupRepoJob" do
        expect { action.run }.
          to have_enqueued_job(SetupRepoJob).
          with(
            account: account,
            github_id: 95046787,
          )
      end
    end

    context "when the webhook doesn't contain installation information" do
      before do
        webhook_body.delete(:installation)
      end

      it "no-ops" do
        expect { action.run }.not_to have_enqueued_job(SetupRepoJob)
      end
    end
  end

  describe "given an 'unarchived' webhook" do
    let(:webhook_body) do
      hash = json_fixture("github_webhooks/repository_unarchived")
      hash.deep_symbolize_keys
    end

    let!(:account) do
      FactoryBot.create(
        :account, :active,
        installation_id: installation_id,
      )
    end

    let(:installation_id) { webhook_body[:installation][:id] }

    context "when the installation is the current one" do
      it "delegates to SetupRepoJob" do
        expect { action.run }.
          to have_enqueued_job(SetupRepoJob).
          with(
            account: account,
            github_id: 95046787,
          )
      end
    end

    context "when the webhook doesn't contain installation information" do
      before do
        webhook_body.delete(:installation)
      end

      it "no-ops" do
        expect { action.run }.not_to have_enqueued_job(SetupRepoJob)
      end
    end
  end

  describe "given a 'transferred' webhook" do
    let(:webhook_body) do
      hash = json_fixture("github_webhooks/repository_transferred")
      hash.deep_symbolize_keys
    end

    context "with neither account nor repo in the DB" do
      it "no-ops" do
        expect { action.run }.not_to have_enqueued_job(TransferRepoAccountJob)
        expect { action.run }.not_to have_enqueued_job(SetupRepoJob)
      end
    end

    context "with the new account in the DB" do
      let!(:account) { FactoryBot.create(:account, :active, :dependabot) }

      it "enqueues a job to set up the repo" do
        expect { action.run }.to have_enqueued_job(SetupRepoJob)
      end

      context "and the repo being transferred in the DB, too" do
        let!(:repo) { FactoryBot.create(:repo, github_id: 145360490) }

        it "enqueues a job to resync the repo's account" do
          expect { action.run }.to have_enqueued_job(TransferRepoAccountJob)
        end
      end

      context "and no repo in the DB" do
        let!(:repository_access) do
          FactoryBot.create(
            :repository_access,
            account_id: account.id,
            github_id: 145360490,
          )
        end

        it "deletes the repository access for the given repo id" do
          expect { action.run }.to change(RepositoryAccess, :count).by(-1)
        end
      end
    end

    context "with the repo being transferred in the DB (not the account)" do
      let!(:repo) { FactoryBot.create(:repo, github_id: 145360490) }

      it "no-ops" do
        expect { action.run }.not_to have_enqueued_job(TransferRepoAccountJob)
        expect { action.run }.not_to have_enqueued_job(ResyncRepoConfigFileJob)
      end
    end
  end

  describe "given an 'edited' webhook" do
    let(:webhook_body) do
      hash = json_fixture("github_webhooks/repository_edited")
      hash.deep_symbolize_keys
    end

    context "with neither account nor repo in the DB" do
      it "no-ops" do
        expect { action.run }.not_to have_enqueued_job(SetupRepoJob)
        expect { action.run }.not_to have_enqueued_job(SynchronizeRepoStateJob)
      end
    end

    context "with the account in the DB" do
      let!(:account) { FactoryBot.create(:account, :active, :dependabot) }

      it "enqueues a job to setup the repo" do
        expect { action.run }.to have_enqueued_job(SetupRepoJob)
      end

      context "and the repo being edited in the DB, too" do
        let!(:repo) { FactoryBot.create(:repo, github_id: 145360490) }

        it "enqueues a job to resync the repo's details" do
          expect { action.run }.to have_enqueued_job(SynchronizeRepoStateJob)
        end
      end
    end

    context "with the repo being edited in the DB (not the account)" do
      let!(:repo) { FactoryBot.create(:repo, github_id: 145360490) }

      it "no-ops" do
        expect { action.run }.not_to have_enqueued_job(SetupRepoJob)
        expect { action.run }.not_to have_enqueued_job(SynchronizeRepoStateJob)
      end
    end
  end

  describe "given a 'renamed' webhook" do
    let(:webhook_body) do
      hash = json_fixture("github_webhooks/repository_renamed")
      hash.deep_symbolize_keys
    end

    context "with neither account nor repo in the DB" do
      it "no-ops" do
        expect { action.run }.not_to have_enqueued_job(SetupRepoJob)
        expect { action.run }.not_to have_enqueued_job(SynchronizeRepoStateJob)
      end
    end

    context "with the account in the DB" do
      let!(:account) { FactoryBot.create(:account, :active, :dependabot) }

      it "enqueues a job to setup the repo" do
        expect { action.run }.to have_enqueued_job(SetupRepoJob)
      end

      context "and the repo being edited in the DB, too" do
        let!(:repo) { FactoryBot.create(:repo, github_id: 145360490) }

        it "enqueues a job to resync the repo's details" do
          expect { action.run }.to have_enqueued_job(SynchronizeRepoStateJob)
        end
      end
    end

    context "with the repo being edited in the DB (not the account)" do
      let!(:repo) { FactoryBot.create(:repo, github_id: 145360490) }

      it "no-ops" do
        expect { action.run }.not_to have_enqueued_job(SetupRepoJob)
        expect { action.run }.not_to have_enqueued_job(SynchronizeRepoStateJob)
      end
    end
  end

  describe "given a 'publicized' webhook" do
    let(:webhook_body) do
      hash = json_fixture("github_webhooks/repository_publicized")
      hash.deep_symbolize_keys
    end

    let!(:account) do
      FactoryBot.create(
        :account, :active,
        installation_id: installation_id,
      )
    end

    let(:installation_id) { webhook_body[:installation][:id] }

    let!(:repository_access) do
      FactoryBot.create(
        :repository_access,
        account_id: account.id,
        github_id: 145360490,
      )
    end

    context "with an existing account in the DB" do
      it "deletes the repository access for the given repo id" do
        expect { action.run }.to change(RepositoryAccess, :count).by(-1)
      end
    end

    context "when the webhook doesn't contain installation information" do
      before do
        webhook_body.delete(:installation)
      end

      context "when the repo exists" do
        let(:repo) { create(:repo, account: account, github_id: webhook_body.dig(:repository, :id)) }

        context "and the webhook repo owner id matches the account" do
          before do
            webhook_body[:repository][:owner][:id] = repo.account.github_id
          end

          it "deletes the repository access for the given repo id" do
            expect { action.run }.to change(RepositoryAccess, :count).by(-1)
          end
        end

        context "and the webhook repo owner id does not match the account" do
          before do
            webhook_body[:repository][:owner][:id] = repo.account.github_id + 1
          end

          it "does not delete the repository access for the given repo id" do
            expect { action.run }.not_to change(RepositoryAccess, :count)
          end
        end
      end

      context "when the repo doesn't exist" do
        it "does not delete the repository access for the given repo id" do
          expect { action.run }.not_to change(RepositoryAccess, :count)
        end
      end
    end
  end
end
