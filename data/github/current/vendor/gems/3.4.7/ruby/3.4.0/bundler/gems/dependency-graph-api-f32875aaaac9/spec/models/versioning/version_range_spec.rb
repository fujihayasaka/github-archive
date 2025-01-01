require "spec_helper"
require "rails_helper"
require "active_support"
require "active_support/core_ext"

module Versioning
  describe VersionRange do
    describe "#valid?" do
      it "is valid if the upper bound follows the lower bound" do
        expect(described_class.new(
          lower_bound: SemanticVersion.new(
            major: 5,
            minor: 0,
            patch: 0,
          ),
          upper_bound: SemanticVersion.new(
            major: 5,
            minor: 1,
            patch: 0,
          )
        )).to be_valid
      end

      it "is valid if the upper bound equals lower bound" do
        expect(described_class.new(
          lower_bound: SemanticVersion.new(
            major: 5,
            minor: 0,
            patch: 0,
          ),
          upper_bound: SemanticVersion.new(
            major: 5,
            minor: 0,
            patch: 0,
          )
        )).to be_valid
      end

      it "is valid if the upper bound is unbounded" do
        expect(described_class.new(
          lower_bound: SemanticVersion.new(
            major: 5,
            minor: 0,
            patch: 0,
          ),
          upper_bound: nil
        )).to be_valid
      end

      it "is valid if the lower bound is unbounded" do
        expect(described_class.new(
          lower_bound: nil,
          upper_bound: SemanticVersion.new(
            major: 5,
            minor: 0,
            patch: 0,
          )
        )).to be_valid
      end

      it "is invalid if the upper bound does not follow lower bound" do
        expect(described_class.new(
          lower_bound: SemanticVersion.new(
            major: 5,
            minor: 0,
            patch: 0,
          ),
          upper_bound: SemanticVersion.new(
            major: 4,
            minor: 9,
            patch: 0,
          )
        )).to_not be_valid
      end
    end
  end
end
