# frozen_string_literal: true

require "rails_helper"

RSpec.describe RepositoryAccessService::V1::Handler do
  let(:service) do
    DependabotApi::V1::RepositoryAccessServiceService.new(described_class.new)
  end

  describe "get_repository_access" do
    context "without owner_github_id" do
      subject(:res) { service.call_rpc :GetRepositoryAccess, req }

      let(:req) do
        DependabotApi::V1::GetRepositoryAccessRequest.new
      end

      it "is not editable" do
        expect(res.access_editable).to be false
      end
    end

    context "with valid request" do
      subject(:res) { service.call_rpc :GetRepositoryAccess, req }

      let(:account) { FactoryBot.create(:account) }
      let(:req) do
        DependabotApi::V1::GetRepositoryAccessRequest.new(
          owner_github_id: account.github_id,
        )
      end

      it "is editable with an empty id list" do
        expect(res.access_editable).to be true
        expect(res.repository_github_ids).to be_empty
      end

      context "with an existing RepositoryAccess" do
        let!(:repository_access) do
          FactoryBot.create(:repository_access, account: account)
        end

        it "is editable and includes the existing RepositoryAccess id" do
          expect(res.access_editable).to be true
          expect(res.repository_github_ids).to contain_exactly(repository_access.github_id)
        end
      end
    end
  end

  describe "set_selected_repositories" do
    context "without owner_github_id" do
      subject(:res) { service.call_rpc :SetSelectedRepositories, req }

      let(:req) do
        DependabotApi::V1::SetSelectedRepositoriesRequest.new
      end

      it "returns a twirp error" do
        expect(res).to be_a(Twirp::Error)
        expect(res.code).to eq(:not_found)
        expect(res.msg).to eq("owner_github_id not found")
      end
    end

    context "valid request" do
      subject(:res) { service.call_rpc :SetSelectedRepositories, req }

      let(:account) { FactoryBot.create(:account) }
      let(:repository_github_ids) { [1, 2] }
      let(:req) do
        DependabotApi::V1::SetSelectedRepositoriesRequest.new(
          owner_github_id: account.github_id,
          repository_github_ids: repository_github_ids,
        )
      end

      it { is_expected.not_to be_a(Twirp::Error) }

      it "updates database" do
        expect { service.call_rpc :SetSelectedRepositories, req }.
          to change { account.repository_accesses.pluck(:github_id) }.
          from([]).to(repository_github_ids)
      end

      context "updating RepositoryAccess" do
        subject(:res) { service.call_rpc :SetSelectedRepositories, req }

        let(:retained_access) do
          FactoryBot.create(:repository_access, account: account)
        end
        let(:removed_access) do
          FactoryBot.create(:repository_access, account: account)
        end
        let(:req) do
          DependabotApi::V1::SetSelectedRepositoriesRequest.new(
            owner_github_id: account.github_id,
            repository_github_ids: [retained_access.github_id],
          )
        end

        it { is_expected.not_to be_a(Twirp::Error) }

        it "updates database" do
          expect { service.call_rpc :SetSelectedRepositories, req }.
            to change { account.repository_accesses.pluck(:github_id) }.
            from([retained_access.github_id, removed_access.github_id]).
            to([retained_access.github_id])
        end
      end

      context "clearing RepositoryAccess" do
        subject(:res) { service.call_rpc :SetSelectedRepositories, req }

        let(:removed_access) do
          FactoryBot.create(:repository_access, account: account)
        end
        let(:req) do
          DependabotApi::V1::SetSelectedRepositoriesRequest.new(
            owner_github_id: account.github_id,
            repository_github_ids: [],
          )
        end

        it { is_expected.not_to be_a(Twirp::Error) }

        it "empties database" do
          expect { service.call_rpc :SetSelectedRepositories, req }.
            to change { account.repository_accesses.pluck(:github_id) }.
            from([removed_access.github_id]).
            to([])
        end
      end
    end
  end
end
