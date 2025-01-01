require "rails_helper"

describe Queries::DependenciesQuery do
  shared_examples "dependencies query" do
    before do
      factory do
        given_package("rake", "11.2.0")

        given_package("aws", "1.2.0")
          .update_package(github_repository_id: 50)
          .add_dependency("rake", "= 11.2.0")
      end
    end

    def get_dependency(package_name, dependent)
      if dependent.is_a?(Manifest) && DependencyGraph.use_normalized_tables?
        dependent.entries.with_package_name(package_name).first
      else
        dependent.dependencies.where(package_name: package_name).first
      end
    end

    describe "querying dependencies with a `prefer` option" do
      let(:release) do
        factory.given_package("rails", "5.0.0")
          .add_dependency("rake", ">= 11.2.0")
          .add_dependency("aws", ">= 1.2.0")
          .release
      end

      it "works the same when `prefer` option is empty" do
        rake_dependency = get_dependency("rake", release)
        aws_dependency  = get_dependency("aws", release)

        query = described_class.new(dependent: release, prefer: [])
        expect(query.dependencies_count).to eq 2
        expect(query.dependencies).to eq [aws_dependency, rake_dependency]
      end

      it "returns dependencies matching the `prefer` option first" do
        rake_dependency = get_dependency("rake", release)
        aws_dependency  = get_dependency("aws", release)

        query = described_class.new(dependent: release, prefer: ["rake"])
        expect(query.dependencies_count).to eq 2
        expect(query.dependencies).to eq [rake_dependency, aws_dependency]
      end
    end

    describe "a package release dependent" do
      let(:release) do
        factory.given_package("rails", "5.0.0")
          .add_dependency("rake", ">= 11.2.0")
          .add_dependency("aws", ">= 1.2.0")
          .release
      end
      let(:query) { described_class.new(dependent: release) }
      let(:dependencies) { query.dependencies }

      it "returns dependencies" do
        rake_dependency = get_dependency("rake", release)
        aws_dependency  = get_dependency("aws", release)

        expect(query.dependencies_count).to eq 2
        expect(dependencies).to eq [aws_dependency, rake_dependency]
      end

      it "includes repository IDs when possible" do
        # aws has an associated repo
        expect(dependencies.first.package_name).to eq "aws"
        expect(dependencies.first.package_github_repository_id).to eq 50

        # rake has no associated repo
        expect(dependencies.last.package_name).to eq "rake"
        expect(dependencies.last.package_github_repository_id).to be_nil
      end

      it "adds a 'has_dependencies' flag" do
        # aws has one dependency
        expect(dependencies.first.package_name).to eq "aws"
        expect(dependencies.first.has_dependencies?).to be_truthy

        # rake has no dependencies
        expect(dependencies.last.package_name).to eq "rake"
        expect(dependencies.last.has_dependencies?).to be_falsey
      end

      it "uses current package version to detect dependencies" do
        # Latest version of aws gem has no dependencies
        factory.given_package("aws", "1.3.0")

        expect(dependencies.first.package_name).to eq "aws"
        expect(dependencies.first.has_dependencies?).to be_falsey
      end

      it "handles missing packages" do
        PackageDependency.create!({
                                    dependent:    release,
                                    package_name: "unknown",
                                    requirements: ""
                                  })

        expect(query.dependencies_count).to eq 3
        expect(dependencies.last.package_name).to eq "unknown"
        expect(dependencies.last.has_dependencies?).to be_falsey
      end
    end

    describe "a manifest dependent" do
      let(:manifest) do
        factory.given_manifest(github_repo_id: 100)
          .add_dependency("rake", ">= 11.2.0")
          .add_dependency("aws", ">= 1.2.0")
          .manifest
      end
      let(:query) { described_class.new(dependent: manifest) }
      let(:dependencies) { query.dependencies }

      it "returns dependencies" do
        rake_dependency = get_dependency("rake", manifest)
        aws_dependency  = get_dependency("aws", manifest)

        expect(dependencies).to match_model [
          aws_dependency,
          rake_dependency,
                                ]
      end

      it "only includes the latest dependencies" do
        manifest = factory.given_manifest(github_repo_id: 100, revision: 2)
                     .add_dependency("rake", ">= 11.2.0", last_seen_at_revision: 1)
                     .add_dependency("aws", ">= 1.2.0", last_seen_at_revision: 2)
                     .manifest

        query = described_class.new(dependent: manifest)
        expect(query.dependencies_count).to eq 1
        expect(query.dependencies).to match_model [get_dependency("aws", manifest)]
      end

      it "includes repository IDs when possible" do
        # aws has an associated repo
        expect(dependencies.first.package_name).to eq "aws"
        expect(dependencies.first.package_github_repository_id).to eq 50

        # rake has no associated repo
        expect(dependencies.last.package_name).to eq "rake"
        expect(dependencies.last.package_github_repository_id).to be_nil
      end

      it "adds a 'has_dependencies' flag" do
        # aws has one dependency
        expect(dependencies.first.package_name).to eq "aws"
        expect(dependencies.first.has_dependencies?).to be_truthy

        # rake has no dependencies
        expect(dependencies.last.package_name).to eq "rake"
        expect(dependencies.last.has_dependencies?).to be_falsey
      end

      it "handles missing packages" do
        ManifestDependency.create!({
                                     manifest:              manifest,
                                     package_manager:       Types::PackageManager::RUBYGEMS,
                                     package_name:          "unknown",
                                     requirements:          "",
                                     last_seen_at_revision: manifest.revision,
                                   })

        expect(query.dependencies_count).to eq 3
        dependency = dependencies.sort_by(&:package_name).last
        expect(dependency.package_name).to eq "unknown"
        expect(dependency.has_dependencies?).to be_falsey
      end

      it "avoids uncessary check for sub dependencies if non-existent in ecosystem" do
        actions_manifest = factory.given_manifest(github_repo_id: 100, revision: 2, manifest_type: Types::Manifest[:workflow_yaml], package_manager: Types::PackageManager[:actions])
                             .add_dependency("repo/action", "= main")
                             .manifest

        expect_any_instance_of(described_class).to_not receive(:has_dependencies_subquery)

        actions_query = described_class.new(dependent: actions_manifest)
        action = actions_query.dependencies.first

        expect(action.has_dependencies?).to be_falsey
      end
    end
  end

  describe "normalised tables (dotcom and Proxima)" do
    before do
      allow(DependencyGraph).to receive(:use_normalized_tables?).and_return(true)
    end

    include_examples "dependencies query"
  end

  describe "unnormalised tables (GHES)" do
    before do
      allow(DependencyGraph).to receive(:use_normalized_tables?).and_return(false)
    end

    include_examples "dependencies query"
  end
end
