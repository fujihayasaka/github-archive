require "rails_helper"

describe ProcessManifestJob, type: :job do
  include ActiveJob::TestHelper

  let (:manifest_change1) do
    {
      manifest_file: {
        filename: "Gemfile",
        path: "Gemfile",
        git_ref: "2c3ed2",
        pushed_at: {
          seconds: Time.new(2021, 04, 01).to_i,
        },
        blob_oid: "abcde123456"
      },
      repository_id: 600,
      owner_id: 1234,
      repository_nwo: "github/github",
      repository_stargazer_count: 1301,
      repository_private: false,
      repository_fork: false,
      is_backfill: false
    }
  end
  let (:manifest_change2) do
    {
      repository_id: 5141,
      repository_private: false,
      repository_fork: false,
      manifest_file: {
        filename: "Gemfile",
        path: "/src/Gemfile",
        git_ref: "a03a7e5040612362f2f9f81e5b611016c16b",
        pushed_at: {
          seconds: Time.new(2021, 04, 16).to_i,
        },
        blob_oid: "123456abcde",
      },
      repository_nwo: "carlsagan/thecosmos",
      repository_stargazer_count: 999,
      owner_id: 231,
      is_backfill: false
    }
  end

  let (:responses_helper) { BlobOperationsResponseHelper.new }
  let (:blob_provider) { double(BlobOperations::Spokes::Client) }
  let (:blob_response1) do
    responses_helper.blob_response(
      content: "gem 'rails', '~> 7.0'",
      oid: "2c3ed2",
      size_bytes: 20
    )
  end
  let (:blob_response2) do
    responses_helper.blob_response(
      content: "gem 'therubyracer', '>= 0.9.2'",
      oid: "a03a7e5040612362f2f9f81e5b611016c16b",
      size_bytes: 200
    )
  end

  before do
    factory do
      # Create factories used by the manifest change messages
      given_repository(github_repository_id: 600)
      given_repository(github_repository_id: 5141)
    end

    # stub out the blob provider
    allow_any_instance_of(ProcessManifestJob).to receive(:blob_provider).and_return(blob_provider)
    allow(blob_provider).to receive(:get_blob).with(repository_id: 600, oid: "abcde123456").and_return(blob_response1)
    allow(blob_provider).to receive(:get_blob).with(repository_id: 5141, oid: "123456abcde").and_return(blob_response2)
  end

  after do
    clear_enqueued_jobs
  end

  it "enqueues manifest into ecosystem-specific queue" do
    ProcessManifestJob.perform_later(manifest_change1)
    expect(ProcessManifestJob).to have_been_enqueued.on_queue("dependency-graph_test_manifest_rubygems")
  end

  it "parses and loads a manifest" do
    expect {
      ProcessManifestJob.perform_now(manifest_change1)
    }.to change { Manifest.count }.by(1)

    manifest_1 = get_manifest(repo_id: 600, ref: "2c3ed2")
    expect(manifest_1.package_manager).to eq Types::PackageManager[:rubygems]
    expect(manifest_1.manifest_type).to eq Types::Manifest[:gemfile]
    expect(manifest_1.last_pushed_at).to eq Time.new(2021, 04, 01)
    expect(manifest_1.filename).to eq "Gemfile"
    expect(manifest_1.revision).to eq 0
  end

  it "will create a repository for a manifest if it does not already exist" do
    manifest_change = manifest_change1
    manifest_change[:repository_id] = 9999

    allow(blob_provider).to receive(:get_blob).with(repository_id: 9999, oid: "abcde123456").and_return(blob_response1)

    expect(Repository.find_by(github_repository_id: 9999)).to be_nil

    expect {
      ProcessManifestJob.perform_now(manifest_change)
    }.to change { Repository.count }.by(1)

    repository = Repository.find_by(github_repository_id: 9999)

    expect(repository.github_repository_id).to eq 9999
    expect(repository.github_owner_id).to eq 1234
    expect(repository.nwo).to eq "github/github"
    expect(repository.public).to eq true
  end

  it "scrubs non-UTF-8 blob content obtained from Spokes" do
    response = responses_helper.blob_response(
      content: file_fixture("CargoUtf8.toml").read.force_encoding(Encoding::ASCII_8BIT),
      oid: "2c3ed2",
      size_bytes: 20
    )
    allow(blob_provider).to receive(:get_blob).with(repository_id: 777, oid: "2c3ed2").and_return(response)

    manifest_change = {
      repository_id: 777,
      repository_private: false,
      repository_fork: false,
      manifest_file: {
        filename: "Cargo.toml",
        path: "",
        git_ref: "a03a7e5040612362f2f9f81e5b611016c16b",
        pushed_at: {
          seconds: Time.new(2021, 04, 16).to_i,
        },
        blob_oid: "2c3ed2",
      },
      repository_nwo: "github/utf8orbust",
      repository_stargazer_count: 1,
      owner_id: 888,
      is_backfill: false
    }

    expect {
      ProcessManifestJob.perform_now(manifest_change)
    }.to change { Manifest.count }.by(1)
  end
end
