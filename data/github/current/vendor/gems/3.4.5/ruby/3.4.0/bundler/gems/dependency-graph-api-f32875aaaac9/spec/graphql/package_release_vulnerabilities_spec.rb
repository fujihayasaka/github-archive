require "rails_helper"

describe "querying for package release vulnerabilities" do
  before do
    factory do
      given_vulnerable_version_range({
        github_id: 150,
        package_name: "multi_xml",
        package_manager: :rubygems,
        version_range: "> 0, < 1.0"
      })

      given_vulnerable_version_range({
        github_id: 151,
        package_name: "multi_xml",
        package_manager: :rubygems,
        version_range: "> 0, < 2.0",
      })

      given_vulnerable_version_range({
        github_id: 152,
        package_name: "multi_xml",
        package_manager: :rubygems,
        version_range: "> 2.0, < 3.0",
      })

      given_vulnerable_version_range({
        github_id: 153,
        package_name: "httparty",
        package_manager: :rubygems,
        version_range: "< 2.0.1",
      })

      given_vulnerable_version_range({
        github_id: 154,
        package_name: "actionview",
        package_manager: :rubygems,
        version_range: ">= 5.1.0, <= 5.1.6.1",
      })

      given_vulnerable_version_range({
        github_id: 155,
        package_name: "sarahspackage",
        package_manager: :rubygems,
        version_range: ">= 5.1.6.1, <= 5.1.6.3",
      })
    end
  end

  it "includes the GitHub vulnerability ids associated with the package name/manager/version" do
    query <<-QUERY.strip_heredoc
      {
        packageReleaseVulnerabilities(packageName: "multi_xml", packageManager: RUBYGEMS, containsVersion: "0.9.2")
      }
    QUERY
    expect(results).to eq({ packageReleaseVulnerabilities: [150, 151] })
  end

  it "scopes to the specified version" do
    query <<-QUERY.strip_heredoc
      {
        packageReleaseVulnerabilities(packageName: "multi_xml", packageManager: RUBYGEMS, containsVersion: "2.5")
      }
    QUERY
    expect(results).to eq({ packageReleaseVulnerabilities: [152] })

    query <<-QUERY.strip_heredoc
      {
        packageReleaseVulnerabilities(packageName: "multi_xml", packageManager: RUBYGEMS, containsVersion: "4.0")
      }
    QUERY
    expect(results).to eq({ packageReleaseVulnerabilities: [] })
  end

  it "scopes to the specified package manager" do
    query <<-QUERY.strip_heredoc
      {
        packageReleaseVulnerabilities(packageName: "multi_xml", packageManager: NPM, containsVersion: "1.2.3")
      }
    QUERY
    expect(results).to eq({ packageReleaseVulnerabilities: [] })
  end

  it "respects vulnerable version ranges that involve more than 3 version parts" do
    query <<-QUERY.strip_heredoc
      {
        packageReleaseVulnerabilities(packageName: "actionview", packageManager: RUBYGEMS, containsVersion: "5.1.6.2")
      }
    QUERY
    expect(results).to eq({ packageReleaseVulnerabilities: [] })

    query <<-QUERY.strip_heredoc
      {
        packageReleaseVulnerabilities(packageName: "sarahspackage", packageManager: RUBYGEMS, containsVersion: "5.1.6.2")
      }
    QUERY
    expect(results).to eq({ packageReleaseVulnerabilities: [155] })

    query <<-QUERY.strip_heredoc
      {
        packageReleaseVulnerabilities(packageName: "sarahspackage", packageManager: RUBYGEMS, containsVersion: "5.1.6.4")
      }
    QUERY
    expect(results).to eq({ packageReleaseVulnerabilities: [] })
  end
end
