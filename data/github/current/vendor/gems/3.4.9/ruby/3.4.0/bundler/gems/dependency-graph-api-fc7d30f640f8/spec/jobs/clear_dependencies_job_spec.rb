require "rails_helper"

describe ClearDependenciesJob, type: :job do

  before do
    Repository.create!(github_repository_id: 101, public: false)
    factory do
      given_manifest(
        github_repo_id: 101,
        manifest_type:  :gemfile,
        filename:       "Gemfile",
        path:           "/",
        revision:       1,
        dependencies:   [
          {
            package_name: "rails",
            requirements: "~> 5.0.0",
          },
        ]
      )
    end
  end

  describe "#perform_now" do
    it "removes dependencies but not parent repo record" do
      expect(Repository.where(github_repository_id: 101)).to_not be_empty
      described_class.perform_now(101)
      expect(Repository.where(github_repository_id: 101)).to_not be_empty
      expect(Repository.where(github_repository_id: 101).first.manifests).to be_empty
    end

    it "reports to Failbot if errors" do
      allow_any_instance_of(described_class).to receive(:perform).and_raise(StandardError.new)
      expect(Failbot).to receive(:report).once.with(anything,
        "gh.aqueduct.queue.name" => "dependency-graph_test_default",
        "gh.aqueduct.job.name" => "ClearDependenciesJob"
      )
      expect { described_class.perform_now(101) }.to raise_error StandardError
    end
  end
end
