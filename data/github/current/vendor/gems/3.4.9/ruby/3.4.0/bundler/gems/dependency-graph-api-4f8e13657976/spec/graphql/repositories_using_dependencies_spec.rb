require "rails_helper"

describe "querying repositoriesUsingDependencies" do
  before do
    factory do
      repo_using_django1 = Repository.create!(github_repository_id: 1, nwo: "some/project",
        github_owner_id: 1, public: true)
      repo_using_django2 = Repository.create!(github_repository_id: 2, nwo: "some/project2",
        github_owner_id: 1, public: true)
      repo_using_django3 = Repository.create!(github_repository_id: 3, nwo: "some/project3",
        github_owner_id: 1, public: true)
      repo_using_djangoproject = Repository.create!(github_repository_id: 4, nwo: "some/other-project",
        github_owner_id: 1, public: false)
      repo_using_rails = Repository.create!(github_repository_id: 5, nwo: "OtherOwner/Project",
        github_owner_id: 2, public: true)
      repo_using_log4j1 = Repository.create!(github_repository_id: 6,
        nwo: "some/neato-project", github_owner_id: 1, public: true)
      repo_using_log4j2 = Repository.create!(github_repository_id: 7,
        nwo: "some/neato-project2", github_owner_id: 1, public: true)

      rubygems = Types::PackageManager[:rubygems]
      pip = Types::PackageManager[:pip]
      maven = Types::PackageManager[:maven]

      AbstractRepositoryDependency.create!(repository_id: repo_using_django1.id,
        package_manager: pip, package_name: "django")
      AbstractRepositoryDependency.create!(repository_id: repo_using_django2.id,
        package_manager: pip, package_name: "django")
      AbstractRepositoryDependency.create!(repository_id: repo_using_django3.id,
        package_manager: pip, package_name: "django")
      AbstractRepositoryDependency.create!(repository_id: repo_using_djangoproject.id,
        package_manager: pip, package_name: "djangoproject.com")
      AbstractRepositoryDependency.create!(repository_id: repo_using_rails.id,
        package_manager: rubygems, package_name: "rails")
      AbstractRepositoryDependency.create!(repository_id: repo_using_log4j1.id,
        package_manager: maven, package_name: "log4j")
      AbstractRepositoryDependency.create!(repository_id: repo_using_log4j2.id,
        package_manager: maven, package_name: "log4j")

      django = given_package("django", "4.2.1", :pip,
        repository_id: 11,
        last_published_at: 1.month.ago
      )
      .update_package_repository({ nwo: "django/django" })
      .dependency("djangoproject.com", "1.2.1").package

      given_package("djangoproject.com", "1.2.1", :pip,
        repository_id: 13,
        last_published_at: 1.day.ago)
      .update_package_repository({ nwo: "django/djangoproject.com" })

      given_manifest(
        github_repo_id: 100,
        package_manager: :pip,
        manifest_type:  :requirements_txt,
        filename:       "requirements.txt",
        path:           "/",
        dependencies:   [
          {
            package_name: "django",
            requirements: "= 4.2.1",
          },
        ]
      )

      given_package("rails", "3.3.3", :rubygems,
        repository_id: 14)
      .update_package_repository({ nwo: "rails/rails" })

      given_package("log4j", "1.2.3", :maven,
        repository_id: 15,
        last_published_at: 1.second.ago)
      .update_package_repository({ nwo: "apache/log4j" })
    end
  end

  it "returns results for each of the given dependency IDs" do
    query <<-QUERY.strip_heredoc
      {
        repositoriesUsingDependencies(ownerId: 1, dependencyIds: [11, 13, 14, 15]) {
          dependencyId
          repositories
        }
      }
    QUERY

    repos_using_dependencies = results[:repositoriesUsingDependencies]

    expect(repos_using_dependencies.size).to eq(4)

    django_row = repos_using_dependencies.detect { |hash| hash[:dependencyId] == 11 }
    expect(django_row).to_not be_nil
    expect(django_row[:repositories]).to eq([1, 2, 3])

    djangoproject_row = repos_using_dependencies.detect { |hash| hash[:dependencyId] == 13 }
    expect(djangoproject_row).to_not be_nil
    expect(djangoproject_row[:repositories]).to eq([4])

    rails_row = repos_using_dependencies.detect { |hash| hash[:dependencyId] == 14 }
    expect(rails_row).to_not be_nil
    expect(rails_row[:repositories]).to eq([])

    log4j_row = repos_using_dependencies.detect { |hash| hash[:dependencyId] == 15 }
    expect(log4j_row).to_not be_nil
    expect(log4j_row[:repositories]).to eq([6, 7])
  end

  it "returns results only for the specified repository owner" do
    query <<-QUERY.strip_heredoc
      {
        repositoriesUsingDependencies(ownerId: 2, dependencyIds: [11, 13, 14, 15]) {
          dependencyId
          repositories
        }
      }
    QUERY

    repos_using_dependencies = results[:repositoriesUsingDependencies]

    expect(repos_using_dependencies.size).to eq(4)

    django_row = repos_using_dependencies.detect { |hash| hash[:dependencyId] == 11 }
    expect(django_row).to_not be_nil
    expect(django_row[:repositories]).to eq([])

    djangoproject_row = repos_using_dependencies.detect { |hash| hash[:dependencyId] == 13 }
    expect(djangoproject_row).to_not be_nil
    expect(djangoproject_row[:repositories]).to eq([])

    rails_row = repos_using_dependencies.detect { |hash| hash[:dependencyId] == 14 }
    expect(rails_row).to_not be_nil
    expect(rails_row[:repositories]).to eq([5])

    log4j_row = repos_using_dependencies.detect { |hash| hash[:dependencyId] == 15 }
    expect(log4j_row).to_not be_nil
    expect(log4j_row[:repositories]).to eq([])
  end

  context "caching" do
    let(:memory_store) { ActiveSupport::Cache::MemoryStore.new }

    before do
      allow(Rails).to receive(:cache).and_return(memory_store)
    end

    after do
      allow(Rails).to receive(:cache).and_call_original
    end

    it "returns the same results twice, but hits the cache on the second time" do
      expected_query = <<-QUERY.strip_heredoc
        {
          repositoriesUsingDependencies(ownerId: 1, dependencyIds: [11, 13, 15]) {
            dependencyId
            repositories
          }
        }
      QUERY

      query(expected_query)

      repos_using_dependencies = results[:repositoriesUsingDependencies]
      dependency_ids = repos_using_dependencies.map { |hash| hash[:dependencyId] }.sort
      expect(dependency_ids).to eq([11, 13, 15])

      expect do
        query(expected_query)
      end.to make_database_queries(count: 0)

      repos_using_dependencies = results[:repositoriesUsingDependencies]
      dependency_ids = repos_using_dependencies.map { |hash| hash[:dependencyId] }.sort
      expect(dependency_ids).to eq([11, 13, 15])

      django_row = repos_using_dependencies.detect { |hash| hash[:dependencyId] == 11 }
      expect(django_row).to_not be_nil
      expect(django_row[:repositories]).to eq([1, 2, 3])
    end
  end
end
