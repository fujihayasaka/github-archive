require "spec_helper"
require "rails_helper"

module Versioning
  describe EncodedVersion do
    describe "#to_i" do
      it "packs major, minor and patch version into a 48 bit INT" do
        version = SemanticVersion.new(
          major: 2,
          minor: 5,
          patch: 60
        )
        encoded = 0b000000000000001000000000000000000000000000000000 + # top 16    - major
                  0b000000000000000000000000000001010000000000000000 + # middle 16 - minor
                  0b000000000000000000000000000000000000000000111100   # bottom 16 - patch

        expect(version.encoded.to_i.to_s(2)).to eq(encoded.to_s(2))
      end

      it "handles 2^16 versions" do
        version = SemanticVersion.new(
          major: 2,
          minor: (2 ** 16) - 1,
          patch: 60
        )
        encoded = 0b000000000000001000000000000000000000000000000000 +
                  0b000000000000000011111111111111110000000000000000 +
                  0b000000000000000000000000000000000000000000111100

        expect(version.encoded.to_i.to_s(2)).to eq(encoded.to_s(2))
      end

      it "caps versions 2^16" do
        version = SemanticVersion.new(
          major: 2,
          minor: (2 ** 16) + 10,
          patch: 60
        )
        encoded = 0b000000000000001000000000000000000000000000000000 +
                  0b000000000000000011111111111111110000000000000000 +
                  0b000000000000000000000000000000000000000000111100

        expect(version.encoded.to_i.to_s(2)).to eq(encoded.to_s(2))
      end

      it "thinks that infinity is less than 2^16" do
        version = SemanticVersion.new(
          major: 2,
          minor: 2,
          patch: Float::INFINITY
        )
        encoded = 0b000000000000001000000000000000000000000000000000 +
                  0b000000000000000000000000000000100000000000000000 +
                  0b000000000000000000000000000000001111111111111111

        expect(version.encoded.to_i.to_s(2)).to eq(encoded.to_s(2))
      end

      it "does not encode named versions" do
        version = NamedVersion.new(
          name: "main",
        )

        expect { version.encoded.to_i }.to raise_error NoEncodedVersionError
      end
    end
  end
end
