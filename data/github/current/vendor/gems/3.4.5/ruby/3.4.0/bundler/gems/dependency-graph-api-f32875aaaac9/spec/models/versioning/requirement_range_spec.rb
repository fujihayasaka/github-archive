require "spec_helper"
require "rails_helper"
require "active_support"
require "active_support/core_ext"

module Versioning
  describe RequirementRange do

    describe "#min_upper_bound" do
      context "semantic versions" do
        it "returns the requirement with the min upper bound" do
          range = described_class.new([
            Requirement.new("=", "1.1.0", allow_named_versions: false),
            Requirement.new("=", "1.0.0", allow_named_versions: false),
          ])

          expect(range.min_upper_bound).to eq(Requirement.new("=", "1.0.0", allow_named_versions: false))
        end

        it "treats a requirement lacking an upper bound as greater than a bounded requirement" do
          range = described_class.new([
            Requirement.new("=", "1.1.0", allow_named_versions: false),
            Requirement.new("~>", "1.0.0", allow_named_versions: false),
            Requirement.new(">", "1.0.0", allow_named_versions: false),
          ])

          expect(range.min_upper_bound).to eq(Requirement.new("~>", "1.0.0", allow_named_versions: false))
        end

        it "treats an inclusive upper bound as greater than an exclusive upper bound" do
          range = described_class.new([
            Requirement.new("<=", "1.0.0", allow_named_versions: false),
            Requirement.new("<", "1.0.0", allow_named_versions: false),
          ])

          expect(range.min_upper_bound).to eq(Requirement.new("<", "1.0.0", allow_named_versions: false))
        end

        it "handles identical requirements" do
          range = described_class.new([
            Requirement.new("<=", "1.0.0", allow_named_versions: false),
            Requirement.new("<", "1.0.0", allow_named_versions: false),
            Requirement.new("<=", "1.0.0", allow_named_versions: false),
            Requirement.new("<", "1.0.0", allow_named_versions: false),
          ])

          expect(range.min_upper_bound).to eq(Requirement.new("<", "1.0.0", allow_named_versions: false))
        end
      end

      context "named versions" do
        it "returns the requirement with the min upper bound" do
          range = described_class.new([
            Requirement.new("=", "1.1.0", allow_named_versions: true),
            Requirement.new("=", "main", allow_named_versions: true),
          ])

          expect(range.min_upper_bound).to eq(Requirement.new("=", "1.1.0", allow_named_versions: true))
        end

        it "treats a requirement lacking an upper bound as greater than a bounded requirement" do
          range = described_class.new([
            Requirement.new(">", "1.1.0", allow_named_versions: true),
            Requirement.new("=", "main", allow_named_versions: true),
          ])

          expect(range.min_upper_bound).to eq(Requirement.new("=", "main", allow_named_versions: true))
        end
      end

    end

    describe "#exact_version" do
      context "semantic versions" do
        it "returns the exact version for a requirement range that has one" do
          range = described_class.new([
            Requirement.new("=", "1.1.0", allow_named_versions: false),
          ])
          expect(range.exact_version).to eq("1.1.0")
        end

        it "returns `nil` for a requirement range that isn't exact" do
          range = described_class.new([
            Requirement.new(">=", "1.1.0", allow_named_versions: false),
          ])
          expect(range.exact_version).to eq(nil)
        end

        it "returns `nil` for a requirement range that has more than one requirement" do
          range = described_class.new([
            Requirement.new("=", "1.1.0", allow_named_versions: false),
            Requirement.new("=", "1.2.0", allow_named_versions: false),
          ])
          expect(range.exact_version).to eq(nil)
        end
      end

      context "named versions" do
        it "returns the exact version for a requirement range that has one" do
          range = described_class.new([
            Requirement.new("=", "dev", allow_named_versions: true),
          ])
          expect(range.exact_version).to eq("dev")
        end

        it "returns `nil` for a requirement range that has more than one requirement" do
          range = described_class.new([
            Requirement.new("=", "dev", allow_named_versions: true),
            Requirement.new("=", "prod", allow_named_versions: true),
          ])
          expect(range.exact_version).to eq(nil)
        end
      end
    end
  end
end
