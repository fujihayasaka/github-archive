require "rails_helper"

module Queries
  describe AbstractRepositoryDependentsQuery do
    let!(:rails) do
      factory.given_package("rails", "5.0.0", :rubygems).package
    end

    let!(:httparty) do
      factory.given_package("httparty", "1.0.0", :rubygems).package
    end

    let(:repository) { Repository.create!(github_repository_id: 1) }
    let(:repository_2) { Repository.create!(github_repository_id: 2) }
    let(:repository_3) { Repository.create!(github_repository_id: 3) }

    describe "#results" do
      it "returns abstract dependencies for the package" do
        included = AbstractRepositoryDependency.create!({
          repository:       repository,
          package_name:    "rails",
          package_manager: :rubygems,
        })
        excluded = AbstractRepositoryDependency.create!({
          repository:       repository,
          package_name:    "httparty",
          package_manager: :rubygems,
        })

        query = described_class.new(depends_on: rails)

        expect(query.results)
          .to eq [included]
      end

      it "returns more recently created dependencies first" do
        older = AbstractRepositoryDependency.create!({
          repository:       repository,
          package_name:    "rails",
          package_manager: :rubygems,
        })
        newer = AbstractRepositoryDependency.create!({
          repository:       repository_2,
          package_name:    "rails",
          package_manager: :rubygems,
        })

        query = described_class.new(depends_on: rails)

        expect(query.results).to eq [newer, older]
      end

      it "eagerly loads repositories" do
        10.times do |i|
          repository = Repository.create!({
            github_repository_id: i
          })
          AbstractRepositoryDependency.create!({
            repository:      repository,
            package_name:    "rails",
            package_manager: :rubygems,
          })
        end

        query = described_class.new(depends_on: rails)

        expect {
          query.results.map(&:github_repository_id)
        }.to make_database_queries(count: 1)
      end

      it "allows filtering by dependent owner" do
        owner_id1 = 1
        owner_id2 = 2

        repo_using_django1 = Repository.create!(github_repository_id: 1, nwo: "some/project",
          github_owner_id: owner_id1, public: true)
        repo_using_django2 = Repository.create!(github_repository_id: 2, nwo: "some/project2",
          github_owner_id: owner_id1, public: true)
        repo_using_django_with_other_owner = Repository.create!(github_repository_id: 3, nwo: "other/project3",
          github_owner_id: owner_id2, public: true)

        django = factory.given_package("django", "4.2.1", :pip,
          repository_id: 11,
          last_published_at: 1.month.ago
        )
        .update_package_repository(nwo: "django/django")
        .package

        pip = Types::PackageManager[:pip]

        ard1 = AbstractRepositoryDependency.create!(repository_id: repo_using_django1.id,
          package_manager: pip, package_name: "django")
        ard2 = AbstractRepositoryDependency.create!(repository_id: repo_using_django2.id,
          package_manager: pip, package_name: "django")
        other_owner_ard = AbstractRepositoryDependency.create!(repository_id: repo_using_django_with_other_owner.id,
          package_manager: pip, package_name: "django")

        query = described_class.new(depends_on: django, github_owner_id: owner_id1)
        expect(query.results).to eq([ard2, ard1])

        query = described_class.new(depends_on: django, github_owner_id: owner_id2)
        expect(query.results).to eq([other_owner_ard])
      end
    end

    describe "private repositories" do
      let(:repository) { Repository.create!(github_repository_id: 42, public: false) }
      before do
        AbstractRepositoryDependency.create!({
          repository:      repository,
          package_name:    "rails",
          package_manager: :rubygems,
        })
        5.times do |i|
          repository = Repository.create!(github_repository_id: i)
          AbstractRepositoryDependency.create!({
            repository:      repository,
            package_name:    "rails",
            package_manager: :rubygems,
          })
        end
      end

      it "does not return the private repository" do
        query = described_class.new(depends_on: rails)
        expect(query.results.map(&:github_repository_id)).to_not include(42)
      end
    end

    describe "#after" do
      it "returns results after the cursor" do
        older = AbstractRepositoryDependency.create!({
          repository:       repository,
          package_name:    "rails",
          package_manager: :rubygems,
        })
        newer = AbstractRepositoryDependency.create!({
          repository:       repository_2,
          package_name:    "rails",
          package_manager: :rubygems,
        })

        newest= AbstractRepositoryDependency.create!({
          repository:       repository_3,
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
        older = AbstractRepositoryDependency.create!({
          repository:       repository,
          package_name:    "rails",
          package_manager: :rubygems,
        })

        newer = AbstractRepositoryDependency.create!({
          repository:       repository_2,
          package_name:    "rails",
          package_manager: :rubygems,
        })

        newest= AbstractRepositoryDependency.create!({
          repository:       repository_3,
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
        older = AbstractRepositoryDependency.create!({
          repository:       repository,
          package_name:    "rails",
          package_manager: :rubygems,
        })

        newer = AbstractRepositoryDependency.create!({
          repository:       repository_2,
          package_name:    "rails",
          package_manager: :rubygems,
        })

        newest= AbstractRepositoryDependency.create!({
          repository:      repository_3,
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
        older = AbstractRepositoryDependency.create!({
          repository:       repository,
          package_name:    "rails",
          package_manager: :rubygems,
        })

        newer = AbstractRepositoryDependency.create!({
          repository:       repository_2,
          package_name:    "rails",
          package_manager: :rubygems,
        })

        newest = AbstractRepositoryDependency.create!({
          repository:       repository_3,
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
      it "returns the number of repository dependents for the package" do
        5.times do |i|
          AbstractRepositoryDependency.create!({
            repository:      Repository.create!(github_repository_id: i),
            package_name:    "rails",
            package_manager: :rubygems,
          })
        end
        2.times do |i|
          AbstractRepositoryDependency.create!({
            repository:      Repository.create!(github_repository_id: 10 + i),
            package_name:    "httparty",
            package_manager: :rubygems,
          })
        end

        Views::AbstractRepositoryDependencyCount.rebuild

        query = described_class.new(depends_on: rails)

        expect(query.dependent_count).to eq 5
      end

      it "respects the owner ID filter" do
        owner_id1 = 1
        owner_id2 = 2

        repo_using_django1 = Repository.create!(github_repository_id: 1, nwo: "some/project",
          github_owner_id: owner_id1, public: true)
        repo_using_django2 = Repository.create!(github_repository_id: 2, nwo: "some/project2",
          github_owner_id: owner_id1, public: true)
        repo_using_django_with_other_owner = Repository.create!(github_repository_id: 3, nwo: "other/project3",
          github_owner_id: owner_id2, public: true)

        django = factory.given_package("django", "4.2.1", :pip,
          repository_id: 11,
          last_published_at: 1.month.ago
        )
        .update_package_repository(nwo: "django/django")
        .package

        pip = Types::PackageManager[:pip]

        ard1 = AbstractRepositoryDependency.create!(repository_id: repo_using_django1.id,
          package_manager: pip, package_name: "django")
        ard2 = AbstractRepositoryDependency.create!(repository_id: repo_using_django2.id,
          package_manager: pip, package_name: "django")
        other_owner_ard = AbstractRepositoryDependency.create!(repository_id: repo_using_django_with_other_owner.id,
          package_manager: pip, package_name: "django")

        query = described_class.new(depends_on: django, github_owner_id: owner_id1)
        expect(query.dependent_count).to eq(2)

        query = described_class.new(depends_on: django, github_owner_id: owner_id2)
        expect(query.dependent_count).to eq(1)
      end
    end
  end
end
