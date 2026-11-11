require "rails_helper"

module Views
  describe PackageReleaseVulnerabilitiesCount do
    it "rebuilds package release vulnerabilities counts" do
      factory do
        given_vulnerable_version_range({
          github_id: 1,
          package_name: "actionview",
          package_manager: :rubygems,
          version_range: ">= 5.1.0, <= 5.1.6.1",
          severity: "high",
        })

        given_vulnerable_version_range({
          github_id: 2,
          package_name: "actionview",
          package_manager: :rubygems,
          version_range: ">= 5.1.6.1, <= 5.1.6.3",
          severity: "low",
        })
      end

      actionview = factory.given_package("actionview", "5.1.6.2", :rubygems).release

      described_class.rebuild

      vuln_count = actionview.vulnerability_count_view

      expect(vuln_count.total_count).to eq(1)
      expect(vuln_count.low_count).to eq(1)
    end

    it "rebuilds successfully on each additional vulnerability" do
      factory.given_vulnerable_version_range({
        github_id: 2,
        package_name: "actionview",
        package_manager: :rubygems,
        version_range: ">= 5.1.6.1, <= 5.1.6.3",
        severity: "low",
      })

      actionview = factory.given_package("actionview", "5.1.6.2", :rubygems).release

      described_class.rebuild

      vuln_count = actionview.vulnerability_count_view

      expect(vuln_count.total_count).to eq(1)
      expect(vuln_count.low_count).to eq(1)
      expect(vuln_count.moderate_count).to eq(0)

      factory.given_vulnerable_version_range({
        github_id: 3,
        package_name: "actionview",
        package_manager: :rubygems,
        version_range: ">= 5.1.5.1, <= 5.1.6.4",
        severity: "moderate",
      })

      described_class.rebuild

      vuln_count = actionview.reload.vulnerability_count_view

      expect(vuln_count.total_count).to eq(2)
      expect(vuln_count.low_count).to eq(1)
      expect(vuln_count.moderate_count).to eq(1)
    end

    it "keeps up to date after deleting vulnerable version range" do
      version_range = factory.given_vulnerable_version_range({
        github_id: 4,
        package_name: "actionview",
        package_manager: :rubygems,
        version_range: ">= 5.1.7.1, <= 5.1.8.3",
        severity: "critical",
      })

      actionview = factory.given_package("actionview", "5.1.7.2", :rubygems).release

      described_class.rebuild

      vuln_count = actionview.vulnerability_count_view

      expect(vuln_count.total_count).to eq(1)
      expect(vuln_count.critical_count).to eq(1)

      version_range.destroy

      described_class.rebuild

      vuln_count = actionview.reload.vulnerability_count_view

      expect(vuln_count).to be_nil
    end
  end
end
