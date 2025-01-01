require "rails_helper"

module Versioning
  describe RequirementSet do
    describe "#contain?" do
      it "is true if all ranges on the right are entirely contained by a range on the left" do
        CSV.open(file_fixture("requirement_set_contain.csv")).each do |serialized_left, serialized_right, expected_to_contain|
          left = described_class.deserialize(serialized_left, allow_named_versions: false)
          right = described_class.deserialize(serialized_right, allow_named_versions: false)
          expected_to_contain = (expected_to_contain == "true")

          expect(left).to be_valid
          expect(right).to be_valid

          expect(left.contain?(right)).to eq(expected_to_contain), <<~MSG.squish
            Expected #{serialized_left.inspect}
            #{expected_to_contain ? "to" : "not to"}
            contain #{serialized_right.inspect}
            MSG
        end
      end

      context "named" do
        it "is true if any requirement on the right falls within a range on the left" do
          [
            ["= dev", "= dev", true],
            ["= dev", "= 1.4.0", false],
            ["= dev", "= main", false],
            ["= dev", "< 20.0.0", false],
            ["> 5.0.0", "= dev", true],
            ["> 5.0.0", "= main", true],
          ].each do |serialized_left, serialized_right, expected_to_contain|
            left = described_class.deserialize(serialized_left, allow_named_versions: true)
            right = described_class.deserialize(serialized_right, allow_named_versions: true)

            expect(left).to be_valid
            expect(right).to be_valid

            expect(left.contain?(right)).to eq(expected_to_contain), <<~MSG.squish
              Expected #{serialized_left.inspect}
              #{expected_to_contain ? "to" : "not to"}
              contain #{serialized_right.inspect}
              MSG
          end
        end
      end
    end
  end
end
