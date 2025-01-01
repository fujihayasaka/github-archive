require "rails_helper"

describe "querying for allRepositoriesWithVersionRange" do
  before do
    factory do
      given_manifest(
        github_repo_id: 100,
        manifest_type:  :gemfile,
        filename:       "Gemfile",
        path:           "/",
        revision:       1,
        dependencies:   [
          {
            package_name: "rails",
            requirements: "= 5.0.0",
          },
        ]
      )
      given_manifest(
        github_repo_id: 200,
        manifest_type:  :gemfile_lock,
        filename:       "Gemfile.lock",
        path:           "/",
        revision:       1,
        dependencies:   [
          {
            package_name: "rails",
            requirements: "~> 5.0.0",
          },
        ]
      )

      # Excluded by package
      given_manifest(
        github_repo_id: 300,
        manifest_type:  :gemfile_lock,
        filename:       "Gemfile.lock",
        path:           "/",
        revision:       1,
        dependencies:   [
          {
            package_name: "rake",
            requirements: "> 0.0.0",
          },
        ]
      )

      # Excluded by version
      given_manifest(
        github_repo_id: 400,
        manifest_type:  :gemfile,
        filename:       "Gemfile",
        path:           "/",
        revision:       1,
        dependencies:   [
          {
            package_name: "rails",
            requirements: "~> 4.2.0",
          },
        ]
      )

      # Excluded by package manager
      given_manifest(
        github_repo_id: 500,
        manifest_type:  :gemfile_lock,
        filename:       "Gemfile.lock",
        path:           "/",
        revision:       1,
        dependencies:   [
          {
            package_name: "rake",
            requirements: "> 0.0.0",
          },
        ]
      )

      given_manifest(
        github_repo_id: 600,
        manifest_type:  :gemfile_lock,
        filename:       "Gemfile.lock",
        path:           "/",
        revision:       2,
        dependencies:   [
          {
            package_name: "actionview",
            requirements: "= 5.1.6.1",
            last_seen_at_revision: 1, # Rejected, not current
          },
        ]
      )

      given_manifest(
        github_repo_id: 700,
        manifest_type:  :gemfile_lock,
        filename:       "Gemfile.lock",
        path:           "/",
        revision:       2,
        dependencies:   [
          {
            package_name: "actionview",
            requirements: "= 5.1.6.2",
            last_seen_at_revision: 2, # Current
          },
        ]
      )
    end
  end

  context "when it has private repositories" do
    before do
      Repository.create!(github_repository_id: 42, public: false)
      factory do
        given_manifest(
          github_repo_id: 42,
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          revision:       1,
          dependencies:   [
            {
              package_name: "rails",
              requirements: "~> 5.0.0",
            },
          ]
        )
      end
    end

    context "enterprise" do
      before { DependencyGraphAPI.enterprise = true }

      after { DependencyGraphAPI.enterprise = nil }

      it "should include the private repository" do
        query <<-QUERY.strip_heredoc
        {
          allRepositoriesWithVersionRange(packageManager: RUBYGEMS, packageName: "rails", requirements: ">= 5.0.0, <= 5.1.0") {
            edges {
              node {
                repositoryId
              }
            }
          }
        }
        QUERY

        repo_ids = results[:allRepositoriesWithVersionRange][:edges].map { |e| e[:node][:repositoryId] }.sort
        expect(repo_ids).to eq [42, 100, 200]
      end
    end

    context "dotcom" do
      it "allRepositoriesWithVersionRange should include the private repository" do

        query <<-QUERY.strip_heredoc
        {
          allRepositoriesWithVersionRange(packageManager: RUBYGEMS, packageName: "rails", requirements: ">= 5.0.0, <= 5.1.0") {
            edges {
              node {
                repositoryId
              }
            }
          }
        }
        QUERY

        repo_ids = results[:allRepositoriesWithVersionRange][:edges].map { |e| e[:node][:repositoryId] }.sort
        expect(repo_ids).to eq [42, 100, 200]
      end
    end
  end

  it "finds allRepositoriesWithVersionRange by package name and version bounds" do
    query <<-QUERY.strip_heredoc
      {
        allRepositoriesWithVersionRange(packageManager: RUBYGEMS, packageName: "rails", requirements: ">= 5.0.0, <= 5.1.0") {
          estimatedRepositoryCount
          edges {
            node {
              packageName
              requirements
              manifestType
              manifestPath
              manifestFilename
              repositoryId
            }
          }
        }
      }
    QUERY

    expect(results[:allRepositoriesWithVersionRange][:edges]).to eq([
      {
        node: {
          packageName:      "rails",
          requirements:     "= 5.0.0",
          manifestType:     "gemfile",
          manifestPath:     "/",
          manifestFilename: "Gemfile",
          repositoryId:     100,
        }
      },
      {
        node: {
          packageName:      "rails",
          requirements:     "~> 5.0.0",
          manifestType:     "gemfile_lock",
          manifestPath:     "/",
          manifestFilename: "Gemfile.lock",
          repositoryId:     200,
        }
      },
    ].sort_by(&sort_by(:repositoryId)))

    expect(results[:allRepositoriesWithVersionRange][:estimatedRepositoryCount]).to eq 2
  end

  it "doesn't require upper bounds" do
    query <<-QUERY.strip_heredoc
      {
        allRepositoriesWithVersionRange(packageManager: RUBYGEMS, packageName: "rails", requirements: ">= 5.0.0, <= 5.1.0") {
          estimatedRepositoryCount
          edges {
            node {
              packageName
              requirements
              manifestType
              manifestPath
              manifestFilename
              repositoryId
            }
          }
        }
      }
    QUERY

    expect(results[:allRepositoriesWithVersionRange][:edges]).to eq([
      {
        node: {
          packageName:      "rails",
          requirements:     "= 5.0.0",
          manifestType:     "gemfile",
          manifestPath:     "/",
          manifestFilename: "Gemfile",
          repositoryId:     100,
        }
      },
      {
        node: {
          packageName:      "rails",
          requirements:     "~> 5.0.0",
          manifestType:     "gemfile_lock",
          manifestPath:     "/",
          manifestFilename: "Gemfile.lock",
          repositoryId:     200,
        }
      },
    ].sort_by(&sort_by(:repositoryId)))

    expect(results[:allRepositoriesWithVersionRange][:estimatedRepositoryCount]).to eq 2

  end

  it "returns nothing if the package manager is in preview" do
    stub_const("DependencyGraph::PACKAGE_MANAGER_PREVIEW", [
      Types::PackageManager[:rubygems]
    ])

    query <<~QUERY
      {
        allRepositoriesWithVersionRange(packageManager: RUBYGEMS, packageName: "rails", requirements: ">= 5.0.0") {
          edges {
            node {
              packageName
            }
          }
        }
      }
    QUERY

    expect(results[:allRepositoriesWithVersionRange][:edges]).to eq([])

    query <<~QUERY
      {
        allRepositoriesWithVersionRange(packageManager: RUBYGEMS, packageName: "rails", requirements: ">= 5.0.0", preview: true) {
          edges {
            node {
              packageName
            }
          }
        }
      }
    QUERY

    expect(results[:allRepositoriesWithVersionRange][:edges]).to eq([
      {
        node: {
          packageName: "rails",
        }
      },
      {
        node: {
          packageName: "rails",
        }
      },
    ].sort_by(&sort_by(:repositoryId)))
  end

  it "doesn't require lower bounds" do
    query <<-QUERY.strip_heredoc
      {
        allRepositoriesWithVersionRange(packageManager: RUBYGEMS, packageName: "rails", requirements: "<= 5.0.0") {
          estimatedRepositoryCount
          edges {
            node {
              packageName
              requirements
              manifestType
              manifestPath
              manifestFilename
              repositoryId
            }
          }
        }
      }
    QUERY

    expect(results[:allRepositoriesWithVersionRange][:edges]).to eq([
      {
        node: {
          packageName:      "rails",
          requirements:     "= 5.0.0",
          manifestType:     "gemfile",
          manifestPath:     "/",
          manifestFilename: "Gemfile",
          repositoryId:     100,
        }
      },
      {
        node: {
          packageName:      "rails",
          requirements:     "~> 4.2.0",
          manifestType:     "gemfile",
          manifestPath:     "/",
          manifestFilename: "Gemfile",
          repositoryId:     400,
        }
      },
    ].sort_by(&sort_by(:repositoryId)))

    expect(results[:allRepositoriesWithVersionRange][:estimatedRepositoryCount]).to eq 2
  end

  it "accepts a cursor and a limit" do
    dep_1    = get_manifest(repo_id: 100).entries.first
    cursor_1 = API::ConnectionWrappers::VersionRangeDependentsWrapper.encode(dep_1.to_cursor)
    dep_2    = get_manifest(repo_id: 200).entries.first
    cursor_2 = API::ConnectionWrappers::VersionRangeDependentsWrapper.encode(dep_2.to_cursor)

    # Limit the results to a single manifest
    query <<-QUERY.strip_heredoc
      {
        allRepositoriesWithVersionRange(packageManager: RUBYGEMS, packageName: "rails", requirements: ">= 5.0.0, <= 5.1.0", first: 1) {
          estimatedRepositoryCount
          edges {
            cursor
            node {
              packageName
              requirements
              manifestType
              manifestPath
              manifestFilename
              repositoryId
            }
          }
          pageInfo {
            hasPreviousPage
            hasNextPage
          }
        }
      }
    QUERY

    expect(results[:allRepositoriesWithVersionRange]).to eq({
      estimatedRepositoryCount: 2,
      edges: [
        {
          cursor: cursor_1,
          node: {
            packageName:      "rails",
            requirements:     "= 5.0.0",
            manifestType:     "gemfile",
            manifestPath:     "/",
            manifestFilename: "Gemfile",
            repositoryId:     100,
          },
        },
      ],
      pageInfo: {
        hasPreviousPage: false,
        hasNextPage:     true,
      }
    })

    # Skip the first manifest
    # Limit the results to a single manifest
    query <<-QUERY.strip_heredoc
      {
        allRepositoriesWithVersionRange(packageManager: RUBYGEMS, packageName: "rails", requirements: ">= 5.0.0, <= 5.1.0", first: 1, after: "#{cursor_1}") {
          estimatedRepositoryCount
          edges {
            cursor
            node {
              packageName
              requirements
              manifestType
              manifestPath
              manifestFilename
              repositoryId
            }
          }
          pageInfo {
            hasPreviousPage
            hasNextPage
          }
        }
      }
    QUERY

    expect(results[:allRepositoriesWithVersionRange]).to eq({
      estimatedRepositoryCount: 2,
      edges: [
        {
          cursor: cursor_2,
          node: {
            packageName:      "rails",
            requirements:     "~> 5.0.0",
            manifestType:     "gemfile_lock",
            manifestPath:     "/",
            manifestFilename: "Gemfile.lock",
            repositoryId:     200,
          },
        },
      ],
      pageInfo: {
        hasPreviousPage: true,
        hasNextPage:     false,
      }
    })
  end

  it "returns an error when the requirements are invalid" do
    query <<-QUERY.strip_heredoc
      {
        allRepositoriesWithVersionRange(packageManager: RUBYGEMS, packageName: "rails", requirements: "WRONG") {
          estimatedRepositoryCount
          edges {
            node {
              packageName
              requirements
            }
          }
        }
      }
    QUERY

    expect(graphql_errors).to include("Invalid version range")
  end

  it "catches estimatedRepositoryCount error, if the package manager is in preview" do
    stub_const("DependencyGraph::PACKAGE_MANAGER_PREVIEW", [
      Types::PackageManager[:rubygems]
    ])

    query <<~QUERY
      {
        allRepositoriesWithVersionRange(packageManager: RUBYGEMS, packageName: "rails", requirements: ">= 5.0.0") {
        estimatedRepositoryCount
        }
      }
      QUERY

    expect(results[:allRepositoriesWithVersionRange][:estimatedRepositoryCount]).to eq(0)
  end

  it "finds allRepositoriesWithVersionRange even if versions are more than 3 parts" do
    query <<-QUERY.strip_heredoc
      {
        allRepositoriesWithVersionRange(packageManager: RUBYGEMS, packageName: "actionview", requirements: ">= 5.1.0, <= 5.1.6.2") {
          estimatedRepositoryCount
          edges {
            node {
              packageName
              requirements
              manifestType
              manifestPath
              manifestFilename
              repositoryId
            }
          }
        }
      }
    QUERY

    expect(results[:allRepositoriesWithVersionRange][:edges]).to eq([
      {
        node: {
          packageName:      "actionview",
          requirements:     "= 5.1.6.2",
          manifestType:     "gemfile_lock",
          manifestPath:     "/",
          manifestFilename: "Gemfile.lock",
          repositoryId:     700,
        }
      }
    ].sort_by(&sort_by(:repositoryId)))
  end

  context "error conditions" do
    it "handles when repository record is missing" do
      # this test corresponds with bug from https://github.com/github/pe-security-workflows/issues/559
      manifest = ManifestFactory.new(
        github_repo_id: 16932052,
        git_ref: "afdedee0c373f05b5cb22e2b2d625c6f39c9ae3a",
        manifest_type:  4,
        package_manager: 3,
        filename:       "package.json",
        path:           "packages/Zen",
        revision:       0,
        dependencies:   [
          {
            package_name: "thing",
            requirements: "= 1.0.0",
          },
        ]
      ).create
      manifest.repository.delete

      query <<~QUERY
      {
        allRepositoriesWithVersionRange(packageManager: PIP, packageName: "thing", requirements: "= 1.0.0") {
          edges {
            node {
              packageName
              requirements
              manifestType
              manifestPath
              manifestFilename
              repositoryId
            }
          }
        }
      }
      QUERY

      expect(results[:allRepositoriesWithVersionRange][:edges][0][:node][:repositoryId]).to be_nil
    end
  end

  context "empty page support" do
    it "returns a dependentEndCursor to support advancing on empty pages" do
      query <<-QUERY.strip_heredoc
        {
          allRepositoriesWithVersionRange(packageManager: RUBYGEMS, packageName: "actionview", requirements: ">= 5.1.6.1", first: 1) {
            edges {
              node {
                packageName
              }
            }
            dependentEndCursor
          }
        }
      QUERY

      expect(results[:allRepositoriesWithVersionRange][:edges]).to be_empty
      expect(results[:allRepositoriesWithVersionRange][:dependentEndCursor]).not_to be_nil
    end
  end

  it "includes dependency scope information when requested" do
    factory do
      given_manifest(
        github_repo_id: 999,
        manifest_type:  :gemfile,
        filename:       "Gemfile",
        path:           "/",
        revision:       1,
        dependencies:   [
          {
            package_name: "rails",
            requirements: "~> 5.0.0",
            scope: "development",
          },
        ]
      )
    end

    query <<-QUERY.strip_heredoc
      {
        allRepositoriesWithVersionRange(packageManager: RUBYGEMS, packageName: "rails", requirements: ">= 5.0.0, <= 5.1.0") {
          estimatedRepositoryCount
          edges {
            node {
              packageName
              scope
              repositoryId
            }
          }
        }
      }
    QUERY

    expect(results[:allRepositoriesWithVersionRange][:edges]).to eq([
      {
        node: {
          packageName:      "rails",
          scope:            "runtime",
          repositoryId:     100,
        }
      },
      {
        node: {
          packageName:      "rails",
          scope:            "runtime",
          repositoryId:     200,
        }
      },
      {
        node: {
          packageName:      "rails",
          scope:            "development",
          repositoryId:     999,
        }
      },
    ].sort_by(&sort_by(:repositoryId)))
  end

  it "orders results by requirements then ID" do
    factory do
      given_manifest(
        github_repo_id: 101,
        manifest_type:  :gemfile,
        filename:       "Gemfile",
        path:           "/",
        dependencies:   [
          {
            package_name: "rails",
            requirements: "= 5.0.0",
          },
        ]
      )

      given_manifest(
        github_repo_id: 201,
        manifest_type:  :gemfile_lock,
        filename:       "Gemfile.lock",
        path:           "/",
        dependencies:   [
          {
            package_name: "rails",
            requirements: "~> 5.0.0",
          },
        ]
      )

      given_manifest(
        github_repo_id: 401,
        manifest_type:  :gemfile,
        filename:       "Gemfile",
        path:           "/",
        dependencies:   [
          {
            package_name: "rails",
            requirements: "~> 4.2.0",
          },
        ]
      )
    end

    query <<-QUERY.strip_heredoc
      {
        allRepositoriesWithVersionRange(packageManager: RUBYGEMS, packageName: "rails", requirements: "> 0") {
          estimatedRepositoryCount
          edges {
            node {
              repositoryId
              requirements
            }
          }
        }
      }
    QUERY

    expect(results[:allRepositoriesWithVersionRange][:edges]).to eq([
      {
        node: {
          repositoryId: 100,
          requirements: "= 5.0.0"
        },
      },
      {
        node: {
          repositoryId: 101,
          requirements: "= 5.0.0"
        },
      },
      {
        node: {
          repositoryId: 400,
          requirements: "~> 4.2.0"
        },
      },
      {
        node: {
          repositoryId: 401,
          requirements: "~> 4.2.0"
        },
      },
      {
        node: {
          repositoryId: 200,
          requirements: "~> 5.0.0"
        },
      },
      {
        node: {
          repositoryId: 201,
          requirements: "~> 5.0.0"
        },
      },
    ])

    dep    = get_manifest(repo_id: 400).entries.first
    cursor = API::ConnectionWrappers::VersionRangeDependentsWrapper.encode(dep.to_cursor)
    query <<-QUERY.strip_heredoc
      {
        allRepositoriesWithVersionRange(packageManager: RUBYGEMS, packageName: "rails", requirements: "> 0", after: "#{cursor}") {
          estimatedRepositoryCount
          edges {
            node {
              repositoryId
              requirements
            }
          }
        }
      }
    QUERY

    expect(results[:allRepositoriesWithVersionRange][:edges]).to eq([
      {
        node: {
          repositoryId: 401,
          requirements: "~> 4.2.0"
        },
      },
      {
        node: {
          repositoryId: 200,
          requirements: "~> 5.0.0"
        },
      },
      {
        node: {
          repositoryId: 201,
          requirements: "~> 5.0.0"
        },
      },
    ])
  end

  it "queries dg_manifest_dependencies if use_normalized_tables? is false" do
    allow(DependencyGraph).to receive(:use_normalized_tables?).and_return(false)

    expect do
      query <<-QUERY.strip_heredoc
        {
          allRepositoriesWithVersionRange(packageManager: RUBYGEMS, packageName: "rails", requirements: ">= 5.0.0, <= 5.1.0") {
            estimatedRepositoryCount
            edges {
              node {
                packageName
                requirements
                manifestType
                manifestPath
                manifestFilename
                repositoryId
                scope
              }
            }
          }
        }
      QUERY
    end.not_to make_database_queries(matching: /dg_manifest_entries/)

    expect(results[:allRepositoriesWithVersionRange][:edges]).to eq([
      {
        node: {
          packageName:      "rails",
          requirements:     "= 5.0.0",
          manifestType:     "gemfile",
          manifestPath:     "/",
          manifestFilename: "Gemfile",
          repositoryId:     100,
          scope:            "runtime"
        }
      },
      {
        node: {
          packageName:      "rails",
          requirements:     "~> 5.0.0",
          manifestType:     "gemfile_lock",
          manifestPath:     "/",
          manifestFilename: "Gemfile.lock",
          repositoryId:     200,
          scope:            "runtime"
        }
      },
    ].sort_by(&sort_by(:repositoryId)))

    expect(results[:allRepositoriesWithVersionRange][:estimatedRepositoryCount]).to eq 2
  end
end
