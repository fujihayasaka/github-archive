require "rails_helper"

describe Package do
  before do
    factory do
      given_package("rake", "11.2.0")
      given_package("rake", "11.3.0")
      given_package("rails", "4.2.0")
        .dependency("rake", "~> 11.2")
      given_package("rails", "5.0.0")
        .dependency("rake", "~> 11.2")
      given_package("sinatra", "1.4.0")
        .dependency("rake", "11.2.0")
      given_package("sinatra", "1.4.7")
        .dependency("rake", "11.3.0")
    end
  end

  describe "#github_owner_id" do
    it "returns the owner ID of the repository" do
      owner_id = 456
      repo = Repository.create!(github_repository_id: 123, github_owner_id: owner_id, nwo: "bar/foo")
      package = described_class.create!(repository_id: repo.github_repository_id,
        package_manager: Types::PackageManager[:pip], name: "foo")

      expect(package.github_owner_id).to eq(owner_id)
    end
  end

  describe ".repository_owned_by" do
    it "filters packages by repository owner" do
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

      result = described_class.repository_owned_by(owner_id)

      expect(result.size).to eq(2)
      expect(result).to include(package1)
      expect(result).not_to include(package2)
      expect(result).to include(package3)
    end
  end

  describe ".most_dependents_first" do
    it "returns packages with more repo dependents first" do
      ruby_1 = factory.given_package("ruby-package-1", "1.0.0", :rubygems).package
      ruby_2 = factory.given_package("ruby-package-2", "1.0.0", :rubygems).package
      js_1   = factory.given_package("js-package-1", "1.0.0", :npm).package

      Views::AbstractRepositoryDependencyCount.create!({
        package_name: "ruby-package-1",
        package_manager: :rubygems,
        dependent_count: 100,
      })
      Views::AbstractRepositoryDependencyCount.create!({
        package_name: "ruby-package-2",
        package_manager: :rubygems,
        dependent_count: 1000,
      })
      Views::AbstractRepositoryDependencyCount.create!({
        package_name: "js-package-1",
        package_manager: :npm,
        dependent_count: 10000,
      })

      scope = Package.where({
        name: ["ruby-package-1", "ruby-package-2", "js-package-1"],
        package_manager: Types::PackageManager[:rubygems]
      }).most_dependents_first

      expect(scope.most_dependents_first).to eq [ruby_2, ruby_1]
    end
  end
end
