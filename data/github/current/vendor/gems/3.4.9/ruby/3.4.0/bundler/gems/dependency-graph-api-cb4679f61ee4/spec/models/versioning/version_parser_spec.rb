require "spec_helper"
require "rails_helper"
require "active_support"
require "active_support/core_ext"

module Versioning

  describe VersionParser do
    it "knows semantic version components" do
      expect(described_class.parse("0.1.0")).to eq SemanticVersion.new(
        major: 0,
        minor: 1,
        patch: 0
      )
    end

    it "knows named version string components" do
      expect(described_class.parse("main", allow_named_versions: true)).to eq GenericVersionParser.generate(
        allow_named_versions: true,
        primary_identifier: "main"
      )
    end

    it "defaults to semantic version if allows_named_versions is false" do
      expect(described_class.parse("0.1.0", allow_named_versions: false)).to eq SemanticVersion.new(
        major: 0,
        minor: 1,
        patch: 0,
      )
    end

    it "doesn't require a patch version" do
      expect(described_class.parse("0.1")).to eq SemanticVersion.new(
        major: 0,
        minor: 1,
        patch: 0
      )
    end

    it "handles versions with additional fields" do
      expect(described_class.parse("0.1.2.3.4")).to eq SemanticVersion.new(
        major: 0,
        minor: 1,
        patch: 2,
        additional_fields: [3, 4]
      )
    end

    it "handles prerelease versions" do
      # prereleases can be designated by a `-`
      expect(described_class.parse("1.100.22-beta")).to eq SemanticVersion.new(
        major: 1,
        minor: 100,
        patch: 22,
        prerelease: "beta"
      )

      # or they can be specified by having a letter
      expect(described_class.parse("6.0.0.beta3")).to eq SemanticVersion.new(
        major: 6,
        minor: 0,
        patch: 0,
        prerelease: "beta3"
      )

      expect(described_class.parse("6.0.0.1.beta3")).to eq SemanticVersion.new(
        major: 6,
        minor: 0,
        patch: 0,
        additional_fields: [1],
        prerelease: "beta3"
      )

      expect(described_class.parse("1.0.0-rc1")).to eq SemanticVersion.new(
        major: 1,
        minor: 0,
        patch: 0,
        prerelease: "rc1"
      )

      # we can also have metadata
      expect(described_class.parse("1.0.0-rc1+b.1056")).to eq SemanticVersion.new(
        major: 1,
        minor: 0,
        patch: 0,
        prerelease: "rc1",
        metadata: "b.1056"
      )

      expect(described_class.parse("2.0.3-pre-alpha.1.2+b.1056+q"))
        .to eq SemanticVersion.new(
          major: 2,
          minor: 0,
          patch: 3,
          prerelease: "pre-alpha.1.2",
          metadata: "b.1056+q"
        )

      expect(described_class.parse("2.0.3.4.5-pre-alpha.1.2+b.1056+q"))
        .to eq SemanticVersion.new(
          major: 2,
          minor: 0,
          patch: 3,
          additional_fields: [4, 5],
          prerelease: "pre-alpha.1.2",
          metadata: "b.1056+q"
        )

      expect(described_class.parse("1.0.0.beta.1"))
        .to eq SemanticVersion.new(
          major: 1,
          minor: 0,
          patch: 0,
          prerelease: "beta.1",
        )
    end

    it "handles prefixes in sem versions" do
      expect(described_class.parse("v5.0.0")).to eq SemanticVersion.new(
        major: 5,
        minor: 0,
        patch: 0,
      )

      expect(described_class.parse("v 5.0.0")).to eq SemanticVersion.new(
        major: 5,
        minor: 0,
        patch: 0,
      )
    end

    it "handles garbage in sem versions" do
      expect(described_class.parse("TRASH")).to_not be_parseable
      expect(described_class.parse("5  .  0   .  9")).to_not be_parseable
    end

    it "sorts unparseable versions last" do
      v1 = described_class.parse("v 5.0.0")
      v2 = described_class.parse("TRASH")

      expect(v1 > v2).to be_truthy
      expect(v2 < v1).to be_truthy

      v1 = described_class.parse("TRASH")
      v2 = described_class.parse("TRASH")

      expect(v1 < v2).to be_truthy
    end

    it "deals with wildcards in sem versions" do
      point_x = described_class.parse("1.x")
      expect(point_x).to eq SemanticVersion.new(
        major: 1,
        minor: Float::INFINITY,
        patch: Float::INFINITY,
      )

      point_asterisk = described_class.parse("2.*")
      expect(point_asterisk).to eq SemanticVersion.new(
        major: 2,
        minor: Float::INFINITY,
        patch: Float::INFINITY,
      )

      more_point_asterisk = described_class.parse("6.4.*")
      expect(more_point_asterisk).to eq SemanticVersion.new(
        major: 6,
        minor: 4,
        patch: Float::INFINITY,
      )
    end

    it "handles prefixes in named versions" do
      expect(described_class.parse("v1.0.1", allow_named_versions: true)).to eq GenericVersionParser.generate(
        allow_named_versions: true,
        primary_identifier: "v1.0.1"
      )
    end

    it "handles garbage in named versions" do
      expect(described_class.parse("5  .  0   .  9", allow_named_versions: true)).to_not be_parseable
      expect(described_class.parse("fo * sk!!**$", allow_named_versions: true)).to_not be_parseable
    end
  end
end
