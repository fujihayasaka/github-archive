# frozen_string_literal: true

require "rails_helper"

RSpec.describe FindOrCreateRepo do
  subject(:action) { described_class.new(github_repo: github_repo) }

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:github_repo) { Octokit::Client.new(access_token: "junk", api_endpoint: github_url).repo(88632334) }
  let(:github_repo_data) { fixture("github_responses/repo.json") }

  before do
    stub_request(:get, github_url + "repositories/88632334").
      to_return(status: 200, body: github_repo_data, headers: json_header)
  end

  context "for a repo that already exists" do
    let!(:dependabot) { FactoryBot.create(:account, :dependabot) }
    let!(:repo) { FactoryBot.create(:repo, :bump_test, :inactive) }

    it "returns the repo" do
      expect(action.run).to eq(repo)
    end

    context "but is associated with the wrong account (due to a transfer)" do
      let!(:old_account) { FactoryBot.create(:account) }

      before { repo.update!(account: old_account) }

      it "updates the account" do
        expect { action.run }.
          to change { Repo.find(repo.id).account }.
          from(old_account).to(dependabot)
      end

      context "passed as a hash of details" do
        let(:github_repo) do
          {
            id: 88632334,
            name: "bump-test",
            private: true,
            language: nil,
            default_branch: "master",
            owner: {
              id: 27347476,
              type: "Organization",
            },
          }
        end

        it "updates the account" do
          expect { action.run }.
            to change { Repo.find(repo.id).account }.
            from(old_account).to(dependabot)
        end
      end
    end
  end

  context "for a repo that doesn't already exist" do
    context "for an account that exists" do
      let!(:account) do
        FactoryBot.create(:account, :active, :dependabot)
      end

      it "creates a new repo" do
        expect { action.run }.to change(Repo, :count).from(0).to(1)
      end

      it "returns a repo" do
        expect(action.run).to be_a(Repo)
      end

      context "passed as a hash of details" do
        let(:github_repo) do
          {
            id: 88632334,
            node_id: "MDEwOlJlcG9zaXRvcnk4ODYzMjMzNA==",
            name: "bump-test",
            private: true,
            language: nil,
            default_branch: "master",
            owner: {
              id: 27347476,
              type: "Organization",
            },
          }
        end

        it "creates a new repo" do
          expect { action.run }.to change(Repo, :count).from(0).to(1)
        end

        context "for an account with the wrong type" do
          let!(:account) do
            FactoryBot.create(:account, :active, :dependabot, :user)
          end

          it "updates the account type" do
            expect { action.run }.
              to change { account.reload.account_type }.from("user").to("org")
          end
        end
      end
    end

    context "for an account that doesn't exist" do
      it "raises" do
        expect { action.run }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
