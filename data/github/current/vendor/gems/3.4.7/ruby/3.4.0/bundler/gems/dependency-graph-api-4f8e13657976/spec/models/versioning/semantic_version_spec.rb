require "spec_helper"
require "rails_helper"
require "active_support"
require "active_support/core_ext"

module Versioning
  describe SemanticVersion do
    describe "<=>" do
      it "sorts by major version number" do
        v1 = SemanticVersion.new(
          major: 1,
          minor: 0,
          patch: 0,
        )
        v2 = SemanticVersion.new(
          major: 2,
          minor: 0,
          patch: 0,
        )
        v3 = SemanticVersion.new(
          major: 3,
          minor: 0,
        )

        expect([v3, v2, v1].sort).to eq [v1, v2, v3]
      end

      it "sorts by minor version number" do
        v1 = SemanticVersion.new(
          major: 0,
          minor: 1,
          patch: 0,
        )
        v2 = SemanticVersion.new(
          major: 0,
          minor: 2,
          patch: 0,
        )

        expect([v2, v1].sort).to eq [v1, v2]
      end

      it "sorts by patch version number" do
        v1 = SemanticVersion.new(
          major: 0,
          minor: 0,
          patch: 1,
        )
        v2 = SemanticVersion.new(
          major: 0,
          minor: 0,
          patch: 2,
        )

        expect([v2, v1].sort).to eq [v1, v2]
      end

      it "sorts by additional_fields version components" do
        v1 = SemanticVersion.new(
          major: 5,
          minor: 2,
          patch: 1,
        )
        v2 = SemanticVersion.new(
          major: 5,
          minor: 2,
          patch: 2,
        )
        v3 = SemanticVersion.new(
          major: 5,
          minor: 2,
          patch: 2,
          additional_fields: [1]
        )
        v4 = SemanticVersion.new(
          major: 5,
          minor: 2,
          patch: 2,
          additional_fields: [1, 1]
        )
        v5 = SemanticVersion.new(
          major: 5,
          minor: 2,
          patch: 2,
          additional_fields: [1, 2]
        )
         expect([v5, v4, v3, v2, v1].sort).to eq [v1, v2, v3, v4, v5]
      end

      it "sorts by prerelease number" do v1 = SemanticVersion.new(
          major:      1,
          minor:      0,
          patch:      0,
          prerelease: "alpha",
        )
        v2 = SemanticVersion.new(
          major:      1,
          minor:      0,
          patch:      0,
          prerelease: "beta",
        )

        expect([v2, v1].sort).to eq [v1, v2]
      end

      it "sorts by prerelease number" do
        v1 = SemanticVersion.new(
          major:      1,
          minor:      0,
          patch:      0,
          prerelease: "alpha",
        )
        v2 = SemanticVersion.new(
          major:      1,
          minor:      0,
          patch:      0,
          prerelease: "beta",
        )

        expect([v2, v1].sort).to eq [v1, v2]
      end

      it "treats versions with the same components as equal" do
        v1 = SemanticVersion.new(
          major: 1,
          minor: 0,
          patch: 0,
        )
        v2 = SemanticVersion.new(
          major: 1,
          minor: 0,
          patch: 0,
        )

        expect(v1 <=> v2).to be_zero

        v3 = SemanticVersion.new(
          major:      1,
          minor:      0,
          patch:      0,
          prerelease: "beta",
        )
        v4 = SemanticVersion.new(
          major:      1,
          minor:      0,
          patch:      0,
          prerelease: "beta",
        )

        expect(v3 <=> v4).to be_zero
      end

      it "supports prerelease sorting semantics" do
        # From semver.org
        # Precedence [is] determined by comparing each dot separated identifier
        # from left to right until a difference is found as follows:
        # - Identifiers consisting of only digits are compared numerically and
        #   identifiers with letters or hyphens are compared lexically in ASCII
        #   sort order.
        # - Numeric identifiers always have lower precedence than non-numeric
        #   identifiers.
        # - A larger set of pre-release fields has a higher precedence than a
        #   smaller set, if all of the preceding identifiers are equal.
        v1 = SemanticVersion.new(
          major:      1,
          minor:      0,
          patch:      0,
          prerelease: "alpha",
        )
        v2 = SemanticVersion.new(
          major:      1,
          minor:      0,
          patch:      0,
          prerelease: "alpha.1",
        )
        v3 = SemanticVersion.new(
          major:      1,
          minor:      0,
          patch:      0,
          prerelease: "alpha.beta",
        )
        v4 = SemanticVersion.new(
          major:      1,
          minor:      0,
          patch:      0,
          prerelease: "beta",
        )
        v5 = SemanticVersion.new(
          major:      1,
          minor:      0,
          patch:      0,
          prerelease: "beta.2",
        )
        v6 = SemanticVersion.new(
          major:      1,
          minor:      0,
          patch:      0,
          prerelease: "beta.11",
        )
        v7 = SemanticVersion.new(
          major:      1,
          minor:      0,
          patch:      0,
          prerelease: "rc.1",
        )
        v8 = SemanticVersion.new(
          major:      1,
          minor:      0,
          patch:      0,
        )

        expect([v8, v7, v6, v5, v4, v3, v2, v1].sort)
          .to eq [v1, v2, v3, v4, v5, v6, v7, v8]
      end
    end
  end
end
