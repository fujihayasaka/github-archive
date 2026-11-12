require "rails_helper"
require "db_helpers"
require_relative "../../lib/monolith/repositories"

describe ActionsPackageJob do
  include ActiveJob::TestHelper
  let (:client) { BlobOperations::Spokes::Client.new }
  let (:package_loader) { Ingest::PackageLoader.new(nil) }

  before do
    allow_any_instance_of(described_class).to receive(:client).and_return(client)
    allow(client).to receive(:object_exists?).and_return(true)
  end

  setup do
    @release1 = { name: "actions/checkout", version: "3.0.0" }
    @release2 = { name: "an-org/a-repo/.github/workflows/stuff.yml", version: "1.0.0" }
    @release3 = { name: "actions/checkout", version: "3.0.1" }

    @repo1 = Repository.create(github_repository_id: 12, nwo: "actions/checkout")
    @repo2 = Repository.create(github_repository_id: 14, nwo: "an-org/a-repo")
  end

  def run_job(releases)
    perform_enqueued_jobs do
      described_class.perform_now(releases)
    end
  end

  it "creates packages" do
    run_job([@release1, @release2])

    expect(Package.count).to eq 2

    package = get_package(@release1[:name])

    expect(package).to_not be_nil
    expect(package.name).to eq @release1[:name]
    expect(package.repository_nwo).to eq @repo1.nwo
  end

  it "creates package releases" do
    run_job([@release1, @release2, @release3])

    expect(PackageRelease.count).to eq 3

    release = get_package_release(@release2[:name], @release2[:version])

    expect(release).to_not be_nil
    expect(release.name).to eq @release2[:version]
    expect(release.repository_nwo).to eq @repo2.nwo

    package = get_package(@release1[:name])
    expect(package.releases.count).to eq 2
    expect(package.releases.pluck(:name)).to include(@release1[:version], @release3[:version])
  end

  it "skips package releases that exist" do
    factory.given_package(@release1[:name], @release1[:version], :actions)
    expect(PackageRelease.count).to eq 1

    described_class.perform_now([@release1])
    expect(LoadPackageJob).to_not have_been_enqueued

    described_class.perform_now([@release3])
    expect(LoadPackageJob).to have_been_enqueued
  end

  it "skips bad packages" do
    described_class.perform_now([{ name: "jeepers/creepers", version: nil }])
    expect(LoadPackageJob).to_not have_been_enqueued
  end

  it "skips if repo doesn't exist" do
    allow(client).to receive(:object_exists?).and_return(false)
    allow_any_instance_of(Monolith::Repositories).to receive(:find_repositories_by_name).and_return([])
    described_class.perform_now([{ name: "thisdoesntexist/whatever", version: "300000.1" }])
    expect(LoadPackageJob).to_not have_been_enqueued
  end

  it "doesn't skip if repo exist" do
    allow(client).to receive(:object_exists?).and_return(true)
    described_class.perform_now([{ name: "actions/checkout", version: "v1.2" }])
    expect(LoadPackageJob).to have_been_enqueued
  end
end
