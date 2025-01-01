require "rails_helper"

describe "querying for packages" do
  before do
    factory do
      rails = given_package("multi_xml", "0.5.2")
        .update_package(repository_id: 300)
        .update_package_repository({ github_owner_id: 310, nwo: "sferik/multi_xml" })
        .package

      given_package("rails", "5.0.0")
        .update_package(repository_id: 100)
        .update_package_release(repository_id: 100, published_at: Time.now)
        .update_package_repository({ github_owner_id: 110, nwo: "rails/rails" })
        .add_dependency("multi_xml", ">= 0.5.2")

      given_package("httparty", "0.14.0")
        .update_package({
            repository_id: 200,
            repository_id_certainty: PackageToRepoMapping::Certainty.minimum_required_for_display
        })
        .update_package_release(repository_id: 200, published_at: Time.now)
        .update_package_repository({ github_owner_id: 210, nwo: "jnunemaker/httparty" })
        .add_dependency("multi_xml", ">= 0.5.2")

      given_manifest(github_repo_id: 2000, github_owner_id: 2100)
        .add_dependency("httparty", "= 0.14.0")

      given_manifest(github_repo_id: 3000, github_owner_id: 3100)
        .add_dependency("httparty", "= 0.14.0")
    end

    create_corresponding_manifest_for_package(get_package("multi_xml"))
    create_corresponding_manifest_for_package(get_package("rails"))
    create_corresponding_manifest_for_package(get_package("httparty"))

    Views::AbstractPackageDependencyCount.rebuild
    Views::AbstractRepositoryDependencyCount.rebuild
  end

  it "finds packages by repository ID" do
    query <<-QUERY.strip_heredoc
      {
        packages(repositoryIds: [200]) {
          edges {
            node {
              name
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      packages: {
        edges: [
          {
            node: {
              name: "httparty"
            }
          }
        ]
      }
    })
  end

  it "excludes packages with package managers in preview mode" do
    PackageFactory.new("httparty", "0.14.0", :npm).create!(published_at: "2018-10-10 20:33:33")
    stub_const("DependencyGraph::PACKAGE_MANAGER_PREVIEW", [
      Types::PackageManager[:rubygems]
    ])

    query <<~QUERY
      {
        packages(names: ["httparty"], packageManager: RUBYGEMS) {
          edges {
            node {
              name
              packageManager
            }
          }
        }
      }
    QUERY

    expect(results).to eq({ packages: { edges: [] } })

    query <<~QUERY
      {
        packages(names: ["httparty"]) {
          edges {
            node {
              name
              packageManager
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      packages: {
        edges: [
          {
            node: {
              name: "httparty",
              packageManager: "NPM"
            }
          }
        ]
      }
    })

    query <<~QUERY
      {
        packages(names: ["httparty"], packageManager: NPM) {
          edges {
            node {
              name
              packageManager
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      packages: {
        edges: [
          {
            node: {
              name: "httparty",
              packageManager: "NPM"
            }
          }
        ]
      }
    })

    query <<~QUERY
      {
        packages(names: ["httparty"], preview: true) {
          edges {
            node {
              name
              packageManager
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      packages: {
        edges: [
          {
            node: {
              name: "httparty",
              packageManager: "RUBYGEMS"
            }
          },
          {
            node: {
              name: "httparty",
              packageManager: "NPM"
            }
          }
        ]
      }
    })
  end

  it "finds packages without corresponding manifests when debugging" do
    factory.given_package("linguist", "0.0.1")
      .update_package(repository_id: 600)

    query <<-QUERY.strip_heredoc
      {
        packages(repositoryIds: [600], debug: true) {
          edges {
            node {
              name
              repositoryId
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      packages: {
        edges: [
          {
            node: {
              name: "linguist",
              repositoryId: 600,
            }
          }
        ]
      }
    })
  end

  it "finds packages by name" do
    query <<-QUERY.strip_heredoc
      {
        packages(names: ["httparty"], packageManager: RUBYGEMS) {
          edges {
            node {
              name
              repositoryId
              repositoryNwo
              packageManager
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      packages: {
        edges: [
          {
            node: {
              name: "httparty",
              repositoryId: 200,
              repositoryNwo: "jnunemaker/httparty",
              packageManager: "RUBYGEMS"
            }
          }
        ]
      }
    })
  end

  it "finds packages by ID" do
    query <<-QUERY.strip_heredoc
      {
        packages(ids: [#{get_package("multi_xml").id}]) {
          edges {
            node {
              name
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      packages: {
        edges: [
          {
            node: {
              name: "multi_xml"
            }
          }
        ]
      }
    })
  end

  it "packages can be re-queried for by node id" do
    query <<-QUERY.strip_heredoc
      {
        packages(repositoryIds: [200]) {
          edges {
            node {
              id
            }
          }
        }
      }
    QUERY

    package_id = results[:packages][:edges].first[:node][:id]

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

    expect(results).to eq({
      node: {
        name: "httparty",
        id: package_id
      }
    })
  end

  it "finds abstract repository dependents" do
    query <<-QUERY.strip_heredoc
      {
        packages(names: ["httparty"]) {
          edges {
            node {
              name
              abstractRepositoryDependents(first: 1) {
                totalCount
                edges {
                  node {
                    name
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
      packages: {
        edges: [
          {
            node: {
              name: "httparty",
              abstractRepositoryDependents: {
                totalCount: 2,
                edges: [
                  {
                    node: {
                      name: nil,
                      repositoryId: 3000
                    }
                  }
                ]
              }
            }
          }
        ]
      }
    })
  end

  it "allows filtering abstract repository dependents by owner" do
    query <<-QUERY.strip_heredoc
      {
        packages(names: ["httparty"]) {
          edges {
            node {
              name
              abstractRepositoryDependents(first: 1, ownerId: 3100) {
                totalCount
                edges {
                  node {
                    name
                    repositoryId
                    ownerId
                  }
                }
              }
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      packages: {
        edges: [
          {
            node: {
              name: "httparty",
              abstractRepositoryDependents: {
                totalCount: 1,
                edges: [
                  {
                    node: {
                      name: nil,
                      repositoryId: 3000,
                      ownerId: 3100
                    }
                  }
                ]
              }
            }
          }
        ]
      }
    })
  end

  it "paginates abstract repository dependents" do
    query <<-QUERY.strip_heredoc
      {
        packages(names: ["httparty"]) {
          edges {
            node {
              name
              abstractRepositoryDependents(first: 1) {
                totalCount
                edges {
                  cursor
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

    dependents = results
      .dig(:packages, :edges)
      .first
      .dig(:node, :abstractRepositoryDependents, :edges)
    expect(dependents.count).to eq 1
    cursor = dependents.first[:cursor]
    expect(cursor).to be_present
    expect(dependents.first[:node]).to eq({ repositoryId: 3000 })

    query <<-QUERY.strip_heredoc
      {
        packages(names: ["httparty"]) {
          edges {
            node {
              name
              abstractRepositoryDependents(first: 1, after: "#{cursor}") {
                totalCount
                edges {
                  cursor
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

    dependents = results
      .dig(:packages, :edges)
      .first
      .dig(:node, :abstractRepositoryDependents, :edges)
    expect(dependents.count).to eq 1
    cursor = dependents.first[:cursor]
    expect(cursor).to be_present
    expect(dependents.first[:node]).to eq({ repositoryId: 2000 })

    query <<-QUERY.strip_heredoc
      {
        packages(names: ["httparty"]) {
          edges {
            node {
              name
              abstractRepositoryDependents(last: 1, before: "#{cursor}") {
                totalCount
                edges {
                  cursor
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

    dependents = results
      .dig(:packages, :edges)
      .first
      .dig(:node, :abstractRepositoryDependents, :edges)
    expect(dependents.count).to eq 1
    cursor = dependents.first[:cursor]
    expect(cursor).to be_present
    expect(dependents.first[:node]).to eq({ repositoryId: 3000 })
  end

  it "finds abstract package dependents" do
    query <<-QUERY.strip_heredoc
      {
        packages(names: ["multi_xml"]) {
          edges {
            node {
              name
              abstractPackageDependents(first: 1) {
                totalCount
                edges {
                  node {
                    name
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
      packages: {
        edges: [
          {
            node: {
              name: "multi_xml",
              abstractPackageDependents: {
                totalCount: 2,
                edges: [
                  {
                    node: {
                      name: "httparty",
                      repositoryId: 200
                    }
                  }
                ]
              }
            }
          }
        ]
      }
    })
  end

  it "allows filtering abstract package dependents by owner" do
    query <<-QUERY.strip_heredoc
      {
        packages(names: ["multi_xml"]) {
          edges {
            node {
              name
              abstractPackageDependents(first: 1, ownerId: 210) {
                totalCount
                edges {
                  node {
                    name
                    repositoryId
                    ownerId
                  }
                }
              }
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      packages: {
        edges: [
          {
            node: {
              name: "multi_xml",
              abstractPackageDependents: {
                totalCount: 1,
                edges: [
                  {
                    node: {
                      name: "httparty",
                      repositoryId: 200,
                      ownerId: 210
                    }
                  }
                ]
              }
            }
          }
        ]
      }
    })
  end

  it "paginates abstract package dependents" do
    query <<-QUERY.strip_heredoc
      {
        packages(names: ["multi_xml"]) {
          edges {
            node {
              name
              abstractPackageDependents(first: 1) {
                totalCount
                edges {
                  cursor
                  node {
                    name
                  }
                }
              }
            }
          }
        }
      }
    QUERY

    dependents = results
      .dig(:packages, :edges)
      .first
      .dig(:node, :abstractPackageDependents, :edges)
    expect(dependents.count).to eq 1
    cursor = dependents.first[:cursor]
    expect(cursor).to be_present
    expect(dependents.first[:node]).to eq({ name: "httparty" })

    query <<-QUERY.strip_heredoc
      {
        packages(names: ["multi_xml"]) {
          edges {
            node {
              name
              abstractPackageDependents(first: 1, after: "#{cursor}") {
                totalCount
                edges {
                  cursor
                  node {
                    name
                  }
                }
              }
            }
          }
        }
      }
    QUERY

    dependents = results
      .dig(:packages, :edges)
      .first
      .dig(:node, :abstractPackageDependents, :edges)
    expect(dependents.count).to eq 1
    cursor = dependents.first[:cursor]
    expect(cursor).to be_present
    expect(dependents.first[:node]).to eq({ name: "rails" })

    query <<-QUERY.strip_heredoc
      {
        packages(names: ["multi_xml"]) {
          edges {
            node {
              name
              abstractPackageDependents(last: 1, before: "#{cursor}") {
                totalCount
                edges {
                  cursor
                  node {
                    name
                  }
                }
              }
            }
          }
        }
      }
    QUERY

    dependents = results
      .dig(:packages, :edges)
      .first
      .dig(:node, :abstractPackageDependents, :edges)
    expect(dependents.count).to eq 1
    cursor = dependents.first[:cursor]
    expect(cursor).to be_present
    expect(dependents.first[:node]).to eq({ name: "httparty" })
  end

  def create_corresponding_manifest_for_package(package)
    repository = Repository.where({
      github_repository_id: package.github_repository_id
    }).first_or_create!

    Manifest.create!({
      repository:      repository,
      manifest_type:   :gemspec,
      name:            package.name,
      package_manager: package.package_manager || :rubygems,
      latest_git_ref:  "abc",
      last_pushed_at:  Time.now,
    })
  end
end
