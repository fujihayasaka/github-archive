require "rails_helper"

shared_examples "querying for package releases in an organization scope" do |normalized_tables|
  let(:features) { double(:monolith_features) }

  before do
    allow(DependencyGraph).to receive(:use_normalized_tables?).and_return(normalized_tables)
    allow(DependencyGraph).to receive(:features).and_return(features)

    factory do
      org_repo = Repository.create!({
        github_repository_id: 10,
        github_owner_id: 20,
        nwo: "Anthophila/octokit"
      })

      PackageFactory.new("multi_xml", "0.5.2", :rubygems)
        .create!(published_at: "2018-10-10 20:33:33")
      PackageFactory.new("httparty", "2.0.1", :rubygems)
        .create!(published_at: "2018-09-05 20:33:33")

      given_manifest(
        github_repo_id: 10,
        manifest_type:  :gemfile_lock,
        package_manager: :rubygems,
        filename:       "Gemfile.lock",
        path:           "/",
        revision:       1,
        dependencies:   [
          {
            package_name: "multi_xml",
            requirements: "= 0.5.2",
          },
          {
            package_name: "httparty",
            requirements: "= 2.0.1",
          },
        ]
      )

      # affects us
      given_vulnerable_version_range({
        github_id: 123,
        package_name: "multi_xml",
        package_manager: :rubygems,
        version_range: "> 0, < 1.0",
        severity: "moderate"
      })

      given_vulnerable_version_range({
        github_id: 168,
        package_name: "multi_xml",
        package_manager: :rubygems,
        version_range: "> 0, < 3.0",
        severity: "high"
      })

      # does not affect us
      given_vulnerable_version_range({
        github_id: 124,
        package_name: "httparty",
        package_manager: :rubygems,
        version_range: "< 2.0.1",
        severity: "critical"
      })

      org_repo2 = Repository.create!({
        github_repository_id: 100,
        github_owner_id: 20,
        nwo: "Anthophila/manifest-listener"
      })

      PackageFactory.new("lodash", "1.0.0", :npm)
        .create!(published_at: "2018-10-10 20:33:33")

      PackageFactory.new("mocha", "4.0.0", :npm)
        .create!(published_at: "2018-09-05 20:33:33")

      PackageFactory.new("multi_xml", "0.5.2", :npm)
        .create!(published_at: "2018-10-09 20:33:33")

      given_manifest(
        github_repo_id: 100,
        manifest_type:  :package_lock_json,
        package_manager: :npm,
        filename:       "package-lock.json",
        path:           "/",
        revision:       1,
        dependencies:   [
          {
            package_name: "lodash",
            requirements: "= 1.0.0",
          },
          {
            package_name: "mocha",
            requirements: "= 4.0.0",
          },
          {
            package_name: "multi_xml",
            requirements: "= 0.5.2",
          },
        ]
      )

      org_repo3 = Repository.create!({
        github_repository_id: 5000,
        github_owner_id: 30,
        nwo: "ManifestParser/nuget"
      })

      PackageFactory.new("autofac", "1.0.0", :nuget)
        .create!(published_at: "2018-10-10 20:33:33", updated_at: "2019-01-10 20:33:33")
      PackageFactory.new("xunit", "4.0.0", :nuget)
        .create!(published_at: "2018-09-05 20:33:33", updated_at: "2018-08-11 20:33:33")

      given_manifest(
        github_repo_id: 5000,
        manifest_type:  :package_config,
        package_manager: :nuget,
        filename:       "packages.config",
        path:           "/",
        revision:       1,
        dependencies:   [
          {
            package_name: "autofac",
            requirements: "= 1.0.0",
          },
          {
            package_name: "xunit",
            requirements: "= 4.0.0",
          },
        ]
      )

      Repository.create!({
        github_repository_id: 5001,
        github_owner_id: 31,
        nwo: "Manifes_Parser/nuget"
      })

      given_manifest(
        github_repo_id: 5001,
        manifest_type:  :package_config,
        package_manager: :nuget,
        filename:       "packages.config",
        path:           "/",
        revision:       1,
        dependencies:   [
          {
            package_name: "autofac",
            requirements: "= 1.0.0",
          }
        ]
      )

      Views::PackageReleaseDependentCount.rebuild_for(20, 30, 31)
      Views::PackageReleaseVulnerabilitiesCount.rebuild
    end
  end

  it "finds packages used in a specific organization" do
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [30]) {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
                publishedOn
              }
              dependentsCount
            }
          }
        }
      }
    QUERY
    expect(results).to eq({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "autofac",
                packageManager: "NUGET",
                version: "1.0.0",
                publishedOn: "2018-10-10",
              },
              dependentsCount: 1
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "xunit",
                packageManager: "NUGET",
                version: "4.0.0",
                publishedOn: "2018-09-05",
              },
              dependentsCount: 1
            }
          }
        ]
      }
    })
  end

  it "includes go packages in results" do
    factory do
      given_package("example.com/go_package", "v1.2.3", :go)

      given_manifest(
        github_repo_id: 5001,
        manifest_type:  :go_mod,
        package_manager:  :go,
        path:           "/",
        filename: "go.mod",
        revision:       1,
        dependencies: [
          package_name: "example.com/go_package",
          requirements: "= 1.2.3"
        ]
      )
    end

    Views::PackageReleaseDependentCount.rebuild_for(31)

    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [31]) {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
              }
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "autofac",
                packageManager: "NUGET",
                version: "1.0.0",
              }
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "example.com/go_package",
                packageManager: "GO",
                version: "v1.2.3",
              }
            }
          },
        ]
        }
    })
  end

  it "requires organization names to be non-empty" do
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: []) {
          totalCount
        }
      }
    QUERY

    expect(graphql_errors).to eq(["Missing required ownerIds on repositoryPackageReleases"])

    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], first: 1) {
          edges {
            node {
              dependents(ownerIds: []) {
                exactCount
              }
            }
          }
        }
      }
    QUERY

    expect(graphql_errors).to eq(["Missing required ownerIds on dependents"])
  end

  it "returns a dependents count summed across multiple owner ids" do
    factory do
      Repository.create!({
        github_repository_id: 5002,
        github_owner_id: 30,
        nwo: "ManifestParser/octokit2"
      })

      given_manifest(
        github_repo_id: 5002,
        manifest_type:  :gemfile_lock,
        package_manager: :rubygems,
        filename:       "Gemfile.lock",
        path:           "/",
        revision:       1,
        dependencies:   [
          {
            package_name: "httparty",
            requirements: "= 2.0.1",
          },
        ]
      )

      Views::PackageReleaseDependentCount.rebuild_for(20, 30)
    end

    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(first: 1, ownerIds: [20, 30], exactMatch: true, name: "httparty", packageManager: RUBYGEMS) {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
              }
              dependentsCount
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "httparty",
                packageManager: "RUBYGEMS",
                version: "2.0.1",
              },
              dependentsCount: 2
            }
          },
        ],
      }
    })
  end

  it "finds packages used in an organization, can differentiate packages by ecosystem" do
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(first: 10, ownerIds: [20]) {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
                publishedOn
              }
              dependentsCount
            }
          }

          totalCount
        }
      }
    QUERY

    # We should get all 5 package releases back
    # This should Include two multi_xml package releases with different package managers
    expect(results[:repositoryPackageReleases][:edges].count).to eq 5

    expect(results).to eq({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "multi_xml",
                packageManager: "RUBYGEMS",
                version: "0.5.2",
                publishedOn: "2018-10-10",
              },
              dependentsCount: 1
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "httparty",
                packageManager: "RUBYGEMS",
                version: "2.0.1",
                publishedOn: "2018-09-05",
              },
              dependentsCount: 1
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "lodash",
                packageManager: "NPM",
                version: "1.0.0",
                publishedOn: "2018-10-10",
              },
              dependentsCount: 1
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "mocha",
                packageManager: "NPM",
                version: "4.0.0",
                publishedOn: "2018-09-05",
              },
              dependentsCount: 1
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "multi_xml",
                packageManager: "NPM",
                version: "0.5.2",
                publishedOn: "2018-10-09",
              },
              dependentsCount: 1
            }
          },
        ],

        totalCount: 5
      }
    })
  end

  it "finds packages used in an organization, and sorts by newest package release" do
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], sortBy: NEWEST) {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
                publishedOn
              }
              dependentsCount
              vulnerabilitiesCount
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "lodash",
                packageManager: "NPM",
                version: "1.0.0",
                publishedOn: "2018-10-10",
              },
              dependentsCount: 1,
              vulnerabilitiesCount: 0
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "multi_xml",
                packageManager: "RUBYGEMS",
                version: "0.5.2",
                publishedOn: "2018-10-10",
              },
              dependentsCount: 1,
              vulnerabilitiesCount: 2
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "multi_xml",
                packageManager: "NPM",
                version: "0.5.2",
                publishedOn: "2018-10-09",
              },
              dependentsCount: 1,
              vulnerabilitiesCount: 0
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "mocha",
                packageManager: "NPM",
                version: "4.0.0",
                publishedOn: "2018-09-05",
              },
              dependentsCount: 1,
              vulnerabilitiesCount: 0
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "httparty",
                packageManager: "RUBYGEMS",
                version: "2.0.1",
                publishedOn: "2018-09-05",
              },
              dependentsCount: 1,
              vulnerabilitiesCount: 0
            }
          },
        ]
      }
    })
  end

  it "finds packages used in an organization, and sorts by oldest package release" do
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], sortBy: OLDEST) {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
                publishedOn
              }
              dependentsCount
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "httparty",
                packageManager: "RUBYGEMS",
                version: "2.0.1",
                publishedOn: "2018-09-05",
              },
              dependentsCount: 1
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "mocha",
                packageManager: "NPM",
                version: "4.0.0",
                publishedOn: "2018-09-05",
              },
              dependentsCount: 1
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "multi_xml",
                packageManager: "NPM",
                version: "0.5.2",
                publishedOn: "2018-10-09",
              },
              dependentsCount: 1
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "multi_xml",
                packageManager: "RUBYGEMS",
                version: "0.5.2",
                publishedOn: "2018-10-10",
              },
              dependentsCount: 1
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "lodash",
                packageManager: "NPM",
                version: "1.0.0",
                publishedOn: "2018-10-10",
              },
              dependentsCount: 1
            }
          },
        ]
      }
    })
  end

  it "finds packages used in a specific organization, and sorts releases by most recently updated" do
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [30], sortBy: RECENTLY_UPDATED) {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
                publishedOn
              }
              dependentsCount
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "autofac",
                packageManager: "NUGET",
                version: "1.0.0",
                publishedOn: "2018-10-10",
              },
              dependentsCount: 1
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "xunit",
                packageManager: "NUGET",
                version: "4.0.0",
                publishedOn: "2018-09-05",
              },
              dependentsCount: 1
            }
          }
        ]
      }
    })
  end

  it "finds packages used in a specific organization, and sorts releases by least recently updated" do
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [30], sortBy: LEAST_RECENTLY_UPDATED) {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
                publishedOn
              }
              dependentsCount
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "xunit",
                packageManager: "NUGET",
                version: "4.0.0",
                publishedOn: "2018-09-05",
              },
              dependentsCount: 1
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "autofac",
                packageManager: "NUGET",
                version: "1.0.0",
                publishedOn: "2018-10-10",
              },
              dependentsCount: 1
            }
          },
        ]
      }
    })
  end

  it "finds and filters packages in a specific organization based off package manager" do
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], packageManager: NPM) {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
                publishedOn
              }
              dependentsCount
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "lodash",
                packageManager: "NPM",
                version: "1.0.0",
                publishedOn: "2018-10-10",
              },
              dependentsCount: 1
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "mocha",
                packageManager: "NPM",
                version: "4.0.0",
                publishedOn: "2018-09-05",
              },
              dependentsCount: 1
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "multi_xml",
                packageManager: "NPM",
                version: "0.5.2",
                publishedOn: "2018-10-09",
              },
              dependentsCount: 1
            }
          },
        ]
      }
    })
  end

  it "finds and filters packages used in a specific organization based off package name" do

    # Does substring matching on name by default
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [30], name: "auto") {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
                publishedOn
              }
              dependentsCount
            }
          }

          totalCount
        }
      }
    QUERY

    expect(results).to eq({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "autofac",
                packageManager: "NUGET",
                version: "1.0.0",
                publishedOn: "2018-10-10",
              },
              dependentsCount: 1
            }
          },
        ],

        totalCount: 1
      }
    })

    # Should find no match if exact match is used and package name is substring of desired package name
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [30], name: "auto", exactMatch: true) {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
                publishedOn
              }
              dependentsCount
            }
          }

          totalCount
        }
      }
    QUERY

    expect(results[:repositoryPackageReleases][:edges].count).to eq 0

    # Should find match if exactMatch is true and exact name is given
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [30], name: "autofac", exactMatch: true) {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
                publishedOn
              }
              dependentsCount
            }
          }

          totalCount
        }
      }
    QUERY

    expect(results).to eq({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "autofac",
                packageManager: "NUGET",
                version: "1.0.0",
                publishedOn: "2018-10-10",
              },
              dependentsCount: 1
            }
          },
        ],

        totalCount: 1
      }
    })
  end

  it "properly escapes name when comparing" do
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], name: "_") {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
              }
            }
          }

          totalCount
        }
      }
    QUERY

    expect(results).to eq({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "multi_xml",
                packageManager: "RUBYGEMS",
              },
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "multi_xml",
                packageManager: "NPM",
              },
            }
          }
        ],

        totalCount: 2
      }
    })
  end

  it "finds and filters packages used in a specific organization based off package release version" do
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], name: "multi_xml", version: "< 1.0.0") {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
                publishedOn
              }
              dependentsCount
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "multi_xml",
                packageManager: "RUBYGEMS",
                version: "0.5.2",
                publishedOn: "2018-10-10",
              },
              dependentsCount: 1
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "multi_xml",
                packageManager: "NPM",
                version: "0.5.2",
                publishedOn: "2018-10-09",
              },
              dependentsCount: 1
            }
          },
        ]
      }
    })
  end

  it "finds and filters packages used in a specific organization based off package release named version" do
    Repository.create!({
      github_repository_id: 90,
      github_owner_id: 20,
      nwo: "Anthophila/octokit"
    })

    PackageFactory.new("actions/checkout", "main", :actions)
    .create!(published_at: "2018-09-05 20:33:33")

    factory.given_manifest(
      github_repo_id: 90,
      manifest_type:  :workflow_yaml,
      package_manager: :actions,
      filename:       "stuff.yaml",
      path:           ".github/workflows",
      revision:       1,
      dependencies:   [
        {
          package_name: "actions/checkout",
          requirements: "= main",
        },
      ]
    )


    Views::PackageReleaseDependentCount.rebuild_for(20)
    Views::PackageReleaseVulnerabilitiesCount.rebuild

    query <<-QUERY.strip_heredoc
    {
      repositoryPackageReleases(ownerIds: [20], name: "actions/checkout", version: "main") {
        edges {
          node {
            packageRelease {
              packageName
              packageManager
              version
            }
            dependentsCount
          }
        }
      }
    }
  QUERY

    expect(results).to eq({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "actions/checkout",
                packageManager: "ACTIONS",
                version: "main",
              },
              dependentsCount: 1
            }
          },
        ]
      }
    })
  end

  it "finds all package releases in an organization; if given a version without a package name" do
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], version: "< 0.0.0") {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
                publishedOn
              }
              dependentsCount
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "multi_xml",
                packageManager: "RUBYGEMS",
                version: "0.5.2",
                publishedOn: "2018-10-10",
              },
              dependentsCount: 1
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "httparty",
                packageManager: "RUBYGEMS",
                version: "2.0.1",
                publishedOn: "2018-09-05",
              },
              dependentsCount: 1
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "lodash",
                packageManager: "NPM",
                version: "1.0.0",
                publishedOn: "2018-10-10",
              },
              dependentsCount: 1
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "mocha",
                packageManager: "NPM",
                version: "4.0.0",
                publishedOn: "2018-09-05",
              },
              dependentsCount: 1
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "multi_xml",
                packageManager: "NPM",
                version: "0.5.2",
                publishedOn: "2018-10-09",
              },
              dependentsCount: 1
            }
          },
        ]
      }
    })
  end

  it "finds and filters packages used in a specific organization based off vulnerability severity" do
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], severity: HIGH) {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
              }
              dependentsCount
              vulnerabilitiesCount
            }
          }
          totalCount
        }
      }
    QUERY

    expect(results).to eq({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "multi_xml",
                packageManager: "RUBYGEMS",
                version: "0.5.2",
              },
              dependentsCount: 1,
              vulnerabilitiesCount: 2
            }
          },
        ],
        totalCount: 1
      }
    })
  end

  it "will find no package releases for a package if given version does not exist in organization" do
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], name: "multi_xml", version: "> 0.5.2") {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
                publishedOn
              }
              dependentsCount
            }
          }
        }
      }
    QUERY

    # no package release called multi_xml with a version lower than 0.5.2
    expect(results[:repositoryPackageReleases][:edges]).to be_empty
  end

  it "will find package releases in an organization and order them by dependents count" do

    Repository.create!({
      github_repository_id: 6000,
      github_owner_id: 20,
      nwo: "Anthophila/test-repo"
    })

    factory do
      given_manifest(
        github_repo_id: 6000,
        manifest_type:  :package_lock_json,
        package_manager: :npm,
        filename:       "package-lock.json",
        path:           "/",
        revision:       1,
        dependencies:   [
          {
            package_name: "lodash",
            requirements: "= 1.0.0",
          },
          {
            package_name: "mocha",
            requirements: "= 4.0.0",
          },
        ]
      )

      Repository.create!({
        github_repository_id: 7000,
        github_owner_id: 20,
        nwo: "Anthophila/test-repo-2"
      })

      given_manifest(
        github_repo_id: 7000,
        manifest_type:  :package_lock_json,
        package_manager: :npm,
        filename:       "package-lock.json",
        path:           "/",
        revision:       1,
        dependencies:   [
          {
            package_name: "lodash",
            requirements: "= 1.0.0",
          },
        ]
      )

      Views::PackageReleaseDependentCount.rebuild_for(20, 30, 31)
      Views::PackageReleaseVulnerabilitiesCount.rebuild
    end

    # Test sorts package releases by releases with most dependents first
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], sortBy: MOST_DEPENDENTS) {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
                publishedOn
              }
              dependentsCount
            }
          }
        }
      }
    QUERY

    r = results[:repositoryPackageReleases][:edges].map do |node|
      [node[:node][:packageRelease][:packageName], node[:node][:dependentsCount]]
    end

    expect(r.map(&:last)).to eq [3, 2, 1, 1, 1]

    # Test sorts package releases by releases with the least dependents first
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], sortBy: LEAST_DEPENDENTS) {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
                publishedOn
              }
              dependentsCount
            }
          }
        }
      }
    QUERY

    r = results[:repositoryPackageReleases][:edges].map do |node|
      [node[:node][:packageRelease][:packageName], node[:node][:dependentsCount]]
    end

    expect(r.map(&:last)).to eq [1, 1, 1, 2, 3]
  end

  it "will not throw an error if an invalid package version is passed, will ignore version and just return no releases" do
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], name: "lodash", version: "*0.5.2}") {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
                publishedOn
              }
              dependentsCount
            }
          }
        }
      }
    QUERY

    expect(results[:repositoryPackageReleases][:edges]).to be_empty
  end

  it "will find package releases in an org when a specific version is parsed without range specifier" do
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], name: "mocha", version: "4.0.0") {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
                publishedOn
              }
              dependentsCount
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "mocha",
                packageManager: "NPM",
                version: "4.0.0",
                publishedOn: "2018-09-05",
              },
              dependentsCount: 1
            }
          }
        ]
      }
    })
  end

  it "will not find package releases in an org when a specific version is parsed without range specifier, and version for release does not exist" do
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], name: "mocha", version: "1.0.0") {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
                publishedOn
              }
              dependentsCount
            }
          }
        }
      }
    QUERY

    # no package release called mocha with a version lower 1.0.0
    expect(results[:repositoryPackageReleases][:edges]).to be_empty
  end

  it "scope results to package releases with vulnerabilities" do
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], vulnerable: true) {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
              }
              dependentsCount
              vulnerabilitiesCount
            }
          }
          totalCount
        }
      }
    QUERY

    # only one package is vulnerable
    expect(results).to eq({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "multi_xml",
                packageManager: "RUBYGEMS",
                version: "0.5.2",
              },
              dependentsCount: 1,
              vulnerabilitiesCount: 2,
            }
          }
        ],
        totalCount: 1
      }
    })
  end

  it "scope results to package releases with vulnerabilities, and sorts them by most vulnerable" do
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], sortBy: MOST_VULNERABILITIES) {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
              }
              dependentsCount
              vulnerabilitiesCount
            }
          }
        }
      }
    QUERY


    expect(results).to eq({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "multi_xml",
                packageManager: "RUBYGEMS",
                version: "0.5.2",
              },
              dependentsCount: 1,
              vulnerabilitiesCount: 2,
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "multi_xml",
                packageManager: "NPM",
                version: "0.5.2",
              },
              dependentsCount: 1,
              vulnerabilitiesCount: 0,
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "mocha",
                packageManager: "NPM",
                version: "4.0.0",
              },
              dependentsCount: 1,
              vulnerabilitiesCount: 0,
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "lodash",
                packageManager: "NPM",
                version: "1.0.0",
              },
              dependentsCount: 1,
              vulnerabilitiesCount: 0,
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "httparty",
                packageManager: "RUBYGEMS",
                version: "2.0.1",
              },
              dependentsCount: 1,
              vulnerabilitiesCount: 0,
            }
          },
        ]
      }
    })
  end

  it "scope results to package releases with vulnerabilities, and sorts them by least vulnerable" do
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], sortBy: LEAST_VULNERABILITIES) {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
              }
              dependentsCount
              vulnerabilitiesCount
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "httparty",
                packageManager: "RUBYGEMS",
                version: "2.0.1",
              },
              dependentsCount: 1,
              vulnerabilitiesCount: 0,
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "lodash",
                packageManager: "NPM",
                version: "1.0.0",
              },
              dependentsCount: 1,
              vulnerabilitiesCount: 0,
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "mocha",
                packageManager: "NPM",
                version: "4.0.0",
              },
              dependentsCount: 1,
              vulnerabilitiesCount: 0,
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "multi_xml",
                packageManager: "NPM",
                version: "0.5.2",
              },
              dependentsCount: 1,
              vulnerabilitiesCount: 0,
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "multi_xml",
                packageManager: "RUBYGEMS",
                version: "0.5.2",
              },
              dependentsCount: 1,
              vulnerabilitiesCount: 2,
            }
          },
        ]
      }
    })
  end

  it "paginates over results in a stable manner" do
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], sortBy: NEWEST, first: 2) {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
                publishedOn
              }
            }
          }

          pageInfo {
            hasNextPage
            hasPreviousPage
            startCursor
            endCursor
          }
        }
      }
    QUERY

    expect(results).to match({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "lodash",
                packageManager: "NPM",
                version: "1.0.0",
                publishedOn: "2018-10-10",
              }
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "multi_xml",
                packageManager: "RUBYGEMS",
                version: "0.5.2",
                publishedOn: "2018-10-10",
              }
            }
          },
        ],

        pageInfo: a_hash_including(
          hasNextPage: true,
          hasPreviousPage: false
        )
      }
    })

    after = results[:repositoryPackageReleases][:pageInfo][:endCursor]
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], sortBy: NEWEST, first: 3, after: "#{after}") {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
                publishedOn
              }
            }
          }

          pageInfo {
            hasNextPage
            hasPreviousPage
            startCursor
            endCursor
          }
        }
      }
    QUERY

    expect(results).to match({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "multi_xml",
                packageManager: "NPM",
                version: "0.5.2",
                publishedOn: "2018-10-09",
              }
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "mocha",
                packageManager: "NPM",
                version: "4.0.0",
                publishedOn: "2018-09-05",
              },
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "httparty",
                packageManager: "RUBYGEMS",
                version: "2.0.1",
                publishedOn: "2018-09-05",
              }
            }
          },
        ],

        pageInfo: a_hash_including(
          hasNextPage: false,
          hasPreviousPage: true
        )
      }
    })

    before = results[:repositoryPackageReleases][:pageInfo][:startCursor]
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], sortBy: NEWEST, last: 1, before: "#{before}") {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
                publishedOn
              }
            }
          }

          pageInfo {
            hasNextPage
            hasPreviousPage
            startCursor
            endCursor
          }
        }
      }
    QUERY

    expect(results).to match({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "multi_xml",
                packageManager: "RUBYGEMS",
                version: "0.5.2",
                publishedOn: "2018-10-10",
              }
            }
          },
        ],

        pageInfo: a_hash_including(
          hasNextPage: true,
          hasPreviousPage: true
        )
      }
    })

    # pagination for dependents field

    factory do
      # Create two react releases to ensure requirements are set on pagination query
      given_package("react", "0.9.0", :npm).release
      given_package("react", "1.0.0", :npm).release

      # repo that uses exact version of react package created
      Repository.create!({
        github_repository_id: 9000,
        github_owner_id: 20,
        nwo: "Anthophila/react-test"
      })

      given_manifest(
        github_repo_id: 9000,
        manifest_type:  :package_lock_json,
        name: "toad",
        package_manager: :npm,
        filename:       "package-lock.json",
        path:           "/",
        revision:       1,
        dependencies:   [
          {
            package_name: "react",
            requirements: "= 1.0.0",
          },
          {
            package_name: "mocha",
            requirements: "= 4.0.0",
          },
        ]
      )

      Repository.create!({
        github_repository_id: 10000,
        github_owner_id: 20,
        nwo: "Anthophila/async-test"
      })

      given_manifest(
        github_repo_id: 10000,
        manifest_type:  :package_lock_json,
        name: "mario",
        package_manager: :npm,
        filename:       "package-lock.json",
        path:           "/",
        revision:       1,
        dependencies:   [
          {
            package_name: "react",
            requirements: "= 1.0.0",
          },
        ]
      )

      Repository.create!({
        github_repository_id: 11000,
        github_owner_id: 20,
        nwo: "Anthophila/react-like-test"
      })

      given_manifest(
        github_repo_id: 11000,
        manifest_type:  :package_lock_json,
        name: "luigi",
        package_manager: :npm,
        filename:       "package-lock.json",
        path:           "/",
        revision:       1,
        dependencies:   [
          {
            package_name: "react",
            requirements: "= 1.0.0",
          },
        ]
      )

      Repository.create!({
        github_repository_id: 12000,
        github_owner_id: 20,
        nwo: "Anthophila/react-earlier-version"
      })

      given_manifest(
        github_repo_id: 12000,
        manifest_type:  :package_lock_json,
        name: "toad",
        package_manager: :npm,
        filename:       "package-lock.json",
        path:           "/",
        revision:       1,
        dependencies:   [
          {
            package_name: "react",
            requirements: "= 0.9.0",
          },
        ]
      )

      Views::PackageReleaseDependentCount.rebuild_for(20, 30, 31)
      Views::PackageReleaseVulnerabilitiesCount.rebuild
    end

    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], name: "react", packageManager: NPM, version: "= 1.0.0") {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
              }
              dependentsCount
              vulnerabilitiesCount
              dependents(ownerIds: [20], first: 1) {
                exactCount
                lowerVersionCount
                upperVersionCount
                edges {
                  node {
                    packageName
                    repositoryId
                  }
                }

                pageInfo {
                  hasNextPage
                  hasPreviousPage
                  startCursor
                  endCursor
                }
              }
            }
          }
        }
      }
    QUERY

    expect(results).to match({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "react",
                packageManager: "NPM",
                version: "1.0.0",
              },
              dependentsCount: 3,
              vulnerabilitiesCount: 0,
              dependents: {
                exactCount: 3,
                lowerVersionCount: 1,
                upperVersionCount: 0,
                edges: [
                  {
                    node: {
                      packageName: "luigi",
                      repositoryId: 11000,
                    }
                  },
                ],
                pageInfo: a_hash_including(
                  hasNextPage: true,
                  hasPreviousPage: false,
                )
              }
            }
          }
        ]
      }
    })

    after = results[:repositoryPackageReleases][:edges][0][:node][:dependents][:pageInfo][:endCursor]

    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], name: "react", packageManager: NPM, version: "= 1.0.0") {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
              }
              dependentsCount
              vulnerabilitiesCount
              dependents(ownerIds: [20], first: 1, after: "#{after}") {
                exactCount
                lowerVersionCount
                upperVersionCount
                edges {
                  node {
                    packageName
                    repositoryId
                  }
                }

                pageInfo {
                  hasNextPage
                  hasPreviousPage
                  startCursor
                  endCursor
                }
              }
            }
          }
        }
      }
    QUERY

    expect(results).to match({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "react",
                packageManager: "NPM",
                version: "1.0.0",
              },
              dependentsCount: 3,
              vulnerabilitiesCount: 0,
              dependents: {
                exactCount: 3,
                lowerVersionCount: 1,
                upperVersionCount: 0,
                edges: [
                  {
                    node: {
                      packageName: "mario",
                      repositoryId: 10000,
                    }
                  },
                ],
                pageInfo: a_hash_including(
                  hasNextPage: true,
                  hasPreviousPage: true
                )
              }
            }
          }
        ]
      }
    })

    after = results[:repositoryPackageReleases][:edges][0][:node][:dependents][:pageInfo][:endCursor]

    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], name: "react", packageManager: NPM, version: "= 1.0.0") {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
              }
              dependentsCount
              vulnerabilitiesCount
              dependents(ownerIds: [20], first: 1, after: "#{after}") {
                exactCount
                lowerVersionCount
                upperVersionCount
                edges {
                  node {
                    packageName
                    repositoryId
                  }
                }

                pageInfo {
                  hasNextPage
                  hasPreviousPage
                  startCursor
                  endCursor
                }
              }
            }
          }
        }
      }
    QUERY

    expect(results).to match({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "react",
                packageManager: "NPM",
                version: "1.0.0",
              },
              dependentsCount: 3,
              vulnerabilitiesCount: 0,
              dependents: {
                exactCount: 3,
                lowerVersionCount: 1,
                upperVersionCount: 0,
                edges: [
                  {
                    node: {
                      packageName: "toad",
                      repositoryId: 9000,
                    }
                  },
                ],
                pageInfo: a_hash_including(
                  hasNextPage: false,
                  hasPreviousPage: true
                )
              }
            }
          }
        ]
      }
    })

    before = results[:repositoryPackageReleases][:edges][0][:node][:dependents][:pageInfo][:startCursor]

    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], name: "react", packageManager: NPM, version: "= 1.0.0") {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
              }
              dependentsCount
              vulnerabilitiesCount
              dependents(ownerIds: [20], first: 1, before: "#{before}") {
                exactCount
                lowerVersionCount
                upperVersionCount
                edges {
                  node {
                    packageName
                    repositoryId
                  }
                }

                pageInfo {
                  hasNextPage
                  hasPreviousPage
                  startCursor
                  endCursor
                }
              }
            }
          }
        }
      }
    QUERY

    expect(results).to match({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "react",
                packageManager: "NPM",
                version: "1.0.0",
              },
              dependentsCount: 3,
              vulnerabilitiesCount: 0,
              dependents: {
                exactCount: 3,
                lowerVersionCount: 1,
                upperVersionCount: 0,
                edges: [
                  {
                    node: {
                      packageName: "mario",
                      repositoryId: 10000,
                    }
                  },
                ],
                pageInfo: a_hash_including(
                  hasNextPage: true,
                  hasPreviousPage: true
                )
              }
            }
          }
        ]
      }
    })
  end

  it "paginates over results when sorting by most vulnerabilities count" do
    Views::PackageReleaseVulnerabilitiesCount.rebuild

    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], sortBy: MOST_VULNERABILITIES, first: 1) {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
              }
              vulnerabilitiesCount
            }
          }

          pageInfo {
            hasNextPage
            hasPreviousPage
            startCursor
            endCursor
          }
        }
      }
    QUERY

    expect(results).to match({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "multi_xml",
                packageManager: "RUBYGEMS",
                version: "0.5.2",
              },
              vulnerabilitiesCount: 2
            }
          },
        ],

        pageInfo: a_hash_including(
          hasNextPage: true,
          hasPreviousPage: false
        )
      }
    })

    after = results[:repositoryPackageReleases][:pageInfo][:endCursor]
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], sortBy: MOST_VULNERABILITIES, first: 1, after: "#{after}") {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
              }
              vulnerabilitiesCount
            }
          }

          pageInfo {
            hasNextPage
            hasPreviousPage
            startCursor
            endCursor
          }
        }
      }
    QUERY

    expect(results).to match({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "multi_xml",
                packageManager: "NPM",
                version: "0.5.2",
              },
              vulnerabilitiesCount: 0
            }
          },
        ],

        pageInfo: a_hash_including(
          hasNextPage: true,
          hasPreviousPage: true
        )
      }
    })

    before = results[:repositoryPackageReleases][:pageInfo][:startCursor]
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], sortBy: MOST_VULNERABILITIES, last: 1, before: "#{before}") {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
              }
              vulnerabilitiesCount
            }
          }

          pageInfo {
            hasNextPage
            hasPreviousPage
            startCursor
            endCursor
          }
        }
      }
    QUERY

    expect(results).to match({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "multi_xml",
                packageManager: "RUBYGEMS",
                version: "0.5.2",
              },
              vulnerabilitiesCount: 2
            }
          },
        ],

        pageInfo: a_hash_including(
          hasNextPage: true,
          hasPreviousPage: false
        )
      }
    })
  end

  it "scope results to package releases from an org, and lists its respective repository dependents in the org" do
    factory do
      PackageFactory.new("express", "1.3.0", :npm)
      .create!(published_at: "2019-01-03 10:33:33")

      # Create express releases with different versions
      given_package("express", "0.2.2", :npm).release
      given_package("express", "2.0.0", :npm).release

      # repo that uses exact version of express package created
      Repository.create!({
        github_repository_id: 9000,
        github_owner_id: 20,
        nwo: "Anthophila/bowser-test"
      })

      given_manifest(
        github_repo_id: 9000,
        manifest_type:  :package_lock_json,
        package_manager: :npm,
        filename:       "package-lock.json",
        path:           "/",
        revision:       1,
        dependencies:   [
          {
            package_name: "express",
            requirements: "= 1.3.0",
          },
          {
            package_name: "mocha",
            requirements: "= 4.0.0",
          },
        ]
      )

      # repo that uses exact version of express package created
      Repository.create!({
        github_repository_id: 10000,
        github_owner_id: 20,
        nwo: "Anthophila/mario-test"
      })

      given_manifest(
        github_repo_id: 10000,
        manifest_type:  :package_lock_json,
        package_manager: :npm,
        filename:       "package-lock.json",
        path:           "/",
        revision:       1,
        dependencies:   [
          {
            package_name: "express",
            requirements: "= 1.3.0",
          },
        ]
      )

      # repo that uses newer version of express package created
      Repository.create!({
        github_repository_id: 11000,
        github_owner_id: 20,
        nwo: "Anthophila/luigi-test"
      })

      given_manifest(
        github_repo_id: 11000,
        manifest_type:  :package_lock_json,
        name: "luigi",
        package_manager: :npm,
        filename:       "package-lock.json",
        path:           "/",
        revision:       1,
        dependencies:   [
          {
            package_name: "express",
            requirements: "= 2.0.0",
          },
        ]
      )

      # repo that uses older version of express package created
      Repository.create!({
        github_repository_id: 12000,
        github_owner_id: 20,
        nwo: "Anthophila/toad-test"
      })

      given_manifest(
        github_repo_id: 12000,
        manifest_type:  :package_lock_json,
        package_manager: :npm,
        filename:       "package-lock.json",
        path:           "/",
        revision:       1,
        dependencies:   [
          {
            package_name: "express",
            requirements: "= 0.2.2",
          },
        ]
      )

      Views::PackageReleaseDependentCount.rebuild_for(20, 30, 31)
      Views::PackageReleaseVulnerabilitiesCount.rebuild
    end

    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], name: "express", packageManager: NPM, version: "= 1.3.0") {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
              }
              dependentsCount
              vulnerabilitiesCount
              dependents(ownerIds: [20]) {
                exactCount
                lowerVersionCount
                upperVersionCount
                edges {
                  node {
                    repositoryId
                  }
                }
              }
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "express",
                packageManager: "NPM",
                version: "1.3.0",
              },
              dependentsCount: 2,
              vulnerabilitiesCount: 0,
              dependents: {
                exactCount: 2,
                lowerVersionCount: 1,
                upperVersionCount: 1,
                edges: [
                  {
                    node: {
                      repositoryId: 10000,
                    }
                  },
                  {
                    node: {
                      repositoryId: 9000,
                    }
                  }
                ]
              }
            }
          }
        ]
      }
    })

    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], name: "express", packageManager: NPM, version: "= 0.2.2") {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
              }
              dependentsCount
              vulnerabilitiesCount
              dependents(ownerIds: [20]) {
                exactCount
                lowerVersionCount
                upperVersionCount
                edges {
                  node {
                    repositoryId
                  }
                }
              }
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "express",
                packageManager: "NPM",
                version: "0.2.2",
              },
              dependentsCount: 1,
              vulnerabilitiesCount: 0,
              dependents: {
                exactCount: 1,
                lowerVersionCount: 0,
                upperVersionCount: 3,
                edges: [
                  {
                    node: {
                      repositoryId: 12000,
                    }
                  },
                ]
              }
            }
          }
        ]
      }
    })

    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], name: "express", packageManager: NPM, version: "= 2.0.0") {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
              }
              dependentsCount
              vulnerabilitiesCount
              dependents(ownerIds: [20]) {
                exactCount
                lowerVersionCount
                upperVersionCount
                edges {
                  node {
                    packageName
                    repositoryId
                  }
                }
              }
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "express",
                packageManager: "NPM",
                version: "2.0.0",
              },
              dependentsCount: 1,
              vulnerabilitiesCount: 0,
              dependents: {
                exactCount: 1,
                lowerVersionCount: 3,
                upperVersionCount: 0,
                edges: [
                  {
                    node: {
                      packageName: "luigi",
                      repositoryId: 11000,
                    }
                  },
                ]
              }
            }
          }
        ]
      }
    })

    # filter dependents by dependent name
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], name: "express", packageManager: NPM, version: "= 2.0.0", dependentName: "luigi-test") {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
              }
              dependentsCount
              vulnerabilitiesCount
              dependents(ownerIds: [20], dependentName: "luigi-test") {
                exactCount
                lowerVersionCount
                upperVersionCount
                edges {
                  node {
                    packageName
                    repositoryId
                  }
                }
              }
            }
          }
        }
      }
  QUERY

    expect(results).to eq({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "express",
                packageManager: "NPM",
                version: "2.0.0",
              },
              dependentsCount: 1,
              vulnerabilitiesCount: 0,
              dependents: {
                exactCount: 1,
                lowerVersionCount: 3,
                upperVersionCount: 0,
                edges: [
                  {
                    node: {
                      packageName: "luigi",
                      repositoryId: 11000,
                    }
                  },
                ]
              }
            }
          }
        ]
      }
    })
  end

  it "returns rollup counts for all vulnerabilities by severity" do
    # Does not affect us
    factory.given_vulnerable_version_range({
      github_id: 169,
      package_name: "multi_xml",
      package_manager: :rubygems,
      version_range: "> 1.0, < 3.0",
      severity: "critical"
    })

    # Affects us
    factory.given_vulnerable_version_range({
      github_id: 170,
      package_name: "httparty",
      package_manager: :rubygems,
      version_range: "> 1.0, < 3.0",
      severity: "low"
    })

    # Affects us
    factory.given_vulnerable_version_range({
      github_id: 171,
      package_name: "httparty",
      package_manager: :rubygems,
      version_range: "> 1.0, < 3.0",
      severity: "low"
    })

    # Affects us
    factory.given_vulnerable_version_range({
      github_id: 172,
      package_name: "httparty",
      package_manager: :rubygems,
      version_range: "> 1.1, < 3.1",
      severity: "low"
    })

    Repository.create!({
      github_repository_id: 5002,
      github_owner_id: 30,
      nwo: "ManifestParser/octokit2"
    })

    factory.given_manifest(
      github_repo_id: 5002,
      manifest_type:  :gemfile_lock,
      package_manager: :rubygems,
      filename:       "Gemfile.lock",
      path:           "/",
      revision:       1,
      dependencies:   [
        {
          package_name: "httparty",
          requirements: "= 2.0.1",
        },
      ]
    )

    Views::PackageReleaseDependentCount.rebuild_for(20, 30)
    Views::PackageReleaseVulnerabilitiesCount.rebuild

    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20, 30]) {
          vulnerabilitySeverities {
            severity
            totalCount
            dependentsCount
          }
        }
      }
    QUERY

    expect(results).to eq({
      repositoryPackageReleases: {
        vulnerabilitySeverities: [
          {
            severity: "low",
            totalCount: 6,
            dependentsCount: 2
          },
          {
          severity: "moderate",
          totalCount: 1,
          dependentsCount: 1
          },
          {
            severity: "high",
            totalCount: 1,
            dependentsCount: 1
          }
        ]
      }
    })
  end

  it "scopes results to package releases from an org, and filters them based on license" do
    factory do
      PackageFactory.new("express", "1.3.0", :npm)
      .create!(published_at: "2019-01-03 10:33:33", license: "MIT")

      PackageFactory.new("react-dom", "1.9.2", :npm)
      .create!(published_at: "2019-01-12 10:33:33", license: "MIT")

      PackageFactory.new("vue", "3.3.1", :npm)
      .create!(published_at: "2019-01-10 10:33:33", license: "MPL-2.0 or MIT")

      PackageFactory.new("gulp", "4.3.0", :npm)
      .create!(published_at: "2019-01-03 10:33:33", license: "Apache-2.0")

      Repository.create!({
        github_repository_id: 15000,
        github_owner_id: 20,
        nwo: "Anthophila/bowser-test"
      })

      given_manifest(
        github_repo_id: 15000,
        manifest_type:  :package_lock_json,
        package_manager: :npm,
        filename:       "package-lock.json",
        path:           "/",
        revision:       1,
        dependencies:   [
          {
            package_name: "express",
            requirements: "= 1.3.0",
          },
          {
            package_name: "gulp",
            requirements: "= 4.3.0",
          },
        ]
      )

      Repository.create!({
        github_repository_id: 20000,
        github_owner_id: 20,
        nwo: "Anthophila/mario-test"
      })

      given_manifest(
        github_repo_id: 20000,
        manifest_type:  :package_lock_json,
        package_manager: :npm,
        filename:       "package-lock.json",
        path:           "/",
        revision:       1,
        dependencies:   [
          {
            package_name: "vue",
            requirements: "= 3.3.1",
          },
          {
            package_name: "react-dom",
            requirements: "= 1.9.2",
          },
        ]
      )
      Views::PackageReleaseDependentCount.rebuild_for(20, 30, 31)
      Views::PackageReleaseVulnerabilitiesCount.rebuild
    end

    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], license: MIT) {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
                license
              }
              dependentsCount
              vulnerabilitiesCount
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "express",
                packageManager: "NPM",
                version: "1.3.0",
                license: "MIT"
              },
              dependentsCount: 1,
              vulnerabilitiesCount: 0,
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "react-dom",
                packageManager: "NPM",
                version: "1.9.2",
                license: "MIT"
              },
              dependentsCount: 1,
              vulnerabilitiesCount: 0,
            }
          },
        ]
      }
    })

    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], license: APACHE_2_0) {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
                license
              }
              dependentsCount
              vulnerabilitiesCount
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "gulp",
                packageManager: "NPM",
                version: "4.3.0",
                license: "Apache-2.0"
              },
              dependentsCount: 1,
              vulnerabilitiesCount: 0,
            }
          },
        ]
      }
    })

    # We should be able to filter by multiple licenses
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], license: [MIT, APACHE_2_0]) {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
                license
              }
              dependentsCount
              vulnerabilitiesCount
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "express",
                packageManager: "NPM",
                version: "1.3.0",
                license: "MIT"
              },
              dependentsCount: 1,
              vulnerabilitiesCount: 0,
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "react-dom",
                packageManager: "NPM",
                version: "1.9.2",
                license: "MIT"
              },
              dependentsCount: 1,
              vulnerabilitiesCount: 0,
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "gulp",
                packageManager: "NPM",
                version: "4.3.0",
                license: "Apache-2.0"
              },
              dependentsCount: 1,
              vulnerabilitiesCount: 0,
            }
          },
        ]
      }
    })

    # Since we are doing exact license matching, this should return nothing
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20], license: MPL_2_0) {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                version
                license
              }
              dependentsCount
              vulnerabilitiesCount
            }
          }
        }
      }
    QUERY

    expect(results[:repositoryPackageReleases][:edges]).to be_empty
  end

  it "returns items sorted when vunerability is filtered on" do
    # Does not affect us
    factory.given_vulnerable_version_range({
      github_id: 169,
      package_name: "multi_xml",
      package_manager: :rubygems,
      version_range: "> 0.0, < 1.0",
      severity: "critical"
    })

    # Affects us
    factory.given_vulnerable_version_range({
      github_id: 170,
      package_name: "httparty",
      package_manager: :rubygems,
      version_range: "> 1.0, < 3.0",
      severity: "critical"
    })

    # Affects us
    factory.given_vulnerable_version_range({
      github_id: 171,
      package_name: "httparty",
      package_manager: :rubygems,
      version_range: "> 1.0, < 3.0",
      severity: "critical"
    })

    # Affects us
    factory.given_vulnerable_version_range({
      github_id: 172,
      package_name: "httparty",
      package_manager: :rubygems,
      version_range: "> 1.1, < 3.1",
      severity: "critical"
    })

    Repository.create!({
      github_repository_id: 5002,
      github_owner_id: 30,
      nwo: "ManifestParser/octokit2"
    })

    factory.given_manifest(
      github_repo_id: 5002,
      manifest_type:  :gemfile_lock,
      package_manager: :rubygems,
      filename:       "Gemfile.lock",
      path:           "/",
      revision:       1,
      dependencies:   [
        {
          package_name: "httparty",
          requirements: "= 2.0.1",
        },
        {
          package_name: "multi_xml",
          requirements: "= 0.5.3",
        },
      ]
    )

    Views::PackageReleaseDependentCount.rebuild_for(20, 30)
    Views::PackageReleaseVulnerabilitiesCount.rebuild

    # multi xml is newest, so it should come first in this query
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(first: 25, vulnerable: true, ownerIds: [20], severity: CRITICAL, sortBy: NEWEST) {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                publishedOn
                version
              }
              dependentsCount
              vulnerabilitiesCount
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "multi_xml",
                packageManager: "RUBYGEMS",
                version: "0.5.2",
                publishedOn: "2018-10-10",
              },
              dependentsCount: 1,
              vulnerabilitiesCount: 3,
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "httparty",
                packageManager: "RUBYGEMS",
                version: "2.0.1",
                publishedOn: "2018-09-05",
              },
              dependentsCount: 1,
              vulnerabilitiesCount: 3,
            }
          },
        ]
      }
    })

    # httparty is oldest, so it should come first in this query
    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(first: 25, vulnerable: true, ownerIds: [20], severity: CRITICAL, sortBy: OLDEST ) {
          edges {
            node {
              packageRelease {
                packageName
                packageManager
                publishedOn
                version
              }
              dependentsCount
              vulnerabilitiesCount
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      repositoryPackageReleases: {
        edges: [
          {
            node: {
              packageRelease: {
                packageName: "httparty",
                packageManager: "RUBYGEMS",
                version: "2.0.1",
                publishedOn: "2018-09-05",
              },
              dependentsCount: 1,
              vulnerabilitiesCount: 3,
            }
          },
          {
            node: {
              packageRelease: {
                packageName: "multi_xml",
                packageManager: "RUBYGEMS",
                version: "0.5.2",
                publishedOn: "2018-10-10",
              },
              dependentsCount: 1,
              vulnerabilitiesCount: 3,
            }
          },
        ]
      }
    })
  end

  it "returns rollup counts for all licenses by license type" do
    factory do
      PackageFactory.new("express", "1.3.0", :npm)
      .create!(published_at: "2019-01-03 10:33:33", license: "MIT")

      PackageFactory.new("react-dom", "1.9.2", :npm)
      .create!(published_at: "2019-01-12 10:33:33", license: "MIT")

      PackageFactory.new("axios", "2.0.0", :npm)
      .create!(published_at: "2017-01-03 10:33:33", license: "MIT")

      PackageFactory.new("vue", "3.3.1", :npm)
      .create!(published_at: "2019-01-10 10:33:33", license: "MPL-2.0 or MIT")

      PackageFactory.new("vue-test", "3.3.2", :npm)
      .create!(published_at: "2019-01-10 10:33:33", license: "MPL-2.0 or Apache-2.0")

      PackageFactory.new("gulp", "4.3.0", :npm)
      .create!(published_at: "2019-01-03 10:33:33", license: "Apache-2.0")

      PackageFactory.new("babel-loader", "2.3.0", :npm)
      .create!(published_at: "2018-01-03 10:33:33", license: "Apache-2.0")

      PackageFactory.new("babel-core", "1.3.0", :npm)
      .create!(published_at: "2018-01-01 10:33:33", license: "GPL-3.0+")

      Repository.create!({
        github_repository_id: 15000,
        github_owner_id: 20,
        nwo: "Anthophila/bowser-test"
      })

      given_manifest(
        github_repo_id: 15000,
        manifest_type:  :package_lock_json,
        package_manager: :npm,
        filename:       "package-lock.json",
        path:           "/",
        revision:       1,
        dependencies:   [
          {
            package_name: "express",
            requirements: "= 1.3.0",
          },
          {
            package_name: "gulp",
            requirements: "= 4.3.0",
          },
          {
            package_name: "axios",
            requirements: "= 2.0.0",
          },
        ]
      )

      Repository.create!({
        github_repository_id: 20000,
        github_owner_id: 20,
        nwo: "Anthophila/mario-test"
      })

      given_manifest(
        github_repo_id: 20000,
        manifest_type:  :package_lock_json,
        package_manager: :npm,
        filename:       "package-lock.json",
        path:           "/",
        revision:       1,
        dependencies:   [
          {
            package_name: "vue",
            requirements: "= 3.3.1",
          },
          {
            package_name: "vue-test",
            requirements: "= 3.3.2",
          },
          {
            package_name: "react-dom",
            requirements: "= 1.9.2",
          },
          {
            package_name: "babel-loader",
            requirements: "= 2.3.0",
          },
          {
            package_name: "babel-core",
            requirements: "= 1.3.0",
          },
        ]
      )
      Views::PackageReleaseDependentCount.rebuild_for(20, 30, 31)
      Views::PackageReleaseVulnerabilitiesCount.rebuild
    end

    query <<-QUERY.strip_heredoc
      {
        repositoryPackageReleases(ownerIds: [20]) {
          licenses {
            license
            totalCount
          }
        }
      }
    QUERY

    expect(results).to match({
      repositoryPackageReleases: {
        licenses: match_array([
          {
            license: "Apache-2.0",
            totalCount: 2
          },
          {
            license: "GPL-3.0+",
            totalCount: 1
          },
          {
            license: "MIT",
            totalCount: 3
          },
          {
            license: "Other",
            totalCount: 2
          }
        ])
      }
    })
  end
end

describe "repository_package_releases" do
  it_behaves_like "querying for package releases in an organization scope", false
end

describe "repository_package_releases (normalized)" do
  it_behaves_like "querying for package releases in an organization scope", true
end
