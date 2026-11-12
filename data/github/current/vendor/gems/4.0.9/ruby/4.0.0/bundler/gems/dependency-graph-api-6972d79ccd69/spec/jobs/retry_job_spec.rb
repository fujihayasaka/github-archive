require "rails_helper"

describe RetryJob, type: :job do
  include ActiveJob::TestHelper

  before do
    # Setup to test retry logic for ClearDependenciesJob
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

  describe "when a retryable error is encountered" do
    it "retries a ClearDependenciesJob 5 times" do
      allow_any_instance_of(ClearDependenciesJob).to receive(:perform).and_raise(
        Aqueduct::Client::RequestError.new(Twirp::Error.internal("OH NO"))
      )
      expect(Repository.where(github_repository_id: 101)).to_not be_empty

      assert_performed_jobs 5 do
        ClearDependenciesJob.perform_later(101) rescue nil
      end

      expect(Repository.where(github_repository_id: 101)).to_not be_empty
    end
  end

  describe "when a non-retryable error is encountered" do
    it "executes a job once and does not retry when no error encountered" do
      expect(Repository.where(github_repository_id: 101)).to_not be_empty
      expect(Repository.where(github_repository_id: 101).first.manifests).to_not be_empty

      ClearDependenciesJob.perform_now(101)

      expect(Repository.where(github_repository_id: 101)).to_not be_empty
      expect(Repository.where(github_repository_id: 101).first.manifests).to be_empty
    end

    it "executes a job once and does not retry when no error encountered" do
      allow_any_instance_of(ClearDependenciesJob).to receive(:perform).and_raise(
        StandardError.new("OH NO I AM NOT RETRYABLE")
      )
      assert_performed_jobs 1 do
        ClearDependenciesJob.perform_later(101) rescue nil
      end
      expect(Repository.where(github_repository_id: 101)).to_not be_empty
    end
  end
end
