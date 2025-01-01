require "rails_helper"
require "dependency_snapshots_api/dependencies_client"
require "dependency-graph-platform/graphql_resolver_client"
require_relative "../lib/monolith/features_helpers.rb"

describe "querying for manifests" do
  include Monolith::FeaturesHelpers

  before do
    # Disable the DGP gateway by default
    allow_any_instance_of(Queries::ManifestsQuery).to receive(:dgp_available).and_return(false)
  end

  let(:dependencies_client_binary) { DependencyGraphAPI::DependencySnapshotsAPI::DependenciesClient.new(use_json: false) }
  let(:dependencies_client_json) { DependencyGraphAPI::DependencySnapshotsAPI::DependenciesClient.new(use_json: true) }
  let(:dgp_graphql_client_json) { DependencyGraphAPI::DependencyGraphPlatform::GraphQLResolverClient.new(use_json: true) }

  before do
    # Replace the snapshots and DGP clients with ones that returns JSON, so our cassettes will be easier to work with
    allow_any_instance_of(Queries::ManifestsQuery).to receive(:dependencies_client).and_return(dependencies_client_json)
    allow_any_instance_of(Queries::ManifestsQuery).to receive(:dgp_graphql_client).and_return(dgp_graphql_client_json)
    allow(DependencyGraph::ObjectModel::DGPGraphqlManifest).to receive(:dgp_graphql_client).and_return(dgp_graphql_client_json)
  end

  # This should be called in tests that use existing cassettes that were not recorded using the JSON wire format.
  def stub_binary_dependencies_client
    allow_any_instance_of(Queries::ManifestsQuery).to receive(:dependencies_client).and_return(dependencies_client_binary)
  end

  def count_worker_threads
    Thread.list.count do |thread|
      thread.instance_variable_defined?(:@name) && thread.instance_variable_get(:@name)&.include?("worker")
    end
  end

  it "includes manifests", vcr: { cassette_name: "manifest-queries-spec-no-dependencies" } do
    factory.given_manifest(
      github_repo_id: 100,
      manifest_type:  :gemfile,
      filename:       "Gemfile",
      path:           "/"
    )
    factory.given_manifest(
      github_repo_id: 200
    )

    query <<-QUERY.strip_heredoc
      {
        manifests(repositoryIds: [100]) {
          edges {
            node {
              repositoryId
              manifestType
              filename
              path
              isVendored
            }
          }
        }
      }
    QUERY

    expect(results[:manifests][:edges]).to eq([
      {
        node: {
          repositoryId: 100,
          manifestType: "gemfile",
          filename:     "Gemfile",
          path:         "/",
          isVendored:   false,
        }
      }
    ])
  end

  it "includes the raw manifest ids", vcr: { cassette_name: "manifest-queries-spec-no-dependencies" } do
    factory.given_manifest(
      github_repo_id: 100,
      filename:       "Gemfile",
    )

    factory.given_manifest(
      github_repo_id: 100,
      filename:       "package.json",
    )

    query <<-QUERY.strip_heredoc
      {
        manifests(repositoryIds: [100]) {
          edges {
            node {
              id
            }
          }
        }
      }
    QUERY

    manifest_ids = results[:manifests][:edges].pluck(:node).pluck(:id)
    expect(manifest_ids.size).to eq(2)
    expect(manifest_ids).to eq(Manifest.with_github_repository_id(100).pluck(:id).map(&:to_s))
  end

  it "excludes manifests with types in preview mode", vcr: { cassette_name: "manifest-queries-spec-no-dependencies" } do
    factory.given_manifest(
      github_repo_id: 100,
      manifest_type:  :gemfile,
      filename:       "Gemfile",
      path:           "/"
    )
    factory.given_manifest(
      github_repo_id: 200
    )

    stub_const("DependencyGraph::MANIFEST_TYPE_PREVIEW", [
      Types::Manifest[:gemfile]
    ])

    query <<~QUERY
      {
        manifests(repositoryIds: [100]) {
          edges {
            node {
              repositoryId
              manifestType
              filename
              path
              isVendored
            }
          }
        }
      }
    QUERY

    expect(results[:manifests][:edges]).to eq([])

    query <<~QUERY
      {
        manifests(repositoryIds: [100], preview: true) {
          edges {
            node {
              repositoryId
              manifestType
              filename
              path
              isVendored
            }
          }
        }
      }
    QUERY

    expect(results[:manifests][:edges]).to eq([
      {
        node: {
          repositoryId: 100,
          manifestType: "gemfile",
          filename:     "Gemfile",
          path:         "/",
          isVendored:   false,
        }
      }
    ])
  end

  it "can scope to manifest ids", vcr: { cassette_name: "manifest-queries-spec-no-dependencies" } do
    gemfile = factory.given_manifest(
      github_repo_id: 100,
      manifest_type:  :gemfile,
      filename:       "Gemfile",
      path:           "/"
    )
    factory.given_manifest(
      github_repo_id: 100,
      manifest_type:  :gemfile_lock,
      filename:       "Gemfile.lock",
      path:           "/"
    )
    query <<-QUERY.strip_heredoc
      {
        manifests(repositoryIds: [100], ids: [#{gemfile.manifest.id}]) {
          edges {
            node {
              id
              repositoryId
              manifestType
              filename
              path
              isVendored
            }
          }
        }
      }
    QUERY

    expect(results[:manifests][:edges]).to eq([
      {
        node: {
          id:           "#{gemfile.manifest.id}",
          repositoryId: 100,
          manifestType: "gemfile",
          filename:     "Gemfile",
          path:         "/",
          isVendored:   false,
        }
      }
    ])
  end

  it "can scope to package manager", vcr: { cassette_name: "manifest-queries-spec-no-dependencies" } do
    factory.given_manifest(
      github_repo_id: 100,
      manifest_type:  :package_lock_json,
      filename:       "package-lock.json",
      path:           "/"
    )
    factory.given_manifest(
      github_repo_id: 100,
      manifest_type:  :gemfile,
      filename:       "Gemfile",
      path:           "/"
    )

    requested_package_manager = "NPM"

    query <<-QUERY.strip_heredoc
      {
        manifests(repositoryIds: [100], packageManager: #{requested_package_manager}) {
          edges {
            node {
              repositoryId
              manifestType
              filename
              path
              isVendored
            }
          }
        }
      }
    QUERY

    expect(results[:manifests][:edges]).to eq([
      {
        node: {
          repositoryId: 100,
          manifestType: "package_lock_json",
          filename:     "package-lock.json",
          path:         "/",
          isVendored:   false,
        }
      }
    ])
  end

  it "includes manifest dependencies", vcr: { cassette_name: "manifest-queries-spec-no-dependencies" } do
    factory.given_package("rails", "5.0.1").update_repository_mapping(github_repository_id: 42)

    factory.given_manifest(
      github_repo_id: 100,
      manifest_type:  :gemfile,
      filename:       "Gemfile",
      path:           "/",
      dependencies:   [
        {
          package_name: "rails",
          requirements: "> 5.0.0",
          scope:        :runtime,
        }
      ]
    )

    query <<-QUERY.strip_heredoc
      {
        manifests(repositoryIds: [100]) {
          edges {
            node {
              manifestType
              repositoryId
              dependencies {
                edges {
                  node {
                    packageName
                    requirements
                    scope
                    repositoryId
                  }
                }
              }
            }
          }
        }
      }
    QUERY

    expect(results[:manifests][:edges]).to eq([
      {
        node: {
          manifestType: "gemfile",
          repositoryId: 100,
          dependencies: {
            edges: [
              {
                node: {
                  packageName:  "rails",
                  requirements: "> 5.0.0",
                  scope:        "runtime",
                  repositoryId: 42
                }
              }
            ]
          }
        }
      }
    ])
  end

  it "should not break when relationship is requested", vcr: { cassette_name: "manifest-queries-spec-no-dependencies" } do
    factory.given_package("rails", "5.0.1").update_repository_mapping(github_repository_id: 42)

    factory.given_manifest(
      github_repo_id: 100,
      manifest_type:  :gemfile,
      filename:       "Gemfile",
      path:           "/",
      dependencies:   [
        {
          package_name: "rails",
          requirements: "> 5.0.0",
          scope:        :runtime,
        }
      ]
    )

    query <<-QUERY.strip_heredoc
      {
        manifests(repositoryIds: [100]) {
          edges {
            node {
              manifestType
              repositoryId
              dependencies {
                edges {
                  node {
                    packageName
                    requirements
                    scope
                    repositoryId
                    relationship
                  }
                }
              }
            }
          }
        }
      }
    QUERY

    expect(results[:manifests][:edges]).to eq([
      {
        node: {
          manifestType: "gemfile",
          repositoryId: 100,
          dependencies: {
            edges: [
              {
                node: {
                  packageName:  "rails",
                  requirements: "> 5.0.0",
                  scope:        "runtime",
                  repositoryId: 42,
                  relationship: nil
                }
              }
            ]
          }
        }
      }
    ])
  end

  context "testing packageUrl" do
    it "should include packageUrl in response when requested", vcr: { cassette_name: "manifest-queries-spec-no-dependencies" } do
      factory.given_package("rails", "5.0.1").update_repository_mapping(github_repository_id: 42)

      factory.given_manifest(
        github_repo_id: 100,
        manifest_type:  :gemfile,
        filename:       "Gemfile",
        path:           "/",
        dependencies:   [
          {
            package_name: "rails",
            requirements: "> 5.0.0",
            scope:        :runtime,
          },
          {
            package_name: "redis",
            requirements: "= 5.4.0",
            scope:        :runtime,
          },
          {
            package_name: "i18n",
            requirements: "> 1.0.0, < 1.13",
            scope:        :runtime,
          }
        ]
      )

      factory.given_manifest(
        github_repo_id: 100,
        manifest_type:  :go_mod,
        filename:       "go.mod",
        path:           "/",
        dependencies:   [
          {
            package_name: "github.com/golang/protobuf",
            requirements: "= 1.5.3",
            scope:        :runtime,
          },
        ]
      )

      query <<-QUERY.strip_heredoc
        {
          manifests(repositoryIds: [100]) {
            edges {
              node {
                manifestType
                repositoryId
                dependencies {
                  edges {
                    node {
                      packageName
                      packageManager
                      packageUrl
                    }
                  }
                }
              }
            }
          }
        }
      QUERY

      expect(results[:manifests][:edges]).to eq([
        {
          node: {
            manifestType: "gemfile",
            repositoryId: 100,
            dependencies: {
              edges: [
                {
                  node: {
                    packageManager: "RUBYGEMS",
                    packageName:    "i18n",
                    packageUrl:     "pkg:gem/i18n",
                  }
                },
                {
                  node: {
                    packageManager: "RUBYGEMS",
                    packageName:    "rails",
                    packageUrl:     "pkg:gem/rails",
                  }
                },
                {
                  node: {
                    packageManager: "RUBYGEMS",
                    packageName:    "redis",
                    packageUrl:     "pkg:gem/redis@5.4.0",
                  }
                }
              ]
            }
          }
        },
        {
          node: {
            manifestType: "go_mod",
            repositoryId: 100,
            dependencies: {
              edges: [
                {
                  node: {
                    packageManager: "GO",
                    packageName:    "github.com/golang/protobuf",
                    packageUrl:     "pkg:golang/github.com/golang/protobuf@1.5.3",
                  }
                },
              ]
            }
          }
        }
      ])
    end
  end

  # https://github.com/github/dependency-graph/issues/1755
  it "prevents low-quality Maven repository mappings from being shown", vcr: { cassette_name: "manifest-queries-spec-no-dependencies" } do
    factory.given_package("log4j", "6.6.6", ::Types::PackageManager::MAVEN)
      .update_repository_mapping(github_repository_id: 42,
                                 repository_id_certainty: PackageToRepoMapping::Certainty::POSITIVE_MATCH)
    factory.given_package("slf4j", "1.1.1", ::Types::PackageManager::MAVEN)
      .update_repository_mapping(github_repository_id: 53,
                                 repository_id_certainty: PackageToRepoMapping::Certainty::MAVEN_INFERRED_NAMESPACE_MULTIPLE_MATCHES)

    factory.given_manifest(
      github_repo_id: 100,
      manifest_type:  :pom_xml,
      filename:       "pom.xml",
      path:           "/",
      package_manager: ::Types::PackageManager::MAVEN,
      dependencies:   [
        {
          package_name: "log4j",
          package_manager: ::Types::PackageManager::MAVEN,
          requirements: "= 6.6.6",
          scope:        :runtime,
        },
        {
          package_name: "slf4j",
          package_manager: ::Types::PackageManager::MAVEN,
          requirements: "= 1.1.1",
          scope:        :runtime,
        }
      ]
    )

    query <<-QUERY.strip_heredoc
      {
        manifests(repositoryIds: [100]) {
          nodes {
            manifestType
            repositoryId
            dependencies {
              nodes {
                packageName
                repositoryId
              }
            }
          }
        }
      }
    QUERY

    manifest = results[:manifests][:nodes].first
    expect(manifest[:manifestType]).to eq("pom_xml")
    expect(manifest[:repositoryId]).to eq(100)

    dependencies = manifest[:dependencies][:nodes]
    expect(dependencies).to eq([
      {
        packageName: "log4j",
        repositoryId: 42
      },
      {
        packageName: "slf4j",
        repositoryId: nil
      }
    ])
  end

  it "includes can sort by preferred manifest dependencies", vcr: { cassette_name: "manifest-queries-spec-no-dependencies" } do
    factory.given_manifest(
      github_repo_id: 100,
      manifest_type:  :gemfile,
      filename:       "Gemfile",
      path:           "/",
      dependencies:   [
        {
          package_name: "aws",
          requirements: "> 5.0.0",
          scope:        :runtime,
        },
        {
          package_name: "rails",
          requirements: "> 5.0.0",
          scope:        :runtime,
        },
        {
          package_name: "rake",
          requirements: "> 5.0.0",
          scope:        :runtime,
        }
      ]
    )

    query <<-QUERY.strip_heredoc
      {
        manifests(repositoryIds: [100]) {
          edges {
            node {
              dependencies(prefer: ["rake"]) {
                edges {
                  node {
                    packageName
                  }
                }
              }
            }
          }
        }
      }
    QUERY

    dependency_edges = results[:manifests][:edges][0][:node][:dependencies][:edges]
    expect(dependency_edges).to eq([
      {
        node: {
          packageName: "rake",
        }
      },
      {
        node: {
          packageName: "aws",
        }
      },
      {
        node: {
          packageName: "rails",
        }
      },
    ])
  end

  it "scopes to just manifests with dependencies", vcr: { cassette_name: "manifest-queries-spec-no-dependencies" } do
    factory do
      given_manifest(github_repo_id: 100, manifest_type: :gemfile)
        .add_dependency("rake", "> 0.0.0")

      given_manifest(github_repo_id: 200, manifest_type: :gemfile)
    end

    query <<-QUERY.strip_heredoc
      {
        manifests(repositoryIds: [100, 200], withDependencies: true) {
          edges {
            node {
              repositoryId
              manifestType
            }
          }
        }
      }
    QUERY

    expect(results[:manifests][:edges]).to eq([
      {
        node: {
          repositoryId: 100,
          manifestType: "gemfile",
        }
      }
    ])
  end

  it "doesn't N+1 on dependency details", vcr: { cassette_name: "manifest-queries-spec-no-dependencies" } do
    package_1 = factory.given_package("package-1", "1.0.0").package
    package_2 = factory.given_package("package-2", "1.0.0").package
    package_3 = factory.given_package("package-3", "1.0.0").package
    package_4 = factory.given_package("package-4", "1.0.0").package

    factory.given_manifest(
      github_repo_id: 100,
      manifest_type:  :gemfile,
      filename:       "Gemfile",
      path:           "/",
      dependencies:   [
        {
          package_name: "package-1",
          requirements: "= 1.0.0",
        },
        {
          package_name: "package-2",
          requirements: "= 1.0.0",
        },
        {
          package_name: "package-3",
          requirements: "= 1.0.0",
        },
        {
          package_name: "package-4",
          requirements: "= 1.0.0",
        },
      ]
    )

    query = <<-QUERY.strip_heredoc
      {
        manifests(repositoryIds: [100]) {
          edges {
            node {
              dependencies {
                edges {
                  node {
                    packageId
                    packageName
                    packageManager
                    requirements
                    hasDependencies
                    license
                  }
                }
              }
            }
          }
        }
      }
    QUERY

    # One query for repository (used for feature checking)
    # One query for manifest
    # One query for dependencies
    expect { query(query) }.to make_database_queries(count: 2)

    expect(results[:manifests][:edges]).to eq([
      {
        node: {
          dependencies: {
            edges: [
              {
                node: {
                  hasDependencies: false,
                  license: nil,
                  packageId: graphql_id("Package", package_1),
                  packageManager: "RUBYGEMS",
                  packageName: "package-1",
                  requirements: "= 1.0.0",
                }
              },
              {
                node: {
                  hasDependencies: false,
                  license: nil,
                  packageId: graphql_id("Package", package_2),
                  packageManager: "RUBYGEMS",
                  packageName: "package-2",
                  requirements: "= 1.0.0",
                }
              },
              {
                node: {
                  hasDependencies: false,
                  license: nil,
                  packageId: graphql_id("Package", package_3),
                  packageManager: "RUBYGEMS",
                  packageName: "package-3",
                  requirements: "= 1.0.0",
                }
              },
              {
                node: {
                  hasDependencies: false,
                  license: nil,
                  packageId: graphql_id("Package", package_4),
                  packageManager: "RUBYGEMS",
                  packageName: "package-4",
                  requirements: "= 1.0.0",
                }
              }
            ]
          }
        }
      }
    ])
  end

  it "doesn't N+1 on packageId", vcr: { cassette_name: "manifest-queries-spec-no-dependencies" } do
    package_1 = factory.given_package("package-1", "1.0.0").package
    package_2 = factory.given_package("package-2", "1.0.0").package
    package_3 = factory.given_package("package-3", "1.0.0").package
    package_4 = factory.given_package("package-4", "1.0.0").package

    factory.given_manifest(
      github_repo_id: 100,
      manifest_type:  :gemfile,
      filename:       "Gemfile",
      path:           "/",
      dependencies:   [
        {
          package_name: "package-1",
          requirements: "= 1.0.0",
        },
        {
          package_name: "package-2",
          requirements: "= 1.0.0",
        },
        {
          package_name: "package-3",
          requirements: "= 1.0.0",
        },
        {
          package_name: "package-4",
          requirements: "= 1.0.0",
        },
      ]
    )

    query = <<-QUERY.strip_heredoc
      {
        manifests(repositoryIds: [100]) {
          edges {
            node {
              dependencies {
                edges {
                  node {
                    packageId
                  }
                }
              }
            }
          }
        }
      }
    QUERY

    # One query for repository (used for feature checking)
    # One query for manifest
    # One query for dependencies
    expect { query(query) }.to make_database_queries(count: 2)

    expect(results[:manifests][:edges]).to eq([
      {
        node: {
          dependencies: {
            edges: [
              {
                node: {
                  packageId: graphql_id("Package", package_1),
                }
              },
              {
                node: {
                  packageId: graphql_id("Package", package_2),
                }
              },
              {
                node: {
                  packageId: graphql_id("Package", package_3),
                }
              },
              {
                node: {
                  packageId: graphql_id("Package", package_4),
                }
              }
            ]
          }
        }
      }
    ])
  end

  it "doesn't N+1 on license", vcr: { cassette_name: "manifest-queries-spec-no-dependencies" } do
    package_1 = Package.create!(
      name: "package-1",
      package_manager: Types::PackageManager[:rubygems]
    )
    package_1_release = PackageRelease.create!(
      package_id: package_1.id,
      package_manager: package_1.package_manager,
      package_name: package_1.name,
      name: "1.0.0",
      license: "MIT"
    )
    package_2 = Package.create!(
      name: "package-2",
      package_manager: Types::PackageManager[:rubygems]
    )
    package_2_release = PackageRelease.create!(
      package_id: package_2.id,
      package_manager: package_2.package_manager,
      package_name: package_2.name,
      name: "1.0.0",
      license: "bsd-2-clause"
    )

    factory.given_manifest(
      github_repo_id: 100,
      manifest_type:  :gemfile,
      filename:       "Gemfile",
      path:           "/",
      dependencies:   [
        {
          package_name: "package-1",
          requirements: "= 1.0.0",
        },
        {
          package_name: "package-2",
          requirements: "= 1.0.0",
        },
      ]
    )

    query = <<-QUERY.strip_heredoc
      {
        manifests(repositoryIds: [100]) {
          edges {
            node {
              dependencies {
                edges {
                  node {
                    license
                  }
                }
              }
            }
          }
        }
      }
    QUERY

    # One query for repository (used for feature checking)
    # One query for manifest
    # One query for dependencies
    expect { query(query) }.to make_database_queries(count: 2)

    expect(results[:manifests][:edges]).to eq([
      {
        node: {
          dependencies: {
            edges: [
              {
                node: {
                  license: "MIT"
                }
              },
              {
                node: {
                  license: "bsd-2-clause"
                }
              }
            ]
          }
        }
      }
    ])
  end

  it "dependents can be re-queried for by node id", vcr: { cassette_name: "manifest-queries-spec-no-dependencies" } do
    package_1 = factory.given_package("package-1", "1.0.0").package

    factory.given_manifest(
      github_repo_id: 100,
      manifest_type:  :gemfile,
      filename:       "Gemfile",
      path:           "/",
      dependencies:   [
        {
          package_name: "package-1",
          requirements: "= 1.0.0",
        },
      ]
    )

    query <<-QUERY.strip_heredoc
      {
        manifests(repositoryIds: [100]) {
          edges {
            node {
              dependencies {
                edges {
                  node {
                    packageId
                  }
                }
              }
            }
          }
        }
      }
    QUERY

    package_id = results[:manifests][:edges].first[:node][:dependencies][:edges].first[:node][:packageId]
    expect(package_id).to eq(graphql_id("Package", package_1))

    query <<-QUERY.strip_heredoc
      {
        node(id: "#{package_id}") {
          ... on Package {
            name
            id
          }
        }
      }
    QUERY

    expect(results[:node]).to eq({ name: "package-1", id: package_id })
  end

  it "can paginate", vcr: { cassette_name: "manifest-queries-spec-no-dependencies" } do
    factory.given_manifest(
      github_repo_id: 100,
      manifest_type:  :gemfile,
      filename:       "Gemfile",
      path:           "/",
      dependencies:
        (1..251).map do |i|
          {
            package_name: "dependency-#{i}",
            requirements: "> 1.0.0",
            scope:        :runtime,
          }
        end

    )

    query <<-QUERY.strip_heredoc
      {
        manifests(repositoryIds: [100]) {
          edges {
            node {
              manifestType
              repositoryId
              dependencies(first: 250) {
                pageInfo {
                  hasNextPage
                  endCursor
                }
                edges {
                  node {
                    packageName
                  }
                }
              }
            }
          }
        }
      }
    QUERY

    dependencies = results[:manifests][:edges][0][:node][:dependencies]

    # I expect to see 250 packages
    package_names = dependencies[:edges].map { |edge| edge[:node][:packageName] }
    expect(package_names.uniq.count).to eq(250)

    # I expect to have a next page
    end_cursor = dependencies[:pageInfo][:endCursor]
    expect(dependencies[:pageInfo][:hasNextPage]).to be true

    # I expect to be able to query the next page
    query <<-QUERY.strip_heredoc
      {
        manifests(repositoryIds: [100]) {
          edges {
            node {
              manifestType
              repositoryId
              dependencies(first: 250, after: "#{end_cursor}") {
                pageInfo {
                  hasNextPage
                  endCursor
                }
                edges {
                  node {
                    packageName
                  }
                }
              }
            }
          }
        }
      }
    QUERY
    dependencies2 = results[:manifests][:edges][0][:node][:dependencies]

    # I expect to ser a package I've never seen before
    package_names2 = dependencies2[:edges].map { |edge| edge[:node][:packageName] }
    expect(package_names2.uniq.count).to eq(1)

    new_package = package_names2[0]
    expect(package_names).not_to include(new_package)
  end

  context "include results from snapshots" do
    it "can request dependencies from snapshots", vcr: { cassette_name: "snapshot-manifests-query" } do
      stub_binary_dependencies_client

      repo = Repository.create(github_owner_id: 11, github_repository_id: 101, nwo: "actions/core")
      PackageFactory.new("@actions/core", "1.1.9", :npm).tap do |f|
        f.create
        f.update_repository_mapping(github_repository_id: 101,
                                    repository_id_certainty: PackageToRepoMapping::Certainty::POSITIVE_MATCH)
      end

      query <<~QUERY
        {
          manifests(repositoryIds: [16], withSnapshots: true) {
            edges {
              node {
                repositoryId
                filename
                path
                source
                manifestName
                snapshotId
                dependencies(first: 250) {
                  edges {
                    node {
                      packageName
                      repositoryId
                      packageManager
                    }
                  }
                }
              }
            }
          }
        }
      QUERY

      expect(results[:manifests][:edges]).to eq([
        {
          node: {
            repositoryId: 16,
            filename: "package-lock.json",
            path: "",
            source: "snapshots",
            manifestName: "package-lock.json",
            snapshotId: 123456789,
            dependencies: {
              edges: [
                {
                  node: {
                    packageManager: "NPM",
                    packageName: "@actions/core",
                    repositoryId: repo.github_repository_id
                  }
                },
                {
                  node: {
                    packageManager: "NPM",
                    packageName: "@actions/http-client",
                    repositoryId: nil
                  }
                },
                {
                  node: {
                    packageManager: "NPM",
                    packageName: "tunnel",
                    repositoryId: nil
                  }
                }
              ]
            }
          }
        }
      ])
    end

    it "should not break when relationship is requested", vcr: { cassette_name: "snapshot-manifests-query" } do
      stub_binary_dependencies_client

      repo = Repository.create(github_owner_id: 11, github_repository_id: 101, nwo: "actions/core")
      PackageFactory.new("@actions/core", "1.1.9", :npm).tap do |f|
        f.create
        f.update_repository_mapping(github_repository_id: 101,
                                    repository_id_certainty: PackageToRepoMapping::Certainty::POSITIVE_MATCH)
      end

      query <<~QUERY
        {
          manifests(repositoryIds: [16], withSnapshots: true) {
            edges {
              node {
                repositoryId
                filename
                path
                source
                manifestName
                snapshotId
                dependencies(first: 250) {
                  edges {
                    node {
                      packageName
                      repositoryId
                      packageManager
                      relationship
                    }
                  }
                }
              }
            }
          }
        }
      QUERY

      expect(results[:manifests][:edges]).to eq([
        {
          node: {
            repositoryId: 16,
            filename: "package-lock.json",
            path: "",
            source: "snapshots",
            manifestName: "package-lock.json",
            snapshotId: 123456789,
            dependencies: {
              edges: [
                {
                  node: {
                    packageManager: "NPM",
                    packageName: "@actions/core",
                    repositoryId: repo.github_repository_id,
                    relationship: "unknown"
                  }
                },
                {
                  node: {
                    packageManager: "NPM",
                    packageName: "@actions/http-client",
                    repositoryId: nil,
                    relationship: "unknown"
                  }
                },
                {
                  node: {
                    packageManager: "NPM",
                    packageName: "tunnel",
                    repositoryId: nil,
                    relationship: "unknown"
                  }
                }
              ]
            }
          }
        }
      ])
    end

    context "testing packageUrl" do
      it "should include package_url in response when requested", vcr: { cassette_name: "unsupported-ecosystem-manifests-query" } do
        stub_binary_dependencies_client

        query <<~QUERY
          {
            manifests(repositoryIds: [16], withSnapshots: true) {
              edges {
                node {
                  repositoryId
                  filename
                  path
                  source
                  manifestName
                  snapshotId
                  dependencies(first: 250) {
                    edges {
                      node {
                        packageName
                        packageManager
                        packageUrl
                      }
                    }
                  }
                }
              }
            }
          }
        QUERY

        expect(results[:manifests][:edges]).to eq([
          {
            node: {
              repositoryId: 16,
              filename: "Chart.lock",
              path: "",
              source: "snapshots",
              manifestName: "Chart.lock",
              snapshotId: 123456789,
              dependencies: {
                edges: [
                  {
                    node: {
                      packageManager: "UNKNOWN",
                      packageName: "bitnami/common",
                      packageUrl: "pkg:helm/bitnami/common@2.30.0"
                    }
                  },
                  {
                    node: {
                      packageManager: "UNKNOWN",
                      packageName: "bitnami/solr",
                      packageUrl: "pkg:helm/bitnami/solr@2.10.5"
                    }
                  },
                  {
                    node: {
                      packageManager: "UNKNOWN",
                      packageName: "bitnami/zookeeper",
                      packageUrl: "pkg:helm/bitnami/zookeeper@13.7.3"
                    },
                  }
                ]
              }
            }
          }
        ])
      end
    end

    it "should respect the preference sorting", vcr: { cassette_name: "snapshot-manifests-query" } do
      stub_binary_dependencies_client

      repo = Repository.create(github_owner_id: 11, github_repository_id: 101, nwo: "actions/core")
      PackageFactory.new("@actions/core", "1.1.9", :npm).tap do |f|
        f.create
        f.update_repository_mapping(github_repository_id: 101,
                                    repository_id_certainty: PackageToRepoMapping::Certainty::POSITIVE_MATCH)
      end

      query <<~QUERY
        {
          manifests(repositoryIds: [16], withSnapshots: true) {
            edges {
              node {
                repositoryId
                filename
                path
                source
                manifestName
                snapshotId
                dependencies(first: 250, prefer: ["tunnel"]) {
                  edges {
                    node {
                      packageName
                      repositoryId
                      packageManager
                    }
                  }
                }
              }
            }
          }
        }
      QUERY

      expect(results[:manifests][:edges]).to eq([
        {
          node: {
            repositoryId: 16,
            filename: "package-lock.json",
            path: "",
            source: "snapshots",
            manifestName: "package-lock.json",
            snapshotId: 123456789,
            dependencies: {
              edges: [
                {
                  node: {
                    packageManager: "NPM",
                    packageName: "tunnel",
                    repositoryId: nil
                  }
                },
                {
                  node: {
                    packageManager: "NPM",
                    packageName: "@actions/core",
                    repositoryId: repo.github_repository_id
                  }
                },
                {
                  node: {
                    packageManager: "NPM",
                    packageName: "@actions/http-client",
                    repositoryId: nil
                  }
                }
              ]
            }
          }
        }
      ])
    end

    it "includes snapshots in totalCount when returning snapshots by default is enabled", vcr: { cassette_name: "snapshot-manifests-query", allow_playback_repeats: true } do
      stub_binary_dependencies_client

      query <<~QUERY
        {
          manifests(repositoryIds: [16]) {
            totalCount
            edges {
              node {
                filename
              }
            }
          }
        }
      QUERY

      expect(results[:manifests][:totalCount]).to eq(1)
    end

    it "skips internal snapshots by default", vcr: { cassette_name: "skip-internal-snapshot-manifests-query" } do
      stub_binary_dependencies_client

      repo = Repository.create(github_owner_id: 11, github_repository_id: 102, nwo: "actions/core")
      PackageFactory.new("@actions/core", "1.1.9", :npm).tap do |f|
        f.create
        f.update_repository_mapping(github_repository_id: 102,
                                    repository_id_certainty: PackageToRepoMapping::Certainty::POSITIVE_MATCH)
      end

      query <<~QUERY
        {
          manifests(repositoryIds: [102], withSnapshots: true) {
            edges {
              node {
                repositoryId
                filename
                path
                source
                dependencies(first: 250) {
                  edges {
                    node {
                      packageName
                      repositoryId
                      packageManager
                    }
                  }
                }
              }
            }
          }
        }
      QUERY

      expect(results[:manifests][:edges]).to be_empty
    end

    it "can request internal snapshots", vcr: { cassette_name: "internal-snapshot-manifests-query" } do
      stub_binary_dependencies_client

      repo = Repository.create(github_owner_id: 11, github_repository_id: 102, nwo: "actions/core")
      PackageFactory.new("@actions/core", "1.1.9", :npm).tap do |f|
        f.create
        f.update_repository_mapping(github_repository_id: 102,
                                    repository_id_certainty: PackageToRepoMapping::Certainty::POSITIVE_MATCH)
      end

      query <<~QUERY
        {
          manifests(repositoryIds: [102], withSnapshots: true, includeInternalSnapshots: true) {
            edges {
              node {
                repositoryId
                filename
                path
                source
                dependencies(first: 250) {
                  edges {
                    node {
                      packageName
                      repositoryId
                      packageManager
                    }
                  }
                }
              }
            }
          }
        }
      QUERY

      expect(results[:manifests][:edges]).to eq([
        {
          node: {
            repositoryId: 102,
            filename: "package-lock.json",
            path: "",
            source: "snapshots",
            dependencies: {
              edges: [
                {
                  node: {
                    packageManager: "NPM",
                    packageName: "@actions/core",
                    repositoryId: 102
                  }
                },
                {
                  node: {
                    packageManager: "NPM",
                    packageName: "@actions/http-client",
                    repositoryId: nil
                  }
                },
                {
                  node: {
                    packageManager: "NPM",
                    packageName: "tunnel",
                    repositoryId: nil
                  }
                }
              ]
            }
          }
        }
      ])
    end

    it "enterprise? = true turns off queries to snapshots", vcr: { cassette_name: "snapshot-manifests-query" } do
      stub_binary_dependencies_client

      repo = Repository.create(github_owner_id: 11, github_repository_id: 101, nwo: "actions/core")
      PackageFactory.new("@actions/core", "1.1.9", :npm).tap do |f|
        f.create
        f.update_repository_mapping(github_repository_id: 101,
                                    repository_id_certainty: PackageToRepoMapping::Certainty::POSITIVE_MATCH)
      end

      allow(DependencyGraphAPI).to receive(:enterprise?).and_return(true)
      query <<~QUERY
        {
          manifests(repositoryIds: [16], withSnapshots: true) {
            edges {
              node {
                repositoryId
                filename
                path
                source
                dependencies(first: 250) {
                  edges {
                    node {
                      packageName
                      repositoryId
                      packageManager
                    }
                  }
                }
              }
            }
          }
        }
      QUERY

      expect(results[:manifests][:edges]).to eq([])
    end

    it "is case insensitive when matching snapshot packages against the package db", vcr: { cassette_name: "snapshot-manifests-query" } do
      stub_binary_dependencies_client

      repo = Repository.create(github_owner_id: 11, github_repository_id: 101, nwo: "actions/core")
      PackageFactory.new("@AcTiOnS/CoRe", "1.1.9", :npm).tap do |f|
        f.create
        f.update_repository_mapping(github_repository_id: 101,
                                    repository_id_certainty: PackageToRepoMapping::Certainty::POSITIVE_MATCH)
      end

      query <<~QUERY
        {
          manifests(repositoryIds: [16], withSnapshots: true) {
            edges {
              node {
                repositoryId
                filename
                path
                source
                dependencies(first: 250) {
                  edges {
                    node {
                      packageName
                      repositoryId
                      packageManager
                    }
                  }
                }
              }
            }
          }
        }
      QUERY

      expect(results[:manifests][:edges][0][:node][:dependencies]).to eq(
              edges: [
                {
                  node: {
                    packageManager: "NPM",
                    packageName: "@actions/core",
                    repositoryId: repo.github_repository_id
                  }
                },
                {
                  node: {
                    packageManager: "NPM",
                    packageName: "@actions/http-client",
                    repositoryId: nil
                  }
                },
                {
                  node: {
                    packageManager: "NPM",
                    packageName: "tunnel",
                    repositoryId: nil
                  }
                }
              ]
      )
    end

    it "doesn't explode with a large result", vcr: { cassette_name: "snapshot-manifests-large-query" } do
      stub_binary_dependencies_client

      query <<~QUERY
        {
          manifests(repositoryIds: [16], withSnapshots: true) {
            edges {
              node {
                repositoryId
                filename
                path
                source
                dependencies(first: 20) {
                  edges {
                    node {
                      packageName
                      repositoryId
                      packageManager
                    }
                  }
                }
              }
            }
          }
        }
      QUERY

      expect(results[:manifests][:edges][0][:node][:dependencies][:edges].count).to eq(20)
    end

    it "shows the manifest name when filename is empty", vcr: { cassette_name: "snapshot-manifests-large-query" } do
      stub_binary_dependencies_client

      query <<~QUERY
        {
          manifests(repositoryIds: [16], withSnapshots: true) {
            edges {
              node {
                repositoryId
                filename
                path
                source
              }
            }
          }
        }
      QUERY

      expect(results[:manifests][:edges][0][:node][:filename]).to eq("go.mod")
      expect(results[:manifests][:edges][0][:node][:path]).to eq("")
    end

    it "can differentiate between snapshot manifests for pagination", vcr: { cassette_name: "many-snapshots" } do
      stub_binary_dependencies_client

      query <<~QUERY
        {
          manifests(repositoryIds: [16], withSnapshots: true) {
            edges {
              node {
                id
                repositoryId
                filename
                path
                source
                dependencies(first: 20) {
                  pageInfo {
                    hasNextPage
                    endCursor
                  }
                  edges {
                    node {
                      packageName
                      repositoryId
                      packageManager
                    }
                  }
                }
              }
            }
          }
        }
      QUERY

      node = results[:manifests][:edges][9][:node]
      expect(node[:filename]).to eq("yarn.lock")
      expect(node[:dependencies][:edges].first[:node][:packageName]).to eq("@babel/code-frame")
      expect(node[:dependencies][:edges].last[:node][:packageName]).to eq("@babel/helper-replace-supers")

      manifest_id = node[:id]
      end_cursor = node[:dependencies][:pageInfo][:endCursor]

      query <<~QUERY
        {
          manifests(repositoryIds: [16], ids: [#{manifest_id}], first: 1, withSnapshots: true) {
            edges {
              node {
                id
                repositoryId
                filename
                path
                source
                dependencies(first: 20, after: "#{end_cursor}") {
                  edges {
                    node {
                      packageName
                      repositoryId
                      packageManager
                    }
                  }
                }
              }
            }
          }
        }
      QUERY

      node = results[:manifests][:edges][0][:node]
      expect(node[:filename]).to eq("yarn.lock")
      expect(node[:id]).to eq(manifest_id)
      expect(node[:dependencies][:edges].first[:node][:packageName]).to eq("@babel/helper-simple-access")
      expect(node[:dependencies][:edges].last[:node][:packageName]).to eq("@babel/plugin-transform-arrow-functions")
    end
  end

  context "include results from dgp for npm" do
    before do
      # Enable the DGP access by default
      allow_any_instance_of(Queries::ManifestsQuery).to receive(:dgp_available).and_return(true)
    end

    it "can request dependencies from dgp", vcr: { cassette_name: "dgp-manifests-query" } do
      repo = Repository.create(github_owner_id: 11, github_repository_id: 101, nwo: "actions/core")
      PackageFactory.new("@actions/core", "1.1.9", :npm).tap do |f|
        f.create
        f.update_repository_mapping(github_repository_id: 101,
                                    repository_id_certainty: PackageToRepoMapping::Certainty::POSITIVE_MATCH)
      end

      query <<~QUERY
        {
          manifests(repositoryIds: [16], withSnapshots: false) {
            edges {
              node {
                repositoryId
                filename
                path
                source
                manifestName
                dependencies(first: 250) {
                  edges {
                    node {
                      packageName
                      requirements
                      repositoryId
                      packageManager
                      relationship
                    }
                  }
                }
              }
            }
          }
        }
      QUERY

      expect(results[:manifests][:edges]).to eq([
        {
          node: {
            repositoryId: 16,
            filename: "package-lock.json",
            path: "ui/application",
            source: "dgp",
            manifestName: "package-lock.json",
            dependencies: {
              edges: [
                {
                  node: {
                    packageManager: "NPM",
                    packageName: "@actions/core",
                    relationship: "direct",
                    repositoryId: repo.github_repository_id,
                    requirements: "= 1.1.9"
                  }
                },
                {
                  node: {
                    packageManager: "NPM",
                    packageName: "@actions/http-client",
                    relationship: "transitive",
                    repositoryId: nil,
                    requirements: "^ 2.0.0"
                  }
                },
                {
                  node: {
                    packageManager: "NPM",
                    packageName: "tunnel",
                    relationship: "unknown",
                    repositoryId: nil,
                    requirements: ""
                  }
                }
              ]
            }
          }
        }
      ])
    end

    context "should include local dependencies, excluding package managers supported by DGP" do
      before do
        factory.given_manifest(
          github_repo_id: 16,
          manifest_type:  :package_lock_json,
          filename:       "package-lock.json",
          path:           "/",
          dependencies:   [
            {
              package_name: "@actions/core",
              requirements: "> 5.0.0",
              scope:        :runtime,
            }
          ]
        )
        factory.given_manifest(
          github_repo_id: 16,
          manifest_type:  :gemfile,
          filename:       "Gemfile",
          path:           "/",
          dependencies: [
            {
              package_name: "rails",
              requirements: "= 8.0",
              scope:        :runtime,
            }
          ]
        )
      end

      it "without the package manager argument", vcr: { cassette_name: "dgp-manifests-query" } do
        query <<~QUERY
          {
            manifests(repositoryIds: [16], withSnapshots: false) {
              edges {
                node {
                  repositoryId
                  filename
                  path
                  source
                  manifestName
                  dependencies(first: 250) {
                    edges {
                      node {
                        packageName
                        requirements
                        packageManager
                      }
                    }
                  }
                }
              }
            }
          }
        QUERY

        expect(results[:manifests][:edges]).to eq([
          {
            node: {
              repositoryId: 16,
              filename: "Gemfile",
              path: "/",
              source: "dependency graph",
              manifestName: nil,
              dependencies: {
                edges: [
                  {
                    node: {
                      packageManager: "RUBYGEMS",
                      packageName: "rails",
                      requirements: "= 8.0"
                    }
                  }
                ]
              }
            }
          },
          {
            node: {
              repositoryId: 16,
              filename: "package-lock.json",
              path: "ui/application",
              source: "dgp",
              manifestName: "package-lock.json",
              dependencies: {
                edges: [
                  {
                    node: {
                      packageManager: "NPM",
                      packageName: "@actions/core",
                      requirements: "= 1.1.9"
                    }
                  },
                  {
                    node: {
                      packageManager: "NPM",
                      packageName: "@actions/http-client",
                      requirements: "^ 2.0.0"
                    }
                  },
                  {
                    node: {
                      packageManager: "NPM",
                      packageName: "tunnel",
                      requirements: ""
                    }
                  }
                ]
              }
            }
          }
        ])
      end

      it "with package manager argument set to NPM", vcr: { cassette_name: "dgp-manifests-query" } do
        requested_package_manager = "NPM"
        query <<~QUERY
          {
            manifests(repositoryIds: [16], withSnapshots: false, packageManager: #{requested_package_manager}) {
              edges {
                node {
                  repositoryId
                  filename
                  path
                  source
                  manifestName
                  dependencies(first: 250) {
                    edges {
                      node {
                        packageName
                        requirements
                        packageManager
                      }
                    }
                  }
                }
              }
            }
          }
        QUERY

        expect(results[:manifests][:edges]).to eq([
          {
            node: {
              repositoryId: 16,
              filename: "package-lock.json",
              path: "ui/application",
              source: "dgp",
              manifestName: "package-lock.json",
              dependencies: {
                edges: [
                  {
                    node: {
                      packageManager: "NPM",
                      packageName: "@actions/core",
                      requirements: "= 1.1.9"
                    }
                  },
                  {
                    node: {
                      packageManager: "NPM",
                      packageName: "@actions/http-client",
                      requirements: "^ 2.0.0"
                    }
                  },
                  {
                    node: {
                      packageManager: "NPM",
                      packageName: "tunnel",
                      requirements: ""
                    }
                  }
                ]
              }
            }
          }
        ])
      end

      it "with the package manager argument set to something other than NPM", vcr: { cassette_name: "dgp-manifests-query" } do
        requested_package_manager = "RUBYGEMS"
        query <<~QUERY
          {
            manifests(repositoryIds: [16], withSnapshots: false, packageManager: #{requested_package_manager}) {
              edges {
                node {
                  repositoryId
                  filename
                  path
                  source
                  manifestName
                  dependencies(first: 250) {
                    edges {
                      node {
                        packageName
                        requirements
                        packageManager
                      }
                    }
                  }
                }
              }
            }
          }
        QUERY

        expect(results[:manifests][:edges]).to eq([
          {
            node: {
              repositoryId: 16,
              filename: "Gemfile",
              path: "/",
              source: "dependency graph",
              manifestName: nil,
              dependencies: {
                edges: [
                  {
                    node: {
                      packageManager: "RUBYGEMS",
                      packageName: "rails",
                      requirements: "= 8.0"
                    }
                  }
                ]
              }
            }
          }
        ])
      end
    end

    it "includes dgp in totalCount", vcr: { cassette_name: "dgp-manifests-query", allow_playback_repeats: true } do
      query <<~QUERY
        {
          manifests(repositoryIds: [16], withSnapshots: false) {
            totalCount
            edges {
              node {
                filename
              }
            }
          }
        }
      QUERY

      expect(results[:manifests][:totalCount]).to eq(1)
    end

    it "should respect the preference sorting", vcr: { cassette_name: "dgp-manifests-query" } do
      repo = Repository.create(github_owner_id: 11, github_repository_id: 101, nwo: "actions/core")
      PackageFactory.new("@actions/core", "1.1.9", :npm).tap do |f|
        f.create
        f.update_repository_mapping(github_repository_id: 101,
                                    repository_id_certainty: PackageToRepoMapping::Certainty::POSITIVE_MATCH)
      end

      query <<~QUERY
        {
          manifests(repositoryIds: [16], withSnapshots: false) {
            edges {
              node {
                repositoryId
                filename
                path
                source
                manifestName
                dependencies(first: 250, prefer: ["tunnel"]) {
                  edges {
                    node {
                      packageName
                      requirements
                      repositoryId
                      packageManager
                    }
                  }
                }
              }
            }
          }
        }
      QUERY

      expect(results[:manifests][:edges]).to eq([
        {
          node: {
            repositoryId: 16,
            filename: "package-lock.json",
            path: "ui/application",
            source: "dgp",
            manifestName: "package-lock.json",
            dependencies: {
              edges: [
                {
                  node: {
                    packageManager: "NPM",
                    packageName: "tunnel",
                    repositoryId: nil,
                    requirements: ""
                  }
                },
                {
                  node: {
                    packageManager: "NPM",
                    packageName: "@actions/core",
                    repositoryId: repo.github_repository_id,
                    requirements: "= 1.1.9"
                  }
                },
                {
                  node: {
                    packageManager: "NPM",
                    packageName: "@actions/http-client",
                    repositoryId: nil,
                    requirements: "^ 2.0.0"
                  }
                }
              ]
            }
          }
        }
      ])
    end

    it "is case insensitive when matching dgp dependencies against the package db", vcr: { cassette_name: "dgp-manifests-query" } do
      repo = Repository.create(github_owner_id: 11, github_repository_id: 101, nwo: "actions/core")
      PackageFactory.new("@AcTiOnS/CoRe", "1.1.9", :npm).tap do |f|
        f.create
        f.update_repository_mapping(github_repository_id: 101,
                                    repository_id_certainty: PackageToRepoMapping::Certainty::POSITIVE_MATCH)
      end

      query <<~QUERY
        {
          manifests(repositoryIds: [16], withSnapshots: false) {
            edges {
              node {
                repositoryId
                filename
                path
                source
                dependencies(first: 250) {
                  edges {
                    node {
                      packageName
                      repositoryId
                      packageManager
                    }
                  }
                }
              }
            }
          }
        }
      QUERY

      expect(results[:manifests][:edges][0][:node][:dependencies]).to eq(
              edges: [
                {
                  node: {
                    packageManager: "NPM",
                    packageName: "@actions/core",
                    repositoryId: repo.github_repository_id
                  }
                },
                {
                  node: {
                    packageManager: "NPM",
                    packageName: "@actions/http-client",
                    repositoryId: nil
                  }
                },
                {
                  node: {
                    packageManager: "NPM",
                    packageName: "tunnel",
                    repositoryId: nil
                  }
                }
              ]
      )
    end

    it "includes package data fetched from db", vcr: { cassette_name: "dgp-manifests-query" } do
      repo = Repository.create(github_owner_id: 11, github_repository_id: 101, nwo: "actions/core")
      PackageFactory.new("@actions/core", "1.1.9", :npm).tap do |f|
        f.create
        f.update_repository_mapping(github_repository_id: 101,
                                    repository_id_certainty: PackageToRepoMapping::Certainty::POSITIVE_MATCH)
        f.update_package_release(license: "MIT")
        f.add_dependency("dependent", "1.0.0")
      end

      query <<~QUERY
        {
          manifests(repositoryIds: [16], withSnapshots: false) {
            edges {
              node {
                repositoryId
                filename
                path
                source
                manifestName
                dependencies(first: 250) {
                  edges {
                    node {
                      packageName
                      requirements
                      repositoryId
                      license
                      hasDependencies
                      packageManager
                    }
                  }
                }
              }
            }
          }
        }
      QUERY

      expect(results[:manifests][:edges]).to eq([
        {
          node: {
            repositoryId: 16,
            filename: "package-lock.json",
            path: "ui/application",
            source: "dgp",
            manifestName: "package-lock.json",
            dependencies: {
              edges: [
                {
                  node: {
                    packageManager: "NPM",
                    packageName: "@actions/core",
                    repositoryId: repo.github_repository_id,
                    license: "MIT",
                    hasDependencies: true,
                    requirements: "= 1.1.9"
                  }
                },
                {
                  node: {
                    packageManager: "NPM",
                    packageName: "@actions/http-client",
                    repositoryId: nil,
                    license: nil,
                    hasDependencies: false,
                    requirements: "^ 2.0.0"
                  }
                },
                {
                  node: {
                    packageManager: "NPM",
                    packageName: "tunnel",
                    repositoryId: nil,
                    license: nil,
                    hasDependencies: false,
                    requirements: ""
                  }
                }
              ]
            }
          }
        }
      ])
    end

    it "doesn't explode with a large result", vcr: { cassette_name: "dgp-manifests-large-query" } do
      query <<~QUERY
        {
          manifests(repositoryIds: [16], withSnapshots: false) {
            edges {
              node {
                repositoryId
                filename
                path
                source
                dependencies(first: 20) {
                  edges {
                    node {
                      packageName
                      repositoryId
                      packageManager
                    }
                  }
                }
              }
            }
          }
        }
      QUERY

      expect(results[:manifests][:edges][0][:node][:dependencies][:edges].count).to eq(20)
    end

    it "doesn't explode when the manifest doesn't have dependencies", vcr: { cassette_name: "dgp-manifests-without-dependencies" } do
      query <<~QUERY
        {
          manifests(repositoryIds: [16], withSnapshots: false) {
            edges {
              node {
                repositoryId
                filename
                path
                source
                manifestName
                dependencies(first: 250) {
                  edges {
                    node {
                      packageName
                      requirements
                      repositoryId
                      packageManager
                    }
                  }
                }
              }
            }
          }
        }
      QUERY

      expect(results[:manifests][:edges]).to eq([
        {
          node: {
            repositoryId: 16,
            filename: "package-lock.json",
            path: "ui/application",
            source: "dgp",
            manifestName: "package-lock.json",
            dependencies: {
              edges: []
            }
          }
        }
      ])
    end

    it "can differentiate between dgp manifests for pagination", vcr: { cassette_name: "many-dgp-manifests", allow_playback_repeats: true, match_requests_on: [:uri, :body] } do
      query <<~QUERY
        {
          manifests(repositoryIds: [16], withSnapshots: false) {
            edges {
              node {
                id
                repositoryId
                filename
                path
                source
                dependencies(first: 25) {
                  pageInfo {
                    hasNextPage
                    endCursor
                  }
                  edges {
                    node {
                      packageName
                      requirements
                      repositoryId
                      packageManager
                    }
                  }
                }
              }
            }
          }
        }
      QUERY

      node = results[:manifests][:edges][1][:node]
      expect(node[:filename]).to eq("package-lock.json")
      expect(node[:dependencies][:edges].first[:node][:packageName]).to eq("@aashutoshrathi/word-wrap")
      expect(node[:dependencies][:edges].last[:node][:packageName]).to eq("@babel/helper-annotate-as-pure")

      manifest_id = node[:id]
      end_cursor = node[:dependencies][:pageInfo][:endCursor]

      query <<~QUERY
        {
          manifests(repositoryIds: [16], ids: [#{manifest_id}], first: 1, withSnapshots: false) {
            edges {
              node {
                id
                repositoryId
                filename
                path
                source
                dependencies(first: 25, after: "#{end_cursor}") {
                  edges {
                    node {
                      packageName
                      requirements
                      repositoryId
                      packageManager
                    }
                  }
                }
              }
            }
          }
        }
      QUERY

      node = results[:manifests][:edges][0][:node]
      expect(node[:filename]).to eq("package-lock.json")
      expect(node[:id]).to eq(manifest_id)
      expect(node[:dependencies][:edges].first[:node][:packageName]).to eq("@babel/helper-annotate-as-pure")
      expect(node[:dependencies][:edges].last[:node][:packageName]).to eq("@babel/helper-hoist-variables")
    end

    it "exposes the relationship field", vcr: { cassette_name: "dgp-manifests-query" } do
      repo = Repository.create(github_owner_id: 11, github_repository_id: 101, nwo: "actions/core")
      PackageFactory.new("@actions/core", "1.1.9", :npm).tap do |f|
        f.create
        f.update_repository_mapping(github_repository_id: 101,
                                    repository_id_certainty: PackageToRepoMapping::Certainty::POSITIVE_MATCH)
      end

      query <<~QUERY
        {
          manifests(repositoryIds: [16], withSnapshots: false) {
            edges {
              node {
                repositoryId
                filename
                path
                source
                manifestName
                dependencies(first: 250) {
                  edges {
                    node {
                      packageName
                      requirements
                      repositoryId
                      packageManager
                      relationship
                    }
                  }
                }
              }
            }
          }
        }
      QUERY

      expect(results[:manifests][:edges]).to eq([
        {
          node: {
            repositoryId: 16,
            filename: "package-lock.json",
            path: "ui/application",
            source: "dgp",
            manifestName: "package-lock.json",
            dependencies: {
              edges: [
                {
                  node: {
                    packageManager: "NPM",
                    packageName: "@actions/core",
                    repositoryId: repo.github_repository_id,
                    requirements: "= 1.1.9",
                    relationship: "direct"
                  }
                },
                {
                  node: {
                    packageManager: "NPM",
                    packageName: "@actions/http-client",
                    repositoryId: nil,
                    requirements: "^ 2.0.0",
                    relationship: "transitive"
                  }
                },
                {
                  node: {
                    packageManager: "NPM",
                    packageName: "tunnel",
                    repositoryId: nil,
                    requirements: "",
                    relationship: "unknown"
                  }
                }
              ]
            }
          }
        }
      ])
    end

    context "testing packageUrl" do
      it "should include packageUrl in response when requested", vcr: { cassette_name: "dgp-manifests-query" } do
        repo = Repository.create(github_owner_id: 11, github_repository_id: 101, nwo: "actions/core")
        PackageFactory.new("@actions/core", "1.1.9", :npm).tap do |f|
          f.create
          f.update_repository_mapping(github_repository_id: 101,
                                      repository_id_certainty: PackageToRepoMapping::Certainty::POSITIVE_MATCH)
        end

        query <<~QUERY
          {
            manifests(repositoryIds: [16], withSnapshots: false) {
              edges {
                node {
                  repositoryId
                  filename
                  path
                  source
                  manifestName
                  dependencies(first: 250) {
                    edges {
                      node {
                        packageManager
                        packageName
                        packageUrl
                      }
                    }
                  }
                }
              }
            }
          }
        QUERY

        expect(results[:manifests][:edges]).to eq([
          {
            node: {
              repositoryId: 16,
              filename: "package-lock.json",
              path: "ui/application",
              source: "dgp",
              manifestName: "package-lock.json",
              dependencies: {
                edges: [
                  {
                    node: {
                      packageManager: "NPM",
                      packageName: "@actions/core",
                      packageUrl: "pkg:npm/%40actions/core@1.1.9"
                    }
                  },
                  {
                    node: {
                      packageManager: "NPM",
                      packageName: "@actions/http-client",
                      packageUrl: "pkg:npm/%40actions/http-client"
                    }
                  },
                  {
                    node: {
                      packageManager: "NPM",
                      packageName: "tunnel",
                      packageUrl: "pkg:npm/tunnel"
                    }
                  }
                ]
              }
            }
          }
        ])
      end
    end
  end

  context "transitive labels from DS-API for Maven ecosystem" do
    it "includes transitive labels", vcr: { cassette_name: "snapshot-maven-manifests-query" } do
      stub_binary_dependencies_client

      repo = Repository.create(github_owner_id: 11, github_repository_id: 101, nwo: "my-org/log4j")
      PackageFactory.new("my-org/log4j", "1.1.1", :maven).tap do |f|
        f.create
        f.update_repository_mapping(github_repository_id: 101,
                                    repository_id_certainty: PackageToRepoMapping::Certainty::POSITIVE_MATCH)
      end

      query <<~QUERY
        {
          manifests(repositoryIds: [16], withSnapshots: true) {
            edges {
              node {
                repositoryId
                filename
                path
                source
                manifestName
                snapshotId
                dependencies(first: 250) {
                  edges {
                    node {
                      packageName
                      repositoryId
                      packageManager
                      relationship
                    }
                  }
                }
              }
            }
          }
        }
      QUERY

      expect(results[:manifests][:edges]).to eq([
        {
          node: {
            repositoryId: 16,
            filename: "pom.xml",
            path: "",
            source: "snapshots",
            manifestName: "pom.xml",
            snapshotId: 123456789,
            dependencies: {
              edges: [
                {
                  node: {
                    packageManager: "MAVEN",
                    packageName: "my-org:jackson-annotations",
                    relationship: "transitive",
                    repositoryId: nil
                  }
                },
                {
                  node: {
                    packageManager: "MAVEN",
                    packageName: "my-org:jsr305",
                    relationship: "transitive",
                    repositoryId: nil
                  }
                },
                {
                  node: {
                    packageManager: "MAVEN",
                    packageName: "my-org:junit",
                    relationship: "unknown",
                    repositoryId: nil
                  }
                },
                {
                  node: {
                    packageManager: "MAVEN",
                    packageName: "my-org:log4j",
                    relationship: "direct",
                    repositoryId: nil
                  }
                },
                {
                  node: {
                    packageManager: "MAVEN",
                    packageName: "my-org:netty",
                    relationship: "unknown",
                    repositoryId: nil
                  }
                }
              ]
            }
          }
        }
      ])
    end
  end
end
