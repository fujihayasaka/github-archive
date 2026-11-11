# frozen_string_literal: true

require "rails_helper"
require "ecosystems"

RSpec.describe Advisorydb do
  describe ".to_advisorydb_ecosystem" do
    it "returns the correct ecosystem for known package managers" do
      expect(described_class.to_advisorydb_ecosystem(PackageManagers::BUNDLER)).to eq(:ECOSYSTEM_RUBYGEMS)
      expect(described_class.to_advisorydb_ecosystem(PackageManagers::NPM_AND_YARN)).to eq(:ECOSYSTEM_NPM)
      expect(described_class.to_advisorydb_ecosystem(PackageManagers::MAVEN)).to eq(:ECOSYSTEM_MAVEN)
      expect(described_class.to_advisorydb_ecosystem(PackageManagers::GO_MODULES)).to eq(:ECOSYSTEM_GO)
      expect(described_class.to_advisorydb_ecosystem(PackageManagers::GITHUB_ACTIONS)).to eq(:ECOSYSTEM_ACTIONS)
      expect(described_class.to_advisorydb_ecosystem(PackageManagers::PUB)).to eq(:ECOSYSTEM_PUB)
      expect(described_class.to_advisorydb_ecosystem(PackageManagers::CONDA)).to eq(:ECOSYSTEM_CONDA)
      expect(described_class.to_advisorydb_ecosystem(PackageManagers::DENO)).to eq(:ECOSYSTEM_DENO)
      expect(described_class.to_advisorydb_ecosystem(PackageManagers::UV)).to eq(:ECOSYSTEM_UV)
    end

    it "raises an error for an unknown package manager" do
      expect { described_class.to_advisorydb_ecosystem("unknown") }.to raise_error(Advisorydb::EcosystemrNotFoundError)
    end
  end

  describe ".to_package_manager" do
    it "returns the correct package manager for known ecosystems" do
      expect(described_class.to_package_manager(:ECOSYSTEM_COMPOSER)).to eq(PackageManagers::COMPOSER)
      expect(described_class.to_package_manager(:ECOSYSTEM_PIP)).to eq(PackageManagers::PIP)
      expect(described_class.to_package_manager(:ECOSYSTEM_NUGET)).to eq(PackageManagers::NUGET)
      expect(described_class.to_package_manager(:ECOSYSTEM_RUST)).to eq(PackageManagers::CARGO)
      expect(described_class.to_package_manager(:ECOSYSTEM_ERLANG)).to eq(PackageManagers::HEX)
      expect(described_class.to_package_manager(:ECOSYSTEM_SWIFT)).to eq(PackageManagers::SWIFT)
      expect(described_class.to_package_manager(:ECOSYSTEM_DENO)).to eq(PackageManagers::DENO)
    end

    it "raises an error for an unknown ecosystem" do
      expect { described_class.to_package_manager("unknown") }.to raise_error(Advisorydb::PackageManagerNotFoundError)
    end
  end
end
