# frozen_string_literal: true

require "rails_helper"
require "github_helpers"

RSpec.describe GitHub::Twirp::Advisorydb, :vcr do
  let(:github_api_url) do
    "http://host.docker.internal:3000/api/v3/"
  end

  let(:twirp_client) do
    GitHub::Twirp::Client.new(
      github_api_url: github_api_url.to_s,
      hmac_key: "dependabotapihmac"
    )
  end

  let(:advisorydb_api) do
    described_class.new(
      client: twirp_client
    )
  end

  context "get advisories for packages" do
    let(:packages) do
      [
        { name: "test_package53", ecosystem: "ECOSYSTEM_ACTIONS" },
        { name: "test_package90", ecosystem: "ECOSYSTEM_COMPOSER" },
        { name: "test_package65", ecosystem: "ECOSYSTEM_ERLANG" },
        { name: "test_package94", ecosystem: "ECOSYSTEM_GO" },
        { name: "test_package49", ecosystem: "ECOSYSTEM_MAVEN" },
        { name: "test_package11", ecosystem: "ECOSYSTEM_NPM" },
        { name: "NONEXISTENT_PACKAGE", ecosystem: "ECOSYSTEM_NPM" },
        { name: "test_package21", ecosystem: "ECOSYSTEM_PIP" },
      ]
    end

    it "returns advisories for the given packages only" do
      advisories = advisorydb_api.request_advisories(packages: packages)

      expect(advisories.advisories).to be_present
      expect(advisories.advisories.count).to eq(7)

      expected_packages = packages.reject { |pkg| pkg[:name] == "NONEXISTENT_PACKAGE" }

      advisories.advisories.each do |advisory|
        advisory.vulnerable_version_ranges.each do |range|
          expect(expected_packages).to include(range.package)
        end
      end
    end

    it "returns no advisories when no packages are given" do
      expect do
        advisorydb_api.request_advisories(packages: [])
      end.to raise_error(GitHub::Twirp::Advisorydb::Error,
                         "Package list cannot be empty")
    end

    it "returns no advisories for non-existent packages only" do
      non_existent_packages = [
        { name: "NONEXISTENT_PACKAGE1", ecosystem: "ECOSYSTEM_NPM" },
        { name: "NONEXISTENT_PACKAGE2", ecosystem: "ECOSYSTEM_PIP" },
      ]

      advisories = advisorydb_api.request_advisories(packages: non_existent_packages)

      expect(advisories.advisories).to be_empty
    end

    it "raises an error when the endpoint is failing" do
      allow(advisorydb_api).to receive(:list_advisories).
        and_return(Twirp::ClientResp.new(error: Twirp::Error.internal("Internal server error")))

      expect do
        advisorydb_api.request_advisories(packages: packages)
      end.to raise_error(GitHub::Twirp::Advisorydb::Error,
                         "Failed to request advisories: Internal server error")
    end
  end
end
