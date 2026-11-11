require "rails_helper"

module Queries
  describe PackageReleaseQuery do
    it "includes releases for the given package name and manager" do
      included = factory.given_package("react", "5.0.0", :rubygems).release
      excluded = factory.given_package("react", "5.0.0", :npm).release
      excluded = factory.given_package("httparty", "5.0.0", :rubygems).release

      query = described_class.new(
        package_name:    "react",
        package_manager: :rubygems,
      )

      expect(query.results).to eq [included]
    end

    it "handles missing packages" do
      query = described_class.new(
        package_name:    "react",
        package_manager: :rubygems,
      )

      expect(query.results).to be_empty
    end

    it "returns package releases with higher release numbers first" do
      releases = %w{ 5.0.0 5.0.0-beta 5.0.0-alpha 3.0.0 }

      releases.shuffle.each do |release|
        factory.given_package("react", release, :rubygems)
      end

      query = described_class.new(
        package_name:    "react",
        package_manager: :rubygems,
      )

      expect(query.results.map(&:parsed_version).map(&:to_s)).to eq releases
    end

    it "accepts a limit" do
      release_new = factory.given_package("react", "5.0.0", :rubygems).release
      release_old = factory.given_package("react", "3.0.0", :rubygems).release

      query = described_class.new(
        package_name:    "react",
        package_manager: :rubygems,
        limit:           1
      )

      expect(query.results).to eq [release_new]
    end

    it "scopes by requirements" do
      included = factory.given_package("react", "3.0.0", :rubygems).release
      excluded = factory.given_package("react", "5.0.0", :rubygems).release

      query = described_class.new(
        package_name:    "react",
        package_manager: :rubygems,
        requirements:    "< 5.0.0"
      )

      expect(query.results).to eq [included]
    end

    it "scopes by requirements of 4 part version strings" do
      excluded_1  = factory.given_package("react", "3.1.0.3", :rubygems).release
      excluded_2  = factory.given_package("react", "3.1.0.1", :rubygems).release
      excluded_3  = factory.given_package("react", "3.2.0", :rubygems).release
      excluded_4  = factory.given_package("react", "3.1.0", :rubygems).release
      included    = factory.given_package("react", "3.1.0.2", :rubygems).release

      query = described_class.new(
        package_name:    "react",
        package_manager: :rubygems,
        requirements:    "< 3.1.0.3, > 3.1.0.1"
      )

      expect(query.results).to eq [included]
    end

    it "allows compound requirements" do
      excluded = factory.given_package("react", "3.0.0", :rubygems).release
      included = factory.given_package("react", "3.5.0", :rubygems).release
      excluded = factory.given_package("react", "5.0.0", :rubygems).release

      query = described_class.new(
        package_name:    "react",
        package_manager: :rubygems,
        requirements:    "< 5.0.0, > 3.0.0"
      )

      expect(query.results).to eq [included]
    end

    it "allows multiple requirements" do
      excluded   = factory.given_package("react", "2.0.0", :rubygems).release
      included_1 = factory.given_package("react", "3.0.0", :rubygems).release
      included_2 = factory.given_package("react", "3.5.0", :rubygems).release

      query = described_class.new(
        package_name:    "react",
        package_manager: :rubygems,
        requirements:    "> 5.0.0 || >= 3.0.0"
      )

      expect(query.results).to eq [included_2, included_1]
    end

    it "filters out releases that match encoded but not semantically" do
      included = factory.given_package("react", "5.0.0", :rubygems).release
      excluded = factory.given_package("react", "5.0.0-beta", :rubygems).release

      query = described_class.new(
        package_name:    "react",
        package_manager: :rubygems,
        requirements:    ">= 5.0.0",
      )

      expect(query.results).to eq [included]
    end

    it "returns nothing if requirements don't match" do
      excluded = factory.given_package("react", "2.0.0", :rubygems).release
      excluded = factory.given_package("react", "3.0.0", :rubygems).release

      query = described_class.new(
        package_name:    "react",
        package_manager: :rubygems,
        requirements:    "> 5.0.0"
      )

      expect(query.results).to eq []
    end

    it "raises an exception when requirements are garbage" do
      excluded = factory.given_package("react", "2.0.0", :rubygems).release
      included = factory.given_package("react", "3.0.0", :rubygems).release

      query = described_class.new(
        package_name:      "react",
        package_manager:   :rubygems,
        requirements:      "GARBAGE",
        limit:             1
      )

      expect { query.results }
        .to raise_error(PackageReleaseQuery::InvalidRequirementsException)
    end

    it "defaults to the latest release with the `default_to_latest` option" do
      excluded = factory.given_package("react", "2.0.0", :rubygems).release
      included = factory.given_package("react", "3.0.0", :rubygems).release

      query = described_class.new(
        package_name:      "react",
        package_manager:   :rubygems,
        requirements:      "> 5.0.0",
        default_to_latest: true
      )

      expect(query.results).to eq [included]
    end

    it "return an empty array when `default_to_latest` is set and the package is missing" do
      query = described_class.new(
        package_name:      "react",
        package_manager:   :rubygems,
        requirements:      "> 5.0.0",
        default_to_latest: true
      )

      expect(query.results).to eq []
    end

    it "does not include unpublished packages by default" do
      unpublished = factory.given_package("react", "5.0.0", :rubygems).release
      unpublished.update!(unpublished_at: Time.now)
      published = factory.given_package("react", "5.0.1", :rubygems).release

      query = described_class.new(
        package_name: "react",
        package_manager: :rubygems,
      )

      expect(query.results).to eq [published]
    end

    it "returns unpublished packages when `include_unpublished` is set" do
      unpublished = factory.given_package("react", "5.0.0", :rubygems).release
      unpublished.update!(unpublished_at: Time.now)
      published = factory.given_package("react", "5.0.1", :rubygems).release

      query = described_class.new(
        package_name: "react",
        package_manager: :rubygems,
        include_unpublished: true,
      )

      expect(query.results).to eq [published, unpublished]
    end

    it "`default_to_latest` option value respects the `include_unpublished` option value" do
      published = factory.given_package("react", "5.0.0", :rubygems).release
      unpublished = factory.given_package("react", "5.0.1", :rubygems).release
      unpublished.update!(unpublished_at: Time.now)

      query = described_class.new(
        package_name: "react",
        package_manager: :rubygems,
        requirements: "=4.0.0",
        default_to_latest: true,
        include_unpublished: true,
      )

      expect(query.results).to eq [unpublished]
    end

    context "named versions" do
      it "scopes by requirements" do
        included1 = factory.given_package("actions/checkout", "3.0.0", :actions).release
        included2 = factory.given_package("actions/checkout", "main", :actions).release
        excluded = factory.given_package("actions/checkout", "2.0.0", :actions).release

        query = described_class.new(
          package_name:    "actions/checkout",
          package_manager: :actions,
          requirements:    ">= 3.0.0"
        )

        expect(query.results).to eq [included2, included1]
      end
    end
  end
end
