require "rails_helper"

module Queries
  describe AbstractPackageDependentsQuery do
    let!(:rails) do
      factory.given_package("rails", "5.0.0", :rubygems).package
    end

    let!(:httparty) do
      factory.given_package("httparty", "1.0.0", :rubygems).package
    end

    describe "#results" do
      it "returns abstract dependencies for the package" do
        included = AbstractPackageDependency.create!({
          dependent:       Package.create(name: "some-rails-project"),
          package_name:    "rails",
          package_manager: :rubygems,
        })

        excluded = AbstractPackageDependency.create!({
          dependent:       Package.create(name: "another-rails-project"),
          package_name:    "httparty",
          package_manager: :rubygems,
        })

        query = described_class.new(depends_on: rails)

        expect(query.results).to eq [included]
      end

      it "returns more recently created dependencies first" do
        oldest = AbstractPackageDependency.create!({
          dependent:       Package.create(name: "some-rails-project"),
          package_name:    "rails",
          package_manager: :rubygems,
        })

        older = AbstractPackageDependency.create!({
          dependent:       Package.create(name: "another-rails-project"),
          package_name:    "rails",
          package_manager: :rubygems,
        })
        newer = AbstractPackageDependency.create!({
          dependent:       Package.create(name: "final-rails-project"),
          package_name:    "rails",
          package_manager: :rubygems,
        })

        query = described_class.new(depends_on: rails)

        expect(query.results).to eq [newer, older, oldest]
      end

      it "eagerly loads packages" do
        10.times do |i|
          dependent = factory.given_package("lib-#{i}", "0.0.1").package
          AbstractPackageDependency.create!({
            dependent:       dependent,
            package_name:    "rails",
            package_manager: :rubygems,
          })
        end

        query = described_class.new(depends_on: rails)

        expect {
          query.results.map(&:github_repository_id)
        }.to make_database_queries(count: 2)
      end

      it "allows filtering by dependent owner" do
        owner_id1 = 1
        owner_id2 = 2
        package_manager = Types::PackageManager[:pip]

        repo_with_owner1 = Repository.create!(github_repository_id: 1, nwo: "some/project",
          github_owner_id: owner_id1, public: true)
        repo_with_owner2 = Repository.create!(github_repository_id: 3, nwo: "other/project3",
          github_owner_id: owner_id2, public: true)

        package1 = Package.create!(repository_id: repo_with_owner1.github_repository_id,
          package_manager: package_manager, name: "foo")
        package2 = Package.create!(repository_id: repo_with_owner2.github_repository_id,
          package_manager: package_manager, name: "cat")

        apd1 = AbstractPackageDependency.create!(dependent_id: package1.id,
          package_manager: package_manager, package_name: "foo")
        apd2 = AbstractPackageDependency.create!(dependent_id: package2.id,
          package_manager: package_manager, package_name: "cat")

        query = described_class.new(depends_on: package1, github_owner_id: owner_id1)
        expect(query.results).to eq([apd1])

        query = described_class.new(depends_on: package1, github_owner_id: owner_id2)
        expect(query.results).to eq([])

        query = described_class.new(depends_on: package2, github_owner_id: owner_id1)
        expect(query.results).to eq([])

        query = described_class.new(depends_on: package2, github_owner_id: owner_id2)
        expect(query.results).to eq([apd2])
      end
    end

    describe "#after" do
      it "returns results after the cursor" do
        older = AbstractPackageDependency.create!({
          dependent:       Package.create(name: "some-rails-project"),
          package_name:    "rails",
          package_manager: :rubygems,
        })

        newer = AbstractPackageDependency.create!({
          dependent:       Package.create(name: "another-rails-project"),
          package_name:    "rails",
          package_manager: :rubygems,
        })

        newest = AbstractPackageDependency.create!({
          dependent:       Package.create(name: "final-rails-project"),
          package_name:    "rails",
          package_manager: :rubygems,
        })

        query = described_class.new(depends_on: rails)
        expect(query.first(3).results).to eq [newest, newer, older]

        query = described_class.new(depends_on: rails)
        expect(query.first(3).after(newest.id).results).to eq [newer, older]

        query = described_class.new(depends_on: rails)
        expect(query.first(1).after(newer.id).results).to eq [older]

        query = described_class.new(depends_on: rails)
        expect(query.first(1).after(older.id).results).to eq []
      end
    end

    describe "#before" do
      it "returns results before the cursor" do
        older = AbstractPackageDependency.create!({
          dependent:       Package.create(name: "some-rails-project"),
          package_name:    "rails",
          package_manager: :rubygems,
        })

        newer = AbstractPackageDependency.create!({
          dependent:       Package.create(name: "another-rails-project"),
          package_name:    "rails",
          package_manager: :rubygems,
        })

        newest = AbstractPackageDependency.create!({
          dependent:       Package.create(name: "final-rails-project"),
          package_name:    "rails",
          package_manager: :rubygems,
        })

        query = described_class.new(depends_on: rails)
        expect(query.first(3).results).to eq [newest, newer, older]

        query = described_class.new(depends_on: rails)
        expect(query.first(3).before(older.id).results).to eq [newest, newer]

        query = described_class.new(depends_on: rails)
        expect(query.first(1).before(newer.id).results).to eq [newest]

        query = described_class.new(depends_on: rails)
        expect(query.first(1).before(older.id).results).to eq [newer]

        query = described_class.new(depends_on: rails)
        expect(query.first(1).before(newest.id).results).to eq []
      end
    end

    describe "#has_previous?" do
      it "is true if the there are results before the page" do
        older = AbstractPackageDependency.create!({
          dependent:       Package.create(name: "some-rails-project"),
          package_name:    "rails",
          package_manager: :rubygems,
        })

        newer = AbstractPackageDependency.create!({
          dependent:       Package.create(name: "another-rails-project"),
          package_name:    "rails",
          package_manager: :rubygems,
        })

        newest = AbstractPackageDependency.create!({
          dependent:       Package.create(name: "final-rails-project"),
          package_name:    "rails",
          package_manager: :rubygems,
        })

        query = described_class.new(depends_on: rails)
        expect(query.first(1)).to_not have_previous

        query = described_class.new(depends_on: rails)
        expect(query.first(1).after(newest.id)).to have_previous

        query = described_class.new(depends_on: rails)
        expect(query.first(1).after(newer.id)).to have_previous

        query = described_class.new(depends_on: rails)
        expect(query.last(1).before(older.id)).to have_previous

        query = described_class.new(depends_on: rails)
        expect(query.first(1).before(newest.id)).to_not have_previous
      end
    end

    describe "#has_next?" do
      it "is true if the there are results after the page" do
        older = AbstractPackageDependency.create!({
          dependent:       Package.create(name: "some-rails-project"),
          package_name:    "rails",
          package_manager: :rubygems,
        })

        newer = AbstractPackageDependency.create!({
          dependent:       Package.create(name: "another-rails-project"),
          package_name:    "rails",
          package_manager: :rubygems,
        })

        newest = AbstractPackageDependency.create!({
          dependent:       Package.create(name: "final-rails-project"),
          package_name:    "rails",
          package_manager: :rubygems,
        })

        query = described_class.new(depends_on: rails)
        expect(query.first(1)).to have_next

        query = described_class.new(depends_on: rails)
        expect(query.last(1).before(older.id)).to have_next

        query = described_class.new(depends_on: rails)
        expect(query.first(1).after(newest.id)).to have_next

        query = described_class.new(depends_on: rails)
        expect(query.first(1).after(newer.id)).to_not have_next

        query = described_class.new(depends_on: rails)
        expect(query.first(1).before(newest.id)).to_not have_next
      end
    end

    describe "#dependent_count" do
      it "returns the number of package dependents" do
        2.times do |i|
          AbstractPackageDependency.create!({
            dependent:       Package.create(name: "rails-proj-#{i}"),
            package_name:    "rails",
            package_manager: :rubygems,
          })
        end
        2.times do |i|
          AbstractPackageDependency.create!({
            dependent:       Package.create(name: "some-proj-#{i}"),
            package_name:    "httparty",
            package_manager: :rubygems,
          })
        end

        Views::AbstractPackageDependencyCount.rebuild

        query = described_class.new(depends_on: rails)

        expect(query.dependent_count).to eq 2
      end

      it "respects the owner ID filter" do
        owner_id1 = 1
        owner_id2 = 2
        package_manager = Types::PackageManager[:pip]

        repo_with_owner1 = Repository.create!(github_repository_id: 1, nwo: "some/project",
          github_owner_id: owner_id1, public: true)
        repo_with_owner2 = Repository.create!(github_repository_id: 3, nwo: "other/project3",
          github_owner_id: owner_id2, public: true)

        package1 = Package.create!(repository_id: repo_with_owner1.github_repository_id,
          package_manager: package_manager, name: "foo")
        package2 = Package.create!(repository_id: repo_with_owner2.github_repository_id,
          package_manager: package_manager, name: "cat")

        apd1 = AbstractPackageDependency.create!(dependent_id: package1.id,
          package_manager: package_manager, package_name: "foo")
        apd2 = AbstractPackageDependency.create!(dependent_id: package2.id,
          package_manager: package_manager, package_name: "cat")

        query = described_class.new(depends_on: package1, github_owner_id: owner_id1)
        expect(query.dependent_count).to eq(1)

        query = described_class.new(depends_on: package1, github_owner_id: owner_id2)
        expect(query.dependent_count).to eq(0)

        query = described_class.new(depends_on: package2, github_owner_id: owner_id1)
        expect(query.dependent_count).to eq(0)

        query = described_class.new(depends_on: package2, github_owner_id: owner_id2)
        expect(query.dependent_count).to eq(1)
      end
    end
  end
end
