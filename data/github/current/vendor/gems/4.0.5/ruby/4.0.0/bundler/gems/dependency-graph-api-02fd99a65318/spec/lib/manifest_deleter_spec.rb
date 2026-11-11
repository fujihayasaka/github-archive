require "rails_helper"
require_relative "../../lib/manifest_deleter"

shared_examples "a manifest deleter" do
  describe ManifestDeleter do
    let(:job_params) do
      {
        manifest_file: {
          filename: "Gemfile.lock",
          path: "",
        },
        repository_id: 1,
      }
    end

    # Mock some manifests, packages, package releases, etc for our repo.
    before do
      @our_repository = Repository.create(github_repository_id: job_params[:repository_id], github_owner_id: 10, public: false)

      @our_manifest = Manifest.create({
        filename: job_params[:manifest_file][:filename],
        path: job_params[:manifest_file][:path],
        last_pushed_at: 1.day.ago,
        latest_git_ref: "0ac7a418dd80a2e85fa2772fc469379d810fced3",
        manifest_type: 2,   # Gemfile.lock
        package_manager: 1, # RubyGems
        revision: 1,
        repository_id: @our_repository.id,
      })

      @our_rails_dependency = ManifestDependency.create!({
        manifest_id: @our_manifest.id,
        requirements: "= 2.0.0",
        package_manager: 1,
        package_name: "rails",
        last_seen_at_revision: 1,
      })

      @our_byebug_dependency = ManifestDependency.create!({
        manifest_id: @our_manifest.id,
        requirements: "= 3.0.0",
        package_manager: 1,
        package_name: "byebug",
        last_seen_at_revision: 1,
      })

      @our_rails_package = Package.create!({
        name: "rails",
        package_manager: :rubygems,
        repository_id_certainty: PackageToRepoMapping::Certainty::NULL
      })

      @our_byebug_package = Package.create!({
        name: "byebug",
        package_manager: :rubygems,
        repository_id_certainty: PackageToRepoMapping::Certainty::NULL
      })

      @our_rails_package_release = PackageRelease.create({
        package_id: @our_rails_package.id,
        package_manager: 1,
        package_name: "rails",
        name: "2.0.0"
      })

      @our_byebug_package_release = PackageRelease.create({
        package_id: @our_byebug_package.id,
        package_manager: 1,
        package_name: "byebug",
        name: "3.0.0"
      })

      @our_abstract_dependency = AbstractRepositoryDependency.create({
        package_manager: 1, # RubyGems
        package_name: "rails",
        repository_id: @our_repository.id
      })

      @our_rails_dependent_counts = Views::PackageReleaseDependentCount.create({
        github_owner_id: @our_repository.github_owner_id,
        package_release_id: @our_rails_package_release.id,
        count: 1
      })

      @our_byebug_dependent_counts = Views::PackageReleaseDependentCount.create({
        github_owner_id: @our_repository.github_owner_id,
        package_release_id: @our_byebug_package_release.id,
        count: 10
      })

      # Make the org act like a Dependency Insights org by adding it to our backfill table
      DependencyInsightsBackfill.org_to_backfill(github_owner_id: @our_repository.github_owner_id)
    end

    it "raises an argument error when missing messages" do
      expect { ManifestDeleter.run!(nil) }.to raise_error(ArgumentError)
      expect { ManifestDeleter.run!("") }.to raise_error(ArgumentError)
      expect { ManifestDeleter.run!({
        repository_id: nil,
        manifest_file: {
          filename: "package.json",
          path: "",
        },
      })
      }.to raise_error(ArgumentError)
    end

    it "deletes manifests" do
      expect { ManifestDeleter.run!(job_params) }.to_not raise_error

      # Ensure that our Manifest was actually deleted!
      expect(Manifest.exists?(@our_manifest.id)).to be_falsey

      # Ensure that our AbstractRepositoryDependency was actually deleted!
      expect(AbstractRepositoryDependency.exists?(@our_abstract_dependency.id)).to be_falsey

      # Ensure that count for rails 2.0.0 package release no longer exists as it went form 1 -> none
      expect(Views::PackageReleaseDependentCount.exists?(@our_rails_dependent_counts.id)).to be_falsey

      # Ensure that count for byebug 3.0.0 dropped from 10 -> 9 after manifest was deleted
      expect(Views::PackageReleaseDependentCount.find(@our_byebug_dependent_counts.id).count).to eq(9)
    end
  end
end

context "normalised tables (dotcom and Proxima)" do
  before do
    allow(DependencyGraph).to receive(:use_normalized_tables?).and_return(true)
  end

  it_behaves_like "a manifest deleter"
end

context "unnormalised tables (GHES)" do
  before do
    allow(DependencyGraph).to receive(:use_normalized_tables?).and_return(false)
  end

  it_behaves_like "a manifest deleter"
end
