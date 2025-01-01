require "rails_helper"

describe AbstractRepositoryDependency do
  let(:repo) { Repository.create!(github_repository_id: 1234) }
  let(:rails) { factory.given_package("rails", "5.0.0", :rubygems).package }

  describe "#github_owner_id" do
    it "returns the repository's owner ID" do
      owner_id = 1
      repo = Repository.create!(github_repository_id: 123, github_owner_id: owner_id)
      dependency = described_class.create!(
        repository_id: repo.id,
        package_manager: Types::PackageManager[:rubygems],
        package_name:    "rails",
      )

      expect(dependency.github_owner_id).to eq(owner_id)
    end
  end

  describe ".for_github_repository scope" do
    it "returns dependencies for the given repository" do
      repo1 = Repository.create!(github_repository_id: 123)
      repo2 = Repository.create!(github_repository_id: 456)

      dependency1 = described_class.create!(
        repository_id: repo1.id,
        package_manager: Types::PackageManager[:rubygems],
        package_name:    "rails",
      )
      dependency2 = described_class.create!(
        repository_id: repo2.id,
        package_manager: Types::PackageManager[:npm],
        package_name:    "react",
      )

      result = described_class.for_github_repository(repo1.github_repository_id)

      expect(result.size).to eq(1)
      expect(result).to include(dependency1)
      expect(result).not_to include(dependency2)
    end
  end

  describe ".repository_owned_by scope" do
    it "includes dependencies for repositories owned by specified owner" do
      owner_id = 1
      other_owner_id = 2
      repo1 = Repository.create!(github_repository_id: 123, github_owner_id: owner_id)
      repo2 = Repository.create!(github_repository_id: 456, github_owner_id: other_owner_id)
      repo3 = Repository.create!(github_repository_id: 789, github_owner_id: owner_id)

      dependency1 = described_class.create!(
        repository_id: repo1.id,
        package_manager: Types::PackageManager[:rubygems],
        package_name:    "rails",
      )
      dependency2 = described_class.create!(
        repository_id: repo2.id,
        package_manager: Types::PackageManager[:npm],
        package_name:    "react",
      )
      dependency3 = described_class.create!(
        repository_id: repo3.id,
        package_manager: Types::PackageManager[:rubygems],
        package_name:    "rake",
      )

      result = described_class.repository_owned_by(owner_id)

      expect(result.size).to eq(2)
      expect(result).to include(dependency1)
      expect(result).not_to include(dependency2)
      expect(result).to include(dependency3)
    end

    it "works even when joining to packages" do
      owner_id = 1
      other_owner_id = 2
      repo_using_django = Repository.create!(github_repository_id: 1, nwo: "some/project",
        github_owner_id: owner_id)
      dependency = AbstractRepositoryDependency.create!(repository_id: repo_using_django.id,
        package_manager: "pip", package_name: "django")
      django = Repository.create!(github_repository_id: 11, nwo: "django/django",
        github_owner_id: other_owner_id)
      Package.create!(name: "django", package_manager: "pip",
        repository_id: django.github_repository_id)

      result = described_class.repository_owned_by(owner_id)
        .join_packages

      expect(result.size).to eq(1)
      expect(result).to eq([dependency])
    end
  end

  describe ".sort_by_package_manager scope" do
    it "sorts by package manager name ascending" do
      dependency1 = described_class.create!(
        repository: Repository.create!(github_repository_id: 123, github_owner_id: 1),
        package_manager: Types::PackageManager[:rubygems],
        package_name: "rails",
      )
      dependency2 = described_class.create!(
        repository: Repository.create!(github_repository_id: 456, github_owner_id: 2),
        package_manager: Types::PackageManager[:maven],
        package_name: "log4j",
      )
      dependency3 = described_class.create!(
        repository: Repository.create!(github_repository_id: 789, github_owner_id: 3),
        package_manager: Types::PackageManager[:npm],
        package_name: "react",
      )

      result = described_class.sort_by_package_manager

      expect(result.size).to eq(3)
      expect(result).to eq([dependency2, dependency3, dependency1])
    end

    it "works when joining to packages" do
      dependency1 = described_class.create!(
        repository: Repository.create!(github_repository_id: 123, github_owner_id: 1),
        package_manager: Types::PackageManager[:rubygems],
        package_name: "rails",
      )
      Package.create!(name: "rails", package_manager: Types::PackageManager[:rubygems],
        repository_id: 123)
      dependency2 = described_class.create!(
        repository: Repository.create!(github_repository_id: 456, github_owner_id: 2),
        package_manager: Types::PackageManager[:maven],
        package_name: "log4j",
      )
      Package.create!(name: "log4j", package_manager: Types::PackageManager[:maven],
        repository_id: 456)
      dependency3 = described_class.create!(
        repository: Repository.create!(github_repository_id: 789, github_owner_id: 3),
        package_manager: Types::PackageManager[:npm],
        package_name: "react",
      )
      Package.create!(name: "react", package_manager: Types::PackageManager[:npm],
        repository_id: 789)

      result = described_class.sort_by_package_manager
        .join_packages

      expect(result.size).to eq(3)
      expect(result).to eq([dependency2, dependency3, dependency1])
    end
  end

  describe ".sort_by_package_name scope" do
    it "sorts by package name" do
      dependency1 = described_class.create!(
        repository: Repository.create!(github_repository_id: 123, github_owner_id: 1),
        package_manager: Types::PackageManager[:rubygems],
        package_name: "rails",
      )
      Package.create!(name: "rails", package_manager: Types::PackageManager[:rubygems],
        repository_id: 123)
      dependency2 = described_class.create!(
        repository: Repository.create!(github_repository_id: 456, github_owner_id: 2),
        package_manager: Types::PackageManager[:maven],
        package_name: "log4j",
      )
      Package.create!(name: "log4j", package_manager: Types::PackageManager[:maven],
        repository_id: 456)
      dependency3 = described_class.create!(
        repository: Repository.create!(github_repository_id: 789, github_owner_id: 3),
        package_manager: Types::PackageManager[:npm],
        package_name: "react",
      )
      Package.create!(name: "react", package_manager: Types::PackageManager[:npm],
        repository_id: 789)

      result = described_class.sort_by_package_name
        .join_packages

      expect(result.size).to eq(3)
      expect(result).to eq([dependency2, dependency1, dependency3])
    end
  end

  describe ".depends_on" do
    it "includes dependencies for the package and package manager" do
      included = described_class.create!({
        repository_id:   repo.id,
        package_manager: Types::PackageManager[:rubygems],
        package_name:    "rails",
      })

      expect(described_class.depends_on(rails)).to eq [included]
    end

    it "excluded dependencies for other packages" do
      described_class.create!({
        repository_id:   repo.id,
        package_manager: Types::PackageManager[:rubygems],
        package_name:    "rake",
      })

      expect(described_class.depends_on(rails)).to be_empty
    end

    it "excluded dependencies for other package managers" do
      described_class.create!({
        repository_id:   repo.id,
        package_manager: Types::PackageManager[:npm],
        package_name:    "rails",
      })

      expect(described_class.depends_on(rails)).to be_empty
    end
  end

  shared_examples "delete orphaned dependencies" do |normalized_tables|
    before do
      allow(DependencyGraph).to receive(:use_normalized_tables?).and_return(normalized_tables)
    end

    it "deletes orphaned dependencies" do
      described_class.create!({
        repository_id:   repo.id,
        package_manager: Types::PackageManager[:rubygems],
        package_name:    "rails",
      })

      described_class.create!({
        repository_id:   repo.id,
        package_manager: Types::PackageManager[:rubygems],
        package_name:    "rake",
      })

      manifest = Manifest.create!({
        repository_id: repo.id,
        package_manager: Types::PackageManager[:rubygems],
        manifest_type:   Types::Manifest[:gemfile],
        filename:        "Gemfile.lock",
        path:            "",
        latest_git_ref:  "77dab21",
        last_pushed_at:  Time.now,
      })

      manifest.dependencies.create!({
        package_name:          "rake",
        requirements:          "~> 4.2.0",
        scope:                 :runtime,
        last_seen_at_revision: 0,
      })

      expect(described_class.where(package_manager: 1, package_name: "rails")).to exist

      deleted_dependencies_count = described_class.delete_orphans("rails", "rubygems")

      expect(deleted_dependencies_count).to eq 1
      expect(described_class.where(package_manager: 1, package_name: "rails")).not_to exist
      expect(described_class.where(package_manager: 1, package_name: "rake")).to exist
    end
  end

  context "denormalized tables" do
    it_should_behave_like "delete orphaned dependencies", false
  end

  context "normalized tables" do
    it_should_behave_like "delete orphaned dependencies", true
  end
end
