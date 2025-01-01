require "rails_helper"
require "db_helpers"

describe VulnerableVersionRange do
  describe ".sync" do
    before do
      reset_vulnerability_data
    end

    let!(:vulnerability) do
      VulnerableVersionRange::GitHubVulnerability.create!({
        severity: "critical",
        status: "published",
      })
    end

    let!(:withdrawn_vulnerability) do
      VulnerableVersionRange::GitHubVulnerability.create!({
        status: "withdrawn",
      })
    end

    let!(:vulnerable_version_range) do
      vulnerability.vulnerable_version_ranges.create!({
        affects: "rails",
        ecosystem: "RubyGems",
        requirements: ">= 5.0.0, < 5.1.0",
        fixed_in: "5.1.0",
      })
    end

    let!(:withdrawn_vulnerable_version_range) do
      withdrawn_vulnerability.vulnerable_version_ranges.create!({
        affects: "withdrawn-rails",
        ecosystem: "RubyGems",
        requirements: ">= 5.0.0, < 5.1.0",
        fixed_in: "5.1.0",
      })
    end

    it "copies ranges from the dotcom database" do
      described_class.sync

      expect(described_class.count).to eq 1

      range = described_class.first
      expect(range.github_id).to eq vulnerable_version_range.id
      expect(range.severity).to eq "critical"
      expect(range.package_name).to eq "rails"
      expect(range.package_manager).to eq Types::PackageManager[:rubygems]
      expect(range.version_range).to eq ">= 5.0.0,< 5.1.0"
      expect(range.encoded_lower_bound).to eq Versioning::SemanticVersion.new(
        major: 5,
        minor: 0,
        patch: 0,
      ).encoded.to_i
      expect(range.encoded_upper_bound).to eq Versioning::SemanticVersion.new(
        major: 5,
        minor: 0,
        patch: Float::INFINITY
      ).encoded.to_i
    end

    it "drops old version ranges that have been deleted in dotcom" do
      deleted_in_dotcom = described_class.create!({
        github_id: 10,
        package_manager: :rubygems,
        package_name: "rake",
        version_range: "= 4.0.0",
        encoded_lower_bound: Versioning::SemanticVersion.new(
          major: 4,
          minor: 0,
          patch: 0
        ).encoded.to_i,
        encoded_upper_bound: Versioning::SemanticVersion.new(
          major: 4,
          minor: 0,
          patch: 0
        ).encoded.to_i,
        created_at: 30.seconds.ago,
        updated_at: 15.seconds.ago,
      })

      described_class.sync

      expect(described_class.count).to eq 1
      expect(described_class.where(package_name: "rake")).to be_empty
    end

    it "ignores withdrawn vulnerabilities" do
      described_class.sync

      expect(described_class.where(package_name: "withdrawn-rails")).to be_empty
    end

    it "ignores requirements that fail to parse and reports them to failbot" do
      vulnerability.vulnerable_version_ranges.create!({
        affects:      "rails",
        ecosystem:    "RubyGems",
        requirements: "NOT VALID",
        fixed_in:     "5.1.0",
      })

      expect(Failbot).to receive(:report).with(VulnerableVersionRange::ParseError)

      described_class.sync
    end

    it "doesn't throw an error when range has an invalid ecosystem" do
      vulnerability.vulnerable_version_ranges.create!({
        affects:      "rake",
        ecosystem:    "TurboPascal", # Not present in Types::PackageManager
        requirements: "< 1.2.3",
      })

      described_class.sync

      expect(described_class.where(package_name: "rake")).to be_empty
    end

    it "doesn't sync a range missing the ecosystem" do
      vulnerability.vulnerable_version_ranges.create!({
        affects:      "rake",
        ecosystem:    nil,
        requirements: "< 1.2.3",
      })

      described_class.sync

      expect(described_class.where(package_name: "rake")).to be_empty
    end

    it "doesn't sync invalid vulnerabilities" do
      vulnerability.vulnerable_version_ranges.create!({
        affects:      "rake",
        ecosystem:    "RubyGems",
        requirements: "NOT VALID",
      })

      # Become one with Prod.
      expect(Failbot).to receive(:report)

      described_class.sync

      expect(described_class.where(package_name: "rake")).to be_empty
    end

    it "skips range item when it has no vulnerability" do
      VulnerableVersionRange::GitHubVulnerability.delete_all
      described_class.sync
      range = described_class.last
      expect(range).to eq nil
    end

    it "syncs vulnerability with named version" do
        VulnerableVersionRange::GitHubVulnerability.delete_all
        actions_vulnerability = VulnerableVersionRange::GitHubVulnerability.create!({
                                  severity: "critical",
                                  status: "published",
                                })

        actions_vulnerability.vulnerable_version_ranges.create!({
          affects: "actions/doing-stuff",
          ecosystem: "Actions",
          requirements: "= e945g5",
          fixed_in: "a789b878cd",
        })

      described_class.sync

      range = described_class.first
      expect(range.package_name).to eq "actions/doing-stuff"
      expect(range.version_range).to eq "= e945g5"
    end

    it "instruments timing" do
      expect { described_class.sync }.to have_instrumented_time("jobs.sync_vulnerabilities")
    end
  end
end
