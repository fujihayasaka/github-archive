require "rails_helper"
require_relative "../../lib/manifest_deleter"

describe ProcessManifestDeletedJob, type: :job do
  include ActiveJob::TestHelper

  let(:manifest_file) {
    {
        filename: "Gemfile.lock",
        git_ref: "303cbb30c474646b4abe1ae74f6b3dc0e182c478",
        path: "",
        pushed_at: Time.now,
      }
  }
  let(:missing_manifest_file) {
    {
        filename: "pom.xml",
        git_ref: "303cbb30c474646b4abe1ae74f6b3dc0e182c500",
        path: "",
        pushed_at: Time.now,
    }
  }

  let(:manifest_id)          { 2 }
  let(:repository_id)        { 4 }
  let(:github_repository_id) { 444 }
  let(:github_owner_id)      { 555 }

  let(:delete_manifest_job_params) {
    {
      manifest_file: manifest_file,
      repository_fork: false,
      repository_id: github_repository_id,
      repository_private: false,
    }
  }

  let(:missing_manifest_job_params) {
    {
      manifest_file: missing_manifest_file,
      repository_fork: false,
      repository_id: github_repository_id,
      repository_private: false,
    }
  }

  before do
    Repository.create(
      id: repository_id,
      github_repository_id: github_repository_id,
      github_owner_id: github_owner_id)

    Manifest.create!({
      id: manifest_id,
      filename: manifest_file[:filename],
      path: manifest_file[:path],
      last_pushed_at: 1.day.ago,
      latest_git_ref: "0ac7a418dd80a2e85fa2772fc469379d810fced3",
      manifest_type: 2,   # Gemfile.lock
      package_manager: 1, # RubyGems
      revision: 1,
      repository_id: repository_id, # DG repo ID, not GH repo ID
    })

  end

  it "consumes message and deletes manifest" do
    expect {
      ProcessManifestDeletedJob.perform_now(delete_manifest_job_params)
    }.to change { Manifest.count }.by(-1)
    expect(Manifest.exists?(manifest_id)).to be_falsey
  end

  it "to no-op and log if manifest cannot be found" do
    expect(DependencyGraph.logger).to receive(:error)

    expect {
      ProcessManifestDeletedJob.perform_now(missing_manifest_job_params)
    }.to change { Manifest.count }.by(0)
    expect(Manifest.exists?(manifest_id)).to be_truthy
  end

  it "to no-op and log if repository ID is missing from the job params" do
    params = delete_manifest_job_params.clone
    params[:repository_id] = nil

    expect(DependencyGraph.logger).to receive(:error)

    expect {
      ProcessManifestDeletedJob.perform_now(missing_manifest_job_params)
    }.to change { Manifest.count }.by(0)
    expect(Manifest.exists?(manifest_id)).to be_truthy
  end
end
