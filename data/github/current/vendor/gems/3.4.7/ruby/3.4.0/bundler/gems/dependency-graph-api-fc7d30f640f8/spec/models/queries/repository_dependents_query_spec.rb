require "rails_helper"

module Queries
  RSpec.shared_examples "a repository dependents query" do
    describe "#results" do
      let(:repository_1) { Repository.create!(github_repository_id: 1, github_owner_id: 10) }
      let(:repository_2) { Repository.create!(github_repository_id: 2, github_owner_id: 10) }

      let!(:manifest_1) do
        builder = factory.given_manifest(
          github_repo_id: repository_1.github_repository_id,
          manifest_type:  :gemfile_lock,
          filename:       "Gemfile.lock",
          path:           "/",
          revision: 1
        )

        builder.add_dependency("rake", "= 2.0.0", last_seen_at_revision: 0)
        builder.manifest
      end

      let!(:manifest_2) do
        builder = factory.given_manifest(
          github_repo_id: repository_2.github_repository_id,
          manifest_type:  :gemfile_lock,
          filename:       "Gemfile.lock",
          path:           "/",
          revision: 1
        )

        builder.add_dependency("rake", "= 2.0.0", last_seen_at_revision: 1)
        builder.manifest
      end

      let!(:actions_manifest) do
        builder = factory.given_manifest(
          github_repo_id: repository_2.github_repository_id,
          package_manager: Types::PackageManager[:actions],
          manifest_type:  :workflow_yaml,
          filename:       "doingthings.yml",
          path:           ".github/workflows/",
          revision: 1
        )

        builder.add_dependency("actions/checkout", "= dev", last_seen_at_revision: 1)
        builder.manifest
      end

      it "doesn't return dependents from old revisions" do
        results = results(owner_ids: 10, package_name: "rake", version: "2.0.0", package_manager: Types::PackageManager[:rubygems] , dependent_name: nil, limit: 25)

        expect(results.count).to eq(1)

        results.each do |dependent|
          expect(dependent.last_seen_at_revision).to eq(dependent.manifest.revision)
        end
      end

      it "returns dependents of a named version" do
        results = results(owner_ids: 10, package_name: "actions/checkout", version: "dev", package_manager: Types::PackageManager[:actions] , dependent_name: nil, limit: 25)
        expect(results.count).to eq(1)
        expect(results.first.requirements).to eq("= dev")
      end
    end

    describe "version counts" do
      let(:repository_1) { Repository.create!(github_repository_id: 1, github_owner_id: 10) }
      let(:repository_2) { Repository.create!(github_repository_id: 2, github_owner_id: 10) }
      let(:repository_3) { Repository.create!(github_repository_id: 3, github_owner_id: 10) }
      let(:repository_4) { Repository.create!(github_repository_id: 4, github_owner_id: 10) }

      before do
        PackageFactory.new("rake", "2.0.0", :rubygems).create
        PackageFactory.new("rake", "2.1.0", :rubygems).create
        PackageFactory.new("rake", "2.2.0", :rubygems).create
        PackageFactory.new("rake", "2.3.0", :rubygems).create

        PackageFactory.new("xunit", "2.0.0", :nuget).create
        PackageFactory.new("xunit", "2.1.0", :nuget).create
        PackageFactory.new("xunit", "2.2.0", :nuget).create
        PackageFactory.new("xunit", "2.3.0", :nuget).create

        PackageFactory.new("lights/camera-action", "main", :actions).create
        PackageFactory.new("lights/camera-action", "1.0.0", :actions).create
        PackageFactory.new("lights/camera-action", "dev", :actions).create
      end

      # lockfile manifests

      let!(:manifest_1) do
        builder = factory.given_manifest(
          github_repo_id: repository_1.github_repository_id,
          manifest_type:  :gemfile_lock,
          filename:       "Gemfile.lock",
          path:           "/",
          revision: 1
        )

        builder.add_dependency("rake", "= 2.0.0", last_seen_at_revision: 1)
        builder.manifest
      end

      let!(:manifest_2) do
        builder = factory.given_manifest(
          github_repo_id: repository_2.github_repository_id,
          manifest_type:  :gemfile_lock,
          filename:       "Gemfile.lock",
          path:           "/",
          revision: 1
        )

        builder.add_dependency("rake", "= 2.1.0", last_seen_at_revision: 1)
        builder.manifest
      end

      let!(:manifest_3) do
        builder = factory.given_manifest(
          github_repo_id: repository_3.github_repository_id,
          manifest_type:  :gemfile_lock,
          filename:       "Gemfile.lock",
          path:           "/",
          revision: 1
        )

        builder.add_dependency("rake", "= 2.2.0", last_seen_at_revision: 1)
        builder.manifest
      end

      let!(:manifest_4) do
        builder = factory.given_manifest(
          github_repo_id: repository_4.github_repository_id,
          manifest_type:  :gemfile_lock,
          filename:       "Gemfile.lock",
          path:           "/",
          revision: 1
        )

        builder.add_dependency("rake", "= 2.3.0", last_seen_at_revision: 1)
        builder.manifest
      end

      # non lockfile manifests (nuget nuspec manifests)

      let!(:manifest_5) do
        builder = factory.given_manifest(github_repo_id: repository_1.github_repository_id,
          manifest_type:  :nuspec,
          filename:       ".nuspec",
          package_manager: Types::PackageManager[:nuget],
          path:           "/",
          revision: 1
        )

        builder.add_dependency("xunit", "= 2.0.0", last_seen_at_revision: 1)
        builder.manifest
      end

      let!(:manifest_6) do
        builder = factory.given_manifest(
          github_repo_id: repository_2.github_repository_id,
          manifest_type:  :nuspec,
          filename:       ".nuspec",
          package_manager: Types::PackageManager[:nuget],
          path:           "/",
          revision: 1
        )

        builder.add_dependency("xunit", "= 2.1.0", last_seen_at_revision: 1)
        builder.manifest
      end

      let!(:manifest_7) do
        builder = factory.given_manifest(
          github_repo_id: repository_3.github_repository_id,
          manifest_type:  :nuspec,
          filename:       ".nuspec",
          package_manager: Types::PackageManager[:nuget],
          path:           "/",
          revision: 1
        )

        builder.add_dependency("xunit", "= 2.2.0", last_seen_at_revision: 1)
        builder.manifest
      end

      let!(:manifest_8) do
        builder = factory.given_manifest(
          github_repo_id: repository_4.github_repository_id,
          manifest_type:  :nuspec,
          filename:       ".nuspec",
          package_manager: Types::PackageManager[:nuget],
          path:           "/",
          revision: 1
        )

        builder.add_dependency("xunit", "= 2.3.0", last_seen_at_revision: 1)
        builder.manifest
      end

      let!(:manifest_9) do
        builder = factory.given_manifest(
          github_repo_id: repository_2.github_repository_id,
          package_manager: Types::PackageManager[:actions],
          manifest_type:  :workflow_yaml,
          filename:       "doingthings.yml",
          path:           ".github/workflows/",
          revision: 1
        )

        builder.add_dependency("lights/camera-action", "= dev", last_seen_at_revision: 1)
        builder.manifest
      end

      let!(:manifest_10) do
        builder = factory.given_manifest(
          github_repo_id: repository_3.github_repository_id,
          package_manager: Types::PackageManager[:actions],
          manifest_type:  :workflow_yaml,
          filename:       "doingthings.yml",
          path:           ".github/workflows/",
          revision: 1
        )

        builder.add_dependency("lights/camera-action", "= main", last_seen_at_revision: 1)
        builder.manifest
      end

      let!(:manifest_11) do
        builder = factory.given_manifest(
          github_repo_id: repository_4.github_repository_id,
          package_manager: Types::PackageManager[:actions],
          manifest_type:  :workflow_yaml,
          filename:       "doingthings.yml",
          path:           ".github/workflows/",
          revision: 1
        )

        builder.add_dependency("lights/camera-action", "= 1.0.0", last_seen_at_revision: 1)
        builder.manifest

        Views::PackageReleaseDependentCount.rebuild_for(10)
      end

      it "gets counts for lower and upper version for a given package release from manifest with lockfile" do

        rake = described_class.new(owner_ids: 10, package_name: "rake", version: "2.0.0", package_manager: Types::PackageManager[:rubygems] , dependent_name: nil, limit: 25)
        expect(rake.upper_version_count).to eq(3)
        expect(rake.lower_version_count).to eq(0)

        rake = described_class.new(owner_ids: 10, package_name: "rake", version: "2.1.0", package_manager: Types::PackageManager[:rubygems] , dependent_name: nil, limit: 25)
        expect(rake.upper_version_count).to eq(2)
        expect(rake.lower_version_count).to eq(1)

        rake = described_class.new(owner_ids: 10, package_name: "rake", version: "2.2.0", package_manager: Types::PackageManager[:rubygems] , dependent_name: nil, limit: 25)
        expect(rake.upper_version_count).to eq(1)
        expect(rake.lower_version_count).to eq(2)

        rake = described_class.new(owner_ids: 10, package_name: "rake", version: "2.3.0", package_manager: Types::PackageManager[:rubygems] , dependent_name: nil, limit: 25)
        expect(rake.upper_version_count).to eq(0)
        expect(rake.lower_version_count).to eq(3)
      end

      it "gets counts for lower and upper version for a given package release from manifest with no lockfiles" do

        xunit = described_class.new(owner_ids: 10, package_name: "xunit", version: "2.0.0", package_manager: Types::PackageManager[:nuget] , dependent_name: nil, limit: 25)
        expect(xunit.upper_version_count).to eq(3)
        expect(xunit.lower_version_count).to eq(0)

        xunit = described_class.new(owner_ids: 10, package_name: "xunit", version: "2.1.0", package_manager: Types::PackageManager[:nuget] , dependent_name: nil, limit: 25)
        expect(xunit.upper_version_count).to eq(2)
        expect(xunit.lower_version_count).to eq(1)

        xunit = described_class.new(owner_ids: 10, package_name: "xunit", version: "2.2.0", package_manager: Types::PackageManager[:nuget] , dependent_name: nil, limit: 25)
        expect(xunit.upper_version_count).to eq(1)
        expect(xunit.lower_version_count).to eq(2)

        xunit = described_class.new(owner_ids: 10, package_name: "xunit", version: "2.3.0", package_manager: Types::PackageManager[:nuget] , dependent_name: nil, limit: 25)
        expect(xunit.upper_version_count).to eq(0)
        expect(xunit.lower_version_count).to eq(3)
      end

      it "does not count versions if we dont know about a corresponding package release" do
        manifest_9 = factory.given_manifest(
          github_repo_id: repository_4.github_repository_id,
          manifest_type:  :nuspec,
          filename:       "project2.nuspec",
          package_manager: Types::PackageManager[:nuget],
          path:           "/project/",
          revision: 1
        )

        manifest_9.add_dependency("xunit", "= 5.3.0", last_seen_at_revision: 1)
        manifest_9.manifest

        Views::PackageReleaseDependentCount.rebuild_for(10)

        xunit = described_class.new(owner_ids: 10, package_name: "xunit", version: "2.3.0", package_manager: Types::PackageManager[:nuget] , dependent_name: nil, limit: 25)
        expect(xunit.upper_version_count).to eq(0)

        PackageFactory.new("xunit", "5.3.0", :nuget).create

        Views::PackageReleaseDependentCount.rebuild_for(10)

        xunit = described_class.new(owner_ids: 10, package_name: "xunit", version: "2.3.0", package_manager: Types::PackageManager[:nuget] , dependent_name: nil, limit: 25)

        expect(xunit.upper_version_count).to eq(1)
      end

      it "gets counts for lower and upper version for a given package release from manifests containing named versions" do
        action = described_class.new(owner_ids: 10, package_name: "lights/camera-action", version: "1.0.0", package_manager: Types::PackageManager[:actions] , dependent_name: nil, limit: 25)
        expect(action.upper_version_count).to eq(2)
        expect(action.lower_version_count).to eq(0)

        # for the named version, the other versions will end up being "lower" than the queried one
        action = described_class.new(owner_ids: 10, package_name: "lights/camera-action", version: "main", package_manager: Types::PackageManager[:actions] , dependent_name: nil, limit: 25)
        expect(action.upper_version_count).to eq(0)
        expect(action.lower_version_count).to eq(2)
      end
    end

    def results(args)
      described_class.new(**args).results
    end
  end

  describe "normalised tables (dotcom and Proxima)" do
    before do
      allow(DependencyGraph).to receive(:use_normalized_tables?).and_return(true)
    end

    describe RepositoryDependentsQuery do
      it_behaves_like "a repository dependents query"
    end
  end

  describe "unnormalised tables (GHES)" do
    before do
      allow(DependencyGraph).to receive(:use_normalized_tables?).and_return(false)
    end

    describe RepositoryDependentsQuery do
      it_behaves_like "a repository dependents query"
    end
  end
end
