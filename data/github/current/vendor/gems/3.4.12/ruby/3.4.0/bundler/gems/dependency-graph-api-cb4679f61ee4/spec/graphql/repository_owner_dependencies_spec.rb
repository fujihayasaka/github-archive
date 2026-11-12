require "rails_helper"

describe "querying repositoryOwnerDependencies" do
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

      given_package("rake", "2.0.0", :rubygems,
        repository_id: 16,
        last_published_at: 1.second.ago
      )
      .update_package_repository({ nwo: "ruby/rake" })


      given_manifest(
        github_repo_id: repo_using_rails.github_repository_id,
        manifest_type:  :gemfile_lock,
        filename:       "Gemfile.lock",
        path:           "/",
        dependencies:   [
          {
            package_name: "rake",
            requirements: "= 2.0.0",
          },
        ]
      )

      rails = given_package("rails", "3.3.3", :rubygems,
        repository_id: 14,
      )
      .update_package_repository({ nwo: "rails/rails" })
      .dependency("rake", "2.0.0").package

      given_package("log4j", "1.2.3", :maven,
        repository_id: 15,
        last_published_at: 1.second.ago)
        .update_package_repository({ nwo: "apache/log4j" })

    end
  end

  it "sorts by package name by default" do
    query <<-QUERY.strip_heredoc
      {
        repositoryOwnerDependencies(ownerId: 1, publicOnly: false) {
          dependencies
        }
      }
    QUERY

    repo_ids = results[:repositoryOwnerDependencies][:dependencies]

    expect(repo_ids).to eq([11, 13, 15])
  end

  it "checks only the requested repositories for dependencies" do
    query <<-QUERY.strip_heredoc
      {
        repositoryOwnerDependencies(ownerId: 1, publicOnly: false, repositoryIds: [4]) {
          dependencies
        }
      }
    QUERY
    expect(results[:repositoryOwnerDependencies][:dependencies]).to eq([13]) # djangoproject

    query <<-QUERY.strip_heredoc
      {
        repositoryOwnerDependencies(ownerId: 1, publicOnly: false, repositoryIds: [1, 4]) {
          dependencies
        }
      }
    QUERY
    expect(results[:repositoryOwnerDependencies][:dependencies]).to eq([11, 13]) # django, djangoproject
  end

  it "includes only direct dependencies when specified" do
    query <<-QUERY.strip_heredoc
      {
        repositoryOwnerDependencies(ownerId: 2, directOnly: true, packageManager: RUBYGEMS) {
          dependencies
        }
      }
    QUERY

    repo_ids = results[:repositoryOwnerDependencies][:dependencies]

    expect(repo_ids).to eq([14]) # rails
  end

  it "includes indirect dependencies when specified" do
    query <<-QUERY.strip_heredoc
      {
        repositoryOwnerDependencies(ownerId: 2, directOnly: false, packageManager: RUBYGEMS) {
          dependencies
        }
      }
    QUERY

    repo_ids = results[:repositoryOwnerDependencies][:dependencies]

    expect(repo_ids).to eq([14, 16]) # rails, rake
  end

  it "excludes dependencies for private repositories when specified" do
    query <<-QUERY.strip_heredoc
      {
        repositoryOwnerDependencies(ownerId: 1, publicOnly: true) {
          dependencies
        }
      }
    QUERY

    repo_ids = results[:repositoryOwnerDependencies][:dependencies]

    expect(repo_ids).to eq([11, 15])
  end

  it "gives dependencies regardless of package manager" do
    query <<-QUERY.strip_heredoc
      {
        repositoryOwnerDependencies(ownerId: 2, publicOnly: false) {
          dependencies
        }
      }
    QUERY

    repo_ids = results[:repositoryOwnerDependencies][:dependencies]

    expect(repo_ids).to eq([14, 16])
  end

  it "handles invalid owner IDs" do
    query <<-QUERY.strip_heredoc
       {
         repositoryOwnerDependencies(ownerId: 1234567, publicOnly: false) {
           dependencies
         }
       }
    QUERY

    expect(results[:repositoryOwnerDependencies][:dependencies]).to eq([])
  end

  it "supports sorting by package manager" do
    query <<-QUERY.strip_heredoc
      {
        repositoryOwnerDependencies(ownerId: 1, publicOnly: true, sortBy: PACKAGE_MANAGER) {
          dependencies
        }
      }
    QUERY

    repo_ids = results[:repositoryOwnerDependencies][:dependencies]

    # log4j (Maven), django (pip)
    expect(repo_ids).to eq([15, 11])
  end

  it "supports filtering by one package manager" do
    query <<-QUERY.strip_heredoc
      {
        repositoryOwnerDependencies(ownerId: 1, publicOnly: false, packageManager: MAVEN) {
          dependencies
        }
      }
    QUERY

    repo_ids = results[:repositoryOwnerDependencies][:dependencies]

    expect(repo_ids).to eq([15])
  end

  it "supports filtering by multiple package managers" do
    query <<-QUERY.strip_heredoc
      {
        repositoryOwnerDependencies(ownerId: 1, publicOnly: false, packageManagers: [MAVEN, PIP]) {
          dependencies
        }
      }
    QUERY

    repo_ids = results[:repositoryOwnerDependencies][:dependencies]

    expect(repo_ids).to eq([11, 13, 15]) # django, djangoproject.com, log4j
  end

  it "allows specifying package manager via both arguments" do
    query <<-QUERY.strip_heredoc
      {
        repositoryOwnerDependencies(ownerId: 1, publicOnly: false, packageManager: MAVEN, packageManagers: [PIP]) {
          dependencies
        }
      }
    QUERY

    repo_ids = results[:repositoryOwnerDependencies][:dependencies]

    expect(repo_ids).to eq([11, 13, 15]) # django, djangoproject.com, log4j
  end

  it "supports sorting by package publish date, descending" do
    query <<-QUERY.strip_heredoc
      {
        repositoryOwnerDependencies(ownerId: 1, publicOnly: false, sortBy: RECENTLY_PUBLISHED) {
          dependencies
        }
      }
    QUERY

    repo_ids = results[:repositoryOwnerDependencies][:dependencies]

    expect(repo_ids).to eq([15, 13, 11])
  end

  it "supports sorting by package publish date, ascending" do
    query <<-QUERY.strip_heredoc
      {
        repositoryOwnerDependencies(ownerId: 1, publicOnly: false, sortBy: LEAST_RECENTLY_PUBLISHED) {
          dependencies
        }
      }
    QUERY

    repo_ids = results[:repositoryOwnerDependencies][:dependencies]

    expect(repo_ids).to eq([11, 13, 15])
  end

  it "supports sorting by most used packages" do
    query <<-QUERY.strip_heredoc
      {
        repositoryOwnerDependencies(ownerId: 1, publicOnly: false, sortBy: MOST_USED) {
          dependencies
        }
      }
    QUERY

    repo_ids = results[:repositoryOwnerDependencies][:dependencies]

    expect(repo_ids).to eq([11, 15, 13])
  end

  it "supports sorting by least used packages" do
    query <<-QUERY.strip_heredoc
      {
        repositoryOwnerDependencies(ownerId: 1, publicOnly: false, sortBy: LEAST_USED) {
          dependencies
        }
      }
    QUERY

    repo_ids = results[:repositoryOwnerDependencies][:dependencies]

    expect(repo_ids).to eq([13, 15, 11])
  end
end
