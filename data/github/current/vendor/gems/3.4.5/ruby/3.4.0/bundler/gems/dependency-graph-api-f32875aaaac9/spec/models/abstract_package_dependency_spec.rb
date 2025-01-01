require "rails_helper"

describe AbstractPackageDependency do
  describe "#github_owner_id" do
    it "returns the dependent package's repository's owner ID" do
      owner_id = 1
      package_manager = Types::PackageManager[:rubygems]
      repo = Repository.create!(github_repository_id: 123, github_owner_id: owner_id, nwo: "bar/foo")
      package = Package.create!(repository_id: repo.github_repository_id,
        package_manager: package_manager, name: "foo")
      apd = described_class.create!(dependent: package, package_manager: package_manager, package_name: "foo")

      expect(apd.github_owner_id).to eq(owner_id)
    end
  end

  describe ".dependent_owned_by" do
    it "filters packages by dependent owner" do
      owner_id = 1
      other_owner_id = 2
      repo1 = Repository.create!(github_repository_id: 123, github_owner_id: owner_id, nwo: "bar/foo")
      repo2 = Repository.create!(github_repository_id: 456, github_owner_id: other_owner_id, nwo: "dog/cat")
      repo3 = Repository.create!(github_repository_id: 789, github_owner_id: owner_id, nwo: "hello/world")
      package_manager = Types::PackageManager[:rubygems]

      package1 = Package.create!(repository_id: repo1.github_repository_id, package_manager: package_manager,
        name: "foo")
      package2 = Package.create!(repository_id: repo2.github_repository_id, package_manager: package_manager,
        name: "cat")
      package3 = Package.create!(repository_id: repo3.github_repository_id, package_manager: package_manager,
        name: "world")

      apd1 = described_class.create!(dependent: package1, package_manager: package_manager, package_name: "foo")
      apd2 = described_class.create!(dependent: package2, package_manager: package_manager, package_name: "cat")
      apd3 = described_class.create!(dependent: package3, package_manager: package_manager, package_name: "world")

      result = described_class.dependent_owned_by(owner_id)

      expect(result.size).to eq(2)
      expect(result).to include(apd1)
      expect(result).not_to include(apd2)
      expect(result).to include(apd3)
    end
  end

  describe ".depends_on" do
    let(:rake) do
      factory.given_package("rake", "11.2.0", :rubygems).package
    end
    let(:rails) do
      factory.given_package("rails", "5.0.0", :rubygems).package
    end

    it "includes dependencies for the package and package manager" do
      included = described_class.create!({
        dependent:       rails,
        package_manager: Types::PackageManager[:rubygems],
        package_name:    "rake",
      })

      expect(described_class.depends_on(rake)).to eq [included]
    end

    it "excluded dependencies for other packages" do
      described_class.create!({
        dependent:       rails,
        package_manager: Types::PackageManager[:rubygems],
        package_name:    "activerecord",
      })

      expect(described_class.depends_on(rake)).to be_empty
    end

    it "excluded dependencies for other package managers" do
      described_class.create!({
        dependent:       rails,
        package_manager: Types::PackageManager[:npm],
        package_name:    "rake",
      })

      expect(described_class.depends_on(rake)).to be_empty
    end
  end
end
