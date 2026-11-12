# frozen_string_literal: true

require "rails_helper"
require "chatops/controller/rspec"

RSpec.describe ChatopsController, :cloud do
  include ActiveSupport::Testing::TimeHelpers

  include_context "chatops controller"

  let(:repo) do
    FactoryBot.create(:repo, :bump_test)
  end
  let(:account) { repo.account }

  let(:user) { "user" }
  let(:channel) { "#dependabot-ops" }
  let(:repo_nwo) { repo.full_name }

  let(:default_branch) { RunUpdater::Actions::Workflow::LATEST_VERSION_TAG }

  let(:tenant_flag) { "" }

  describe "actions set-branch" do
    subject(:run_chatop) do
      chat "dependabot actions set-branch #{repo_nwo} new-release #{tenant_flag}",
           user,
           channel
    end

    it "sets the branch override for the repository" do
      expect { run_chatop }.
        to change { RunUpdater::Actions::Workflow.get_branch_for(repo: repo) }.from(default_branch).to("new-release")

      expect(chatop_response).to start_with("dependabot/bump-test will now use the new-release branch")
    end

    context "with something that isn't a NWO" do
      let(:repo_nwo) { "hello" }

      it "returns an error" do
        run_chatop

        expect(chatop_error).to include(
          "`hello` doesn't seem to be a Name With Owner."
        )
      end
    end

    context "with an account that doesn't exist" do
      let(:repo_nwo) { "sinatra/sinatra" }

      it "returns an error" do
        run_chatop

        expect(chatop_error).to include(
          "Account `sinatra` not found, do you need to specify a `--tenant`?"
        )
      end
    end

    context "with a repo that doesn't exist" do
      let(:repo_nwo) { "#{account.github_login}/sinatra" }

      it "returns an error" do
        run_chatop

        expect(chatop_error).to include(
          "Repository `#{repo_nwo}` not found."
        )
      end
    end

    context "when the repo has a tenant" do
      let(:tenant) { FactoryBot.create(:tenant, slug: "tenant", shortcode: "a") }
      let(:account) { FactoryBot.create(:account, github_login: "org", tenant: tenant) }
      let(:repo) { FactoryBot.create(:repo, :bump_test, account: account) }
      let(:repo_now) { "org/repo" }

      it "doesn't find the repo" do
        run_chatop

        expect(chatop_error).to include(
          "Account `org` not found, do you need to specify a `--tenant`?"
        )
      end

      context "with the tenant flag" do
        let(:tenant_flag) { "--tenant tenant" }

        it "sets the branch override for the repository" do
          expect { run_chatop }.
            to change {
                 RunUpdater::Actions::Workflow.get_branch_for(repo: repo)
               }.from(default_branch).to("new-release")

          expect(chatop_response).to start_with("#{repo.full_name} will now use the new-release branch")
        end
      end

      context "with the wrong tenant flag" do
        let(:tenant_flag) { "--tenant wrong" }

        it "returns an error" do
          run_chatop

          expect(chatop_error).to include(
            "Tenant `wrong` not found on this stamp."
          )
        end
      end
    end
  end

  describe "actions clear-branch" do
    subject(:run_chatop) do
      chat "dependabot actions clear-branch #{repo_nwo}",
           user,
           channel
    end

    let(:test_branch) { "v0.0.1-alpha" }

    before do
      RunUpdater::Actions::Workflow.set_branch_for(repo: repo, branch_name: test_branch)
    end

    it "sets the branch override for the repository" do
      expect { run_chatop }.
        to change { RunUpdater::Actions::Workflow.get_branch_for(repo: repo) }.from(test_branch).to(default_branch)

      expect(chatop_response).to start_with("dependabot/bump-test will now use the `#{default_branch}`")
    end

    context "with something that isn't a NWO" do
      let(:repo_nwo) { "hello" }

      it "returns an error" do
        run_chatop

        expect(chatop_error).to include(
          "`hello` doesn't seem to be a Name With Owner."
        )
      end
    end

    context "with an account that doesn't exist" do
      let(:repo_nwo) { "sinatra/sinatra" }

      it "returns an error" do
        run_chatop

        expect(chatop_error).to include(
          "Account `sinatra` not found, do you need to specify a `--tenant`?"
        )
      end
    end

    context "with a repo that doesn't exist" do
      let(:repo_nwo) { "#{account.github_login}/sinatra" }

      it "returns an error" do
        run_chatop

        expect(chatop_error).to include(
          "Repository `#{repo_nwo}` not found."
        )
      end
    end
  end
end
