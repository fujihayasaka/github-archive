require "spec_helper"
require "rails_helper"

module Versioning
  describe EncodedRequirement do
    describe "#encoded_bound" do
      it "returns encoded upper and lower bounds" do
        requirement = double({
          lower_bound?: true,
          lower_bound_inclusive?: true,
          lower_bound: SemanticVersion.new(major: 0, minor: 0, patch: 4),
          upper_bound?: true,
          upper_bound_inclusive?: true,
          upper_bound: SemanticVersion.new(major: 0, minor: 0, patch: 5)
        })

        expect(described_class.new(requirement).encoded_lower_bound)
          .to eq 0b000000000000000000000000000000000000000000000100
        expect(described_class.new(requirement).encoded_upper_bound)
          .to eq 0b000000000000000000000000000000000000000000000101
      end

      context "the lower bound is not inclusive" do
        # > 0.0.4 is equivalent to >= 0.0.5
        it "assumes the use of an inclusive operator and increments by 1" do
          requirement = double({
            lower_bound?: true,
            lower_bound_inclusive?: false,
            lower_bound: SemanticVersion.new(major: 0, minor: 0, patch: 4),
            upper_bound?: true,
            upper_bound_inclusive?: true,
            upper_bound: SemanticVersion.new(major: 0, minor: 0, patch: 5)
          })

          expect(described_class.new(requirement).encoded_lower_bound)
            .to eq 0b000000000000000000000000000000000000000000000101
          expect(described_class.new(requirement).encoded_upper_bound)
            .to eq 0b000000000000000000000000000000000000000000000101
        end
      end

      context "the upper bound is not inclusive" do
        # < 0.0.5 is equivalent to <= 0.0.4
        it "assumes the use of an inclusive operator and decrements by 1" do
          requirement = double({
            lower_bound?: true,
            lower_bound_inclusive?: true,
            lower_bound: SemanticVersion.new(major: 0, minor: 0, patch: 4),
            upper_bound?: true,
            upper_bound_inclusive?: false,
            upper_bound: SemanticVersion.new(major: 0, minor: 0, patch: 5)
          })

          expect(described_class.new(requirement).encoded_lower_bound)
            .to eq 0b000000000000000000000000000000000000000000000100
          expect(described_class.new(requirement).encoded_upper_bound)
            .to eq 0b000000000000000000000000000000000000000000000100
        end
      end

      it "subsitutes MAX for the upper bound when undefined" do
        requirement = double({
          lower_bound?: true,
          lower_bound_inclusive?: true,
          lower_bound: SemanticVersion.new(major: 0, minor: 0, patch: 4),
          upper_bound?: false,
        })

        expect(described_class.new(requirement).encoded_lower_bound)
          .to eq 0b000000000000000000000000000000000000000000000100
        expect(described_class.new(requirement).encoded_upper_bound)
          .to eq 0b111111111111111111111111111111111111111111111111
      end

      it "does not encode named versions" do
        requirement = double({
          lower_bound?: true,
          lower_bound_inclusive?: true,
          lower_bound: NamedVersion.new(name: "main"),
          upper_bound?: true,
          upper_bound_inclusive?: true,
          upper_bound: NamedVersion.new(name: "main")
        })

        expect { described_class.new(requirement).encoded_lower_bound }.to raise_error Versioning::NoEncodedVersionError
        expect { described_class.new(requirement).encoded_upper_bound }.to raise_error Versioning::NoEncodedVersionError
      end
    end
  end
end
