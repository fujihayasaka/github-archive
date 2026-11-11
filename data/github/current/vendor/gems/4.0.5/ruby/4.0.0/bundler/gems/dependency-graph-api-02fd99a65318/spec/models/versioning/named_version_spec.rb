require "spec_helper"
require "rails_helper"
require "active_support"
require "active_support/core_ext"

module Versioning
  describe NamedVersion do
    describe "<=>" do
      it "sorts by alphabetical order" do
        a = NamedVersion.new(
          name: "a_version",
        )
        b = NamedVersion.new(
          name: "b_version",
        )
        c = NamedVersion.new(
          name: "c_version",
        )

        expect([a, c, b].sort).to eq [a, b, c]
      end

      it "sorts semantic versions before named versions" do
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
        v_main = NamedVersion.new(
          name: "main",
        )
        v_dev = NamedVersion.new(
          name: "dev",
        )

        expect([v_main, v_dev, v2, v1].sort).to eq [v1, v2, v_dev, v_main]
      end

      it "treats versions with the same components as equal" do
        v1 = NamedVersion.new(
          name: "35bafb1ce99aef3ab068afbaabae8f21fd9b9f02d3a9442e364fa92c0b3eeef0",
        )
        v2 = NamedVersion.new(
          name: "35bafb1ce99aef3ab068afbaabae8f21fd9b9f02d3a9442e364fa92c0b3eeef0",
        )

        expect(v1 <=> v2).to be_zero
      end

      it "sorts named versions as smaller than an unbounded upper bound" do
        infinity = SemanticVersion.new(
          major: Float::INFINITY,
          minor: 0,
          patch: 0,
        )
        main = NamedVersion.new(
          name: "main",
        )

        expect([infinity, main].sort).to eq [main, infinity]
      end
    end

    describe "==" do
      it "understands equality correctly" do
        version_main = NamedVersion.new(
          name: "main",
        )
        version_main2 = NamedVersion.new(
          name: "main",
        )
        version_dev = NamedVersion.new(
          name: "dev",
        )

        expect(version_main == version_main2).to be true
        expect(version_main == version_dev).to be false
      end

      it "returns false when comparing to a semantic version" do
        semantic_version = SemanticVersion.new(
          major: 2,
          minor: 0,
          patch: 0,
        )
        named_version = NamedVersion.new(
          name: "main",
        )

        expect(semantic_version == named_version).to be false
      end
    end
  end
end
