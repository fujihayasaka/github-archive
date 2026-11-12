require "rails_helper"
require "db_helpers"

describe VulnerableVersionRange do
  before do
    reset_vulnerability_data
  end

  describe ".sync" do
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

    it "copies ranges from the dotcom database and sets owner fields correctly" do
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
      expect(range.owner_business_id).to be_nil
      expect(range.owner_org_id).to be_nil
      expect(range.open_source?).to be_truthy
      expect(range.innersource?).to be_falsey
    end

    it "syncs innersource vulnerability with owner_business_id set" do
      vulnerability.vulnerable_version_ranges.create!({
        affects: "rails-business",
        ecosystem: "RubyGems",
        requirements: ">= 5.0.0, < 5.1.0",
        fixed_in: "5.1.0",
      })
      vulnerability.update!(owner_business_id: 42)
      vulnerability.update!(visibility_scope: :innersource)
      described_class.sync
      range = described_class.find_by(package_name: "rails-business")
      expect(range.owner_business_id).to eq 42
      expect(range.owner_org_id).to be_nil
      expect(range.innersource?).to be_truthy
      expect(range.open_source?).to be_falsey
    end

    it "syncs innersource vulnerability with owner_org_id set" do
      vulnerability.vulnerable_version_ranges.create!({
        affects: "rails-org",
        ecosystem: "RubyGems",
        requirements: ">= 5.0.0, < 5.1.0",
        fixed_in: "5.1.0",
      })
      vulnerability.update!(owner_org_id: 99)
      vulnerability.update!(visibility_scope: :innersource)
      described_class.sync
      range = described_class.find_by(package_name: "rails-org")
      expect(range.owner_org_id).to eq 99
      expect(range.owner_business_id).to be_nil
      expect(range.innersource?).to be_truthy
      expect(range.open_source?).to be_falsey
    end

    it "does not sync vulnerability with both owner_business_id and owner_org_id set" do
      vulnerability.vulnerable_version_ranges.create!({
        affects: "rails-both",
        ecosystem: "RubyGems",
        requirements: ">= 5.0.0, < 5.1.0",
        fixed_in: "5.1.0",
      })
      vulnerability.update!(owner_business_id: 100, owner_org_id: 101)
      described_class.sync
      expect(described_class.where(package_name: "rails-both")).to be_empty
    end

    it "does not sync vulnerability marked as open_source with either owner_business_id or owner_org_id set" do
      vulnerability.vulnerable_version_ranges.create!({
        affects: "rails-both",
        ecosystem: "RubyGems",
        requirements: ">= 5.0.0, < 5.1.0",
        fixed_in: "5.1.0",
      })
      vulnerability.update!(visibility_scope: :open_source, owner_business_id: 100, owner_org_id: nil)
      described_class.sync
      expect(described_class.where(package_name: "rails-both")).to be_empty

      vulnerability.update!(visibility_scope: :open_source, owner_business_id: nil, owner_org_id: 101)
      described_class.sync
      expect(described_class.where(package_name: "rails-both")).to be_empty
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

  describe ".visible_to" do
    let!(:public_vuln) do
      factory.given_vulnerable_version_range(
        github_id: 100,
        package_name: "rails",
        package_manager: Types::PackageManager[:rubygems],
        version_range: ">= 5.0.0, < 5.1.0",
        visibility_scope: :open_source,
        owner_business_id: nil,
        owner_org_id: nil
      )
    end

    let!(:business_vuln) do
      factory.given_vulnerable_version_range(
        github_id: 101,
        package_name: "rails-business",
        package_manager: Types::PackageManager[:rubygems],
        version_range: ">= 5.0.0, < 5.1.0",
        visibility_scope: :innersource,
        owner_business_id: 42,
        owner_org_id: nil
      )
    end

    let!(:org_vuln) do
      factory.given_vulnerable_version_range(
        github_id: 102,
        package_name: "rails-org",
        package_manager: Types::PackageManager[:rubygems],
        version_range: ">= 5.0.0, < 5.1.0",
        visibility_scope: :innersource,
        owner_business_id: nil,
        owner_org_id: 99
      )
    end

    let!(:both_owners_vuln) do
      factory.given_vulnerable_version_range(
        github_id: 103,
        package_name: "rails-other",
        package_manager: Types::PackageManager[:rubygems],
        version_range: ">= 5.0.0, < 5.1.0",
        visibility_scope: :innersource,
        owner_business_id: 100,
        owner_org_id: 101
      )
    end

    it "returns only public vulns when .open_source scope is used" do
      results = VulnerableVersionRange.open_source
      expect(results).to contain_exactly(public_vuln)
    end

    it "returns only public vulns if no business_id or org_id is given" do
      results = VulnerableVersionRange.visible_to(business_id: nil, org_id: nil)
      expect(results).to contain_exactly(public_vuln)
    end

    it "returns public and business vulns if business_id is given" do
      results = VulnerableVersionRange.visible_to(business_id: 42, org_id: nil)
      expect(results).to contain_exactly(public_vuln, business_vuln)
    end

    it "returns public and org vulns if org_id is given" do
      results = VulnerableVersionRange.visible_to(business_id: nil, org_id: 99)
      expect(results).to contain_exactly(public_vuln, org_vuln)
    end

    it "returns public, business, and org vulns if both ids are given" do
      results = VulnerableVersionRange.visible_to(business_id: 42, org_id: 99)
      expect(results).to contain_exactly(public_vuln, business_vuln, org_vuln)
    end

    # Monolith enforces the rule that a vulnerability cannot be owned by both a business
    # and an org, so we should not return vulnerabilities that violate this rule.
    it "doesn't return vulns where both org and business ids are set" do
      results = VulnerableVersionRange.visible_to(business_id: 100, org_id: 101)
      expect(results).to contain_exactly(public_vuln)
    end

    it "does not return vulns for other business/org ids" do
      results = VulnerableVersionRange.visible_to(business_id: 1, org_id: 2)
      expect(results).to contain_exactly(public_vuln)
    end
  end
end
