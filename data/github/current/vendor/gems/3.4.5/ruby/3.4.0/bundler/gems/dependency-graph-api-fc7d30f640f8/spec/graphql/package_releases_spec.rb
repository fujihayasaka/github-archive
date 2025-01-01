require "rails_helper"

describe "querying for package releases" do
  before do
    factory do
      given_package("rake", "11.2.0")

      given_package("multi_xml", "0.5.2", :rubygems)
        .update_package(repository_id: 100)
        .add_dependency("rake", "> 0.0.0")

      given_package("multi_xml", "0.5.3", :rubygems)
        .update_package_release(published_at: "2018-09-05 20:33:33", package_manager: 1, package_name: "multi_xml")
        .update_package(repository_id: 100)
        .add_dependency("rake", "> 0.0.0")

        given_package("multi_xml", "0.5.1", :rubygems)
        .update_package_release(published_at: "2018-03-05 20:33:33", package_manager: 1, package_name: "multi_xml")
        .update_package(repository_id: 100)
        .add_dependency("rake", "> 0.1.0")

        given_package("multi_xml", "0.4.9", :rubygems)
        .update_package_release(published_at: "2017-11-05 20:33:33", package_manager: 1, package_name: "multi_xml")
        .update_package(repository_id: 100)
        .add_dependency("rake", "> 0.0.9")

      given_package("rails", "5.2.2", :rubygems)
        .update_package_release(published_at: "2019-04-22 13:33:33", package_manager: 1, package_name: "rails",
          license: "MIT", clearly_defined_score: 45
        )
    end
  end

  it "finds releases by package name and manager" do
    query <<-QUERY.strip_heredoc
      {
        packageReleases(first: 1, packageName: "multi_xml", packageManager: RUBYGEMS) {
          edges {
            node {
              version
              latestVersion
              isLatest
              packageName
              packageManager
              repositoryId
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      packageReleases: {
        edges: [
          {
            node: {
              version:        "0.5.3",
              latestVersion:  "0.5.3",
              isLatest:       true,
              packageName:    "multi_xml",
              packageManager: "RUBYGEMS",
              repositoryId:   100,
            }
          }
        ]
      }
    })
  end

  it "finds date when a release was published" do
    query <<-QUERY.strip_heredoc
      {
        packageReleases(first: 1, packageName: "multi_xml", packageManager: RUBYGEMS, requirements: "= 0.5.3") {
          edges {
            node {
              version
              packageName
              packageManager
              repositoryId
              publishedOn
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      packageReleases: {
        edges: [
          {
            node: {
              version:        "0.5.3",
              packageName:    "multi_xml",
              packageManager: "RUBYGEMS",
              repositoryId:   100,
              publishedOn:    "2018-09-05",
            }
          }
        ]
      }
    })
  end

  it "excludes releases with package managers in preview mode" do
    stub_const("DependencyGraph::PACKAGE_MANAGER_PREVIEW", [
      Types::PackageManager[:rubygems]
    ])

    query <<~QUERY
      {
        packageReleases(first: 1, packageName: "multi_xml", packageManager: RUBYGEMS) {
          edges {
            node {
              version
              packageName
              packageManager
              repositoryId
            }
          }
        }
      }
    QUERY

    expect(results).to eq({ packageReleases: { edges: [] } })

    query <<~QUERY
      {
        packageReleases(first: 1, packageName: "multi_xml", packageManager: RUBYGEMS, preview: true) {
          edges {
            node {
              version
              packageName
              packageManager
              repositoryId
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      packageReleases: {
        edges: [
          {
            node: {
              version:        "0.5.3",
              packageName:    "multi_xml",
              packageManager: "RUBYGEMS",
              repositoryId:   100,
            }
          }
        ]
      }
    })

  end

  it "filters by requirements" do
    query <<-QUERY.strip_heredoc
      {
        packageReleases(first: 5, packageName: "multi_xml", packageManager: RUBYGEMS, requirements: "> 0.4.4, < 0.5.3") {
          edges {
            node {
              version
              isLatest
              packageName
              packageManager
              repositoryId
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      packageReleases: {
        edges: [
          {
            node: {
              version:        "0.5.2",
              isLatest:       false,
              packageName:    "multi_xml",
              packageManager: "RUBYGEMS",
              repositoryId:   100,
            }
          },
          {
            node: {
              version:        "0.5.1",
              isLatest:       false,
              packageName:    "multi_xml",
              packageManager: "RUBYGEMS",
              repositoryId:   100,
            }
          },
          {
            node: {
              version:        "0.4.9",
              isLatest:       false,
              packageName:    "multi_xml",
              packageManager: "RUBYGEMS",
              repositoryId:   100,
            }
          }
        ]
      }
    })
  end

  it "included dependencies" do
    query <<-QUERY.strip_heredoc
      {
        packageReleases(first: 1, packageName: "multi_xml", packageManager: RUBYGEMS) {
          edges {
            node {
              version
              packageName
              dependencies {
                edges {
                  node {
                    packageName
                    requirements
                  }
                }
              }
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      packageReleases: {
        edges: [
          {
            node: {
              version:     "0.5.3",
              packageName: "multi_xml",
              dependencies: {
                edges: [
                  {
                    node: {
                      packageName: "rake",
                      requirements: "> 0.0.0",
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

  it "includes license information" do
    query <<-QUERY.strip_heredoc
      {
        packageReleases(first: 1, packageName: "rails", packageManager: RUBYGEMS, requirements: "= 5.2.2") {
          edges {
            node {
              version
              license
              clearlyDefinedScore
            }
          }
        }
      }
    QUERY

    expect(results).to eq({
      packageReleases: {
        edges: [
          {
            node: {
              clearlyDefinedScore: 45,
              license: "MIT",
              version: "5.2.2",
            }
          }
        ]
      }
    })
  end
end
