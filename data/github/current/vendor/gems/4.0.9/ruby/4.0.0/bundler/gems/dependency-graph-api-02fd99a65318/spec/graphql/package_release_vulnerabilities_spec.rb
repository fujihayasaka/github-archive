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

      given_vulnerable_version_range({
        github_id: 160,
        package_name: "innersource_pkg",
        package_manager: :rubygems,
        version_range: ">= 1.0.0, < 2.0.0",
        visibility_scope: :innersource,
        owner_business_id: 123,
        owner_org_id: nil
      })

      given_vulnerable_version_range({
        github_id: 161,
        package_name: "innersource_pkg",
        package_manager: :rubygems,
        version_range: ">= 1.0.0, < 2.0.0",
        visibility_scope: :innersource,
        owner_business_id: nil,
        owner_org_id: 456
      })

      given_vulnerable_version_range({
        github_id: 162,
        package_name: "innersource_pkg",
        package_manager: :rubygems,
        version_range: ">= 1.0.0, < 2.0.0",
        owner_business_id: nil,
        owner_org_id: nil
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

  context "with business_id and org_id filtering" do
    it "returns only opensource vulnerabilities when no business_id or org_id is provided" do
      query <<-QUERY.strip_heredoc
        {
          packageReleaseVulnerabilities(packageName: "innersource_pkg", packageManager: RUBYGEMS, containsVersion: "1.5.0")
        }
      QUERY
      expect(results).to eq({ packageReleaseVulnerabilities: [162] })
    end

    it "returns innersource vulnerabilities when business_id is provided" do
      query <<-QUERY.strip_heredoc
        {
          packageReleaseVulnerabilities(packageName: "innersource_pkg", packageManager: RUBYGEMS, containsVersion: "1.5.0", businessId: 123)
        }
      QUERY
      expect(results).to eq({ packageReleaseVulnerabilities: [160, 162] })
    end

    it "returns innersource vulnerabilities when org_id is provided" do
      query <<-QUERY.strip_heredoc
        {
          packageReleaseVulnerabilities(packageName: "innersource_pkg", packageManager: RUBYGEMS, containsVersion: "1.5.0", orgId: 456)
        }
      QUERY
      expect(results).to eq({ packageReleaseVulnerabilities: [161, 162] })
    end

    it "returns all matching vulnerabilities when both business_id and org_id are provided" do
      query <<-QUERY.strip_heredoc
        {
          packageReleaseVulnerabilities(packageName: "innersource_pkg", packageManager: RUBYGEMS, containsVersion: "1.5.0", businessId: 123, orgId: 456)
        }
      QUERY
      expect(results).to eq({ packageReleaseVulnerabilities: [160, 161, 162] })
    end
  end
end
