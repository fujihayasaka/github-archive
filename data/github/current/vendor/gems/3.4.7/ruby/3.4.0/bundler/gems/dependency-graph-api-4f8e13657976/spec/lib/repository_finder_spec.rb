require "rails_helper"
require_relative "../../lib/repository_finder"

RSpec.configure do |c|
  c.include RepositoryFinder
end

RSpec.describe RepositoryFinder do
  let(:nwo) { "my_org/my_repo" }
  let(:github_repository_id) { 123 }

  context "when the repository exists in the database" do

    before do
      factory.given_repository(nwo: nwo, github_repository_id: github_repository_id)
    end

    it "returns the existing repository in nwo matches" do
      repo = find_repo(nwo: nwo)
      expect(repo).to be_a Repository
      expect(repo.nwo).to eq nwo
    end

    it "updates the existing repository for a duplicate github_repository_id" do
      new_nwo = "my_org/my_new_repo"

      expect(Repository.find_by(nwo: new_nwo)).to be_nil
      expect_any_instance_of(Monolith::Repositories).to receive(:find_repositories_by_name).with([new_nwo]).
        and_return([Repository.new(github_repository_id: github_repository_id, nwo: new_nwo)])

      expect { find_repo(nwo: "my_org/my_new_repo") }.not_to change { Repository.count }
      expect(Repository.find_by(nwo: nwo)).to be_nil
      expect(Repository.find_by(nwo: new_nwo)).to be_a Repository
    end
  end

  it "creates a new repository if none exists" do
    expect(Repository.find_by(nwo: nwo)).to be_nil
    expect_any_instance_of(Monolith::Repositories).to receive(:find_repositories_by_name).with([nwo]).
      and_return([Repository.new(github_repository_id: github_repository_id, nwo: nwo)])

    expect { find_repo(nwo: nwo) }.to change { Repository.count }.by(1)
    expect(Repository.find_by(nwo: nwo)).to be_a Repository
  end

  it "reports to Failbot and returns nil if the Monolith::Repositories request receives a server error" do
    expect_any_instance_of(Monolith::Repositories).
      to receive(:find_repositories_by_name).
      and_raise(Monolith::TwirpClient::Error.new("no repo for you!"))
    expect(Failbot).to receive(:report).once
    result = find_repo(nwo: nwo)
    expect(result).to be_nil
  end
end
