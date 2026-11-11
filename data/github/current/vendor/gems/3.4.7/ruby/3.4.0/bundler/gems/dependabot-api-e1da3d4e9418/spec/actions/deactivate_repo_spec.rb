# frozen_string_literal: true

require "rails_helper"
require "github_helpers"

RSpec.describe DeactivateRepo do
  subject(:action) { described_class.new(account: account, repo_github_id: repo.github_id, user: user) }

  let(:repo) { FactoryBot.create(:repo, github_id: 88632334) }
  let(:user) { { "login" => "octocat", "id" => 1 } }
  let(:account) { repo.account }
  let!(:repository_access) do
    FactoryBot.create(
      :repository_access,
      account_id: account.id,
      github_id: repo.github_id,
    )
  end
  let!(:update_config) do
    FactoryBot.create(:update_config, :active, repo: repo)
  end

  it "marks the update config as deleted" do
    expect { action.run }.
      to change { update_config.current_state(force_reload: true) }.
      from("active").to("deleted")
  end

  it "deletes the repo from selected private repositories" do
    expect { action.run }.
      to change(RepositoryAccess, :count).by(-1)
  end

  it "reports metrics" do
    expect(MetricsClient).to receive(:increment).with("repository.deactivated")

    action.run
  end
end
