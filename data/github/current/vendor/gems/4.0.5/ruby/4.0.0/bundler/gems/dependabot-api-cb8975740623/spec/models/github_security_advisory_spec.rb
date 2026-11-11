# typed: true
# frozen_string_literal: true

require "rails_helper"

AdvisoryAttributes = T.type_alias { T::Hash[Symbol, T.any(String, Array)] }

RSpec.describe GitHubSecurityAdvisory, type: :model do
  extend T::Sig

  subject(:advisory) { FactoryBot.build_stubbed(:github_security_advisory) }

  let(:repo_id) { 1234 }

  describe "validations" do
    it { is_expected.to be_valid }

    context "without a dependency name" do
      before { advisory.dependency_name = nil }

      it { is_expected.not_to be_valid }
    end

    context "without a package manager" do
      before { advisory.package_manager = nil }

      it { is_expected.not_to be_valid }
    end

    context "with an invalid package manager" do
      before { advisory.package_manager = "fedex" }

      it { is_expected.not_to be_valid }
    end

    context "without a ghsa_id" do
      before { advisory.ghsa_id = nil }

      it { is_expected.not_to be_valid }
    end

    context "with an invalid ghsa_id" do
      before { advisory.ghsa_id = "GHSA-1111-1111-1111" }

      it { is_expected.not_to be_valid }
    end

    context "with a GHIS id" do
      let(:advisory) { build_stubbed(:github_security_advisory, :innersource) }

      it { is_expected.to be_valid }

      context "with an invalid ghis_id" do
        before { advisory.ghsa_id = "GHIS-1111-1111-1111" }

        it { is_expected.not_to be_valid }
      end
    end
  end

  describe "#native_affected_versions" do
    subject(:native_affected_versions) { advisory.native_affected_versions }

    let(:affected_versions) { ["< 2.5.14", "> 2.5.0, <= 2.5.14", "= 3.1.12-beta.rc5"] }
    let(:package_manager) { "bundler" }

    let(:advisory) do
      FactoryBot.build_stubbed(
        :github_security_advisory,
        affected_versions: affected_versions,
        package_manager: package_manager,
      )
    end

    it { is_expected.to eq(affected_versions) }

    context "when there is a GitHub Security Advisory for NPM using bundler-like version notations" do
      let(:package_manager) { "npm_and_yarn" }

      it { is_expected.to eq(["< 2.5.14", "> 2.5.0 <= 2.5.14", "= 3.1.12-beta.rc5"]) }
    end
  end

  describe "#native_patched_versions" do
    subject(:native_patched_versions) { advisory.native_patched_versions }

    let(:patched_versions) { ["1.10.0"] }
    let(:advisory) do
      FactoryBot.build_stubbed(:github_security_advisory, patched_versions: patched_versions)
    end

    it { is_expected.to eq([]) }
  end

  context "class methods" do
    let(:package_manager) { "bundler" }
    let(:dependencies) { ["rails"] }
    let(:advisories_response) { FactoryBot.build_stubbed(:advisories_response) }

    before do
      allow(Dependabot::Application.advisorydb_client).to receive(:request_advisories).
        and_return(advisories_response)
    end

    describe ".fetch" do
      it "fetches advisories for the given package manager and dependencies" do
        result = described_class.fetch(PackageManagers::BUNDLER, dependencies, repo_id)
        expect_equal_advisory_attributes(advisories_response, result.first)
      end

      it "raises an error for unsupported package managers" do
        expect do
          described_class.fetch("unsupported_manager", dependencies, repo_id)
        end.to raise_error(GitHubSecurityAdvisory::PackageManagerNotSupported)
      end

      context "with a multi-ecosystem vulnerability response" do
        let(:advisories_response) { FactoryBot.build_stubbed(:advisories_response, :multi_ecosystem) }

        it "fetches and filters advisories for the given package manager and dependencies" do
          result = described_class.fetch(PackageManagers::BUNDLER, dependencies, repo_id)
          expect(result.count).to eq(1)
          expect_equal_advisory_attributes(advisories_response, result.first)
        end
      end

      context "with conda package manager" do
        let(:package_manager) { PackageManagers::CONDA }
        let(:dependencies) { ["numpy"] }

        it "fetches advisories for conda packages without error" do
          expect do
            described_class.fetch(package_manager, dependencies, repo_id)
          end.not_to raise_error
        end
      end

      context "with uv package manager" do
        let(:package_manager) { PackageManagers::UV }
        let(:dependencies) { ["requests"] }

        it "fetches advisories for uv packages without error" do
          expect do
            described_class.fetch(package_manager, dependencies, repo_id)
          end.not_to raise_error
        end
      end
    end

    describe ".from_advisorydb_advisories" do
      it "converts advisories from advisorydb format to GitHubSecurityAdvisory format" do
        expect(described_class).to receive(:from_advisorydb_advisory).
          with(advisories_response.advisories.first).and_call_original
        result = described_class.from_advisorydb_advisories(
          advisories_response.advisories, "ECOSYSTEM_RUBYGEMS", dependencies
        )

        expect(result).to be_an(Array)
        expect(result.count).to eq(1)
        expect(result.first).to be_a(described_class)
        expect_equal_advisory_attributes(advisories_response, result.first)
      end
    end

    describe ".from_advisorydb_advisory" do
      it "converts an advisory from advisorydb format to GitHubSecurityAdvisory format" do
        result = described_class.from_advisorydb_advisory(advisories_response.advisories.first)
        expect(result).to be_a(described_class)
        expect_equal_advisory_attributes(advisories_response, result)
      end
    end
  end

  private

  sig do
    params(advisory_response: GitHub::Twirp::Advisorydb::AdvisoriesResponse,
           github_security_advisory: GitHubSecurityAdvisory).void # rubocop:disable RSpec/DescribedClass
  end
  def expect_equal_advisory_attributes(advisory_response, github_security_advisory)
    advisory_attributes = extract_advisory_attributes_from_response(advisory_response.advisories.first)
    github_security_advisory_attributes = extract_advisory_attributes_from_advisorydb_advisory(github_security_advisory)

    expect(advisory_attributes).to eq(github_security_advisory_attributes)
  end

  sig do
    params(advisory_response: GitHub::Twirp::Advisorydb::Advisory).returns(AdvisoryAttributes)
  end
  def extract_advisory_attributes_from_response(advisory_response)
    vulnerability = advisory_response.vulnerable_version_ranges.first
    package_manager = Advisorydb.to_package_manager(vulnerability.package[:ecosystem])
    {
      ghsa_id: advisory_response.ghsa_id,
      package_manager:,
      dependency_name: vulnerability.package[:name],
      affected_versions: advisory_response.vulnerable_version_ranges.map(&:vulnerable_version_range),
      published_at: advisory_response.published_at.change(sec: 0),
      updated_at: advisory_response.updated_at.change(sec: 0),
    }
  end

  sig { params(advisory: GitHubSecurityAdvisory).returns(AdvisoryAttributes) } # rubocop:disable RSpec/DescribedClass
  def extract_advisory_attributes_from_advisorydb_advisory(advisory)
    {
      ghsa_id: advisory.ghsa_id,
      package_manager: advisory.package_manager,
      dependency_name: advisory.dependency_name,
      affected_versions: advisory.affected_versions,
      published_at: advisory.published_at.change(sec: 0),
      updated_at: advisory.github_updated_at.change(sec: 0),
    }
  end
end
