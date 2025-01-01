require "spec_helper"
require "rails_helper"
require "active_support"
require "active_support/core_ext"

require_relative "../../../app/models/versioning/encoded_version"

module Versioning
  describe RequirementSet do
    describe ".deserialize" do
      it "deserializes a single requirement" do
        deserialized = described_class.deserialize("= 1.4.0", allow_named_versions: false)

        expect(deserialized).to be_valid
        expect(deserialized.ranges).to eq [
          [Requirement.new("=", "1.4.0", allow_named_versions: false)]
        ]
      end

      it "deserializes compound requirements" do
        deserialized = described_class.deserialize("> 1.4.0, < 2.0.0", allow_named_versions: false)

        expect(deserialized).to be_valid
        expect(deserialized.ranges).to match_array [
          [
            Requirement.new(">", "1.4.0", allow_named_versions: false),
            Requirement.new("<", "2.0.0", allow_named_versions: false),
          ]
        ]
      end

      it "deserializes OR requirements" do
        deserialized = described_class.deserialize("> 1.4.0 || < 2.0.0", allow_named_versions: false)

        expect(deserialized).to be_valid
        expect(deserialized.ranges).to match_array [
          [Requirement.new(">", "1.4.0", allow_named_versions: false)],
          [Requirement.new("<", "2.0.0", allow_named_versions: false)],
        ]
      end

      it "throws away invalid requirements in a set" do
        deserialized = described_class.deserialize("> 1.4.0, <", allow_named_versions: false)

        expect(deserialized).to be_valid
        expect(deserialized.ranges).to eq [
          [Requirement.new(">", "1.4.0", allow_named_versions: false)],
        ]
      end

      it "is invalid if there are no requirements" do
        deserialized = described_class.deserialize("= ", allow_named_versions: false)

        expect(deserialized).to_not be_valid
        expect(deserialized.ranges).to eq [[]]
      end

      it "yields invalid requirements" do
        described_class.deserialize("~> 1.4.0 || > 2.4.0, = ", allow_named_versions: false, **{
          on_error: ->(invalid) { @output = invalid }
        })
        expect(@output).to eq "> 2.4.0, = "
      end

      it "deserializes compound requirements" do
        deserialized = described_class.deserialize("> 1.4.0, < 2.0.0", allow_named_versions: false)

        expect(deserialized).to be_valid
        expect(deserialized.ranges).to match_array [
          [
            Requirement.new(">", "1.4.0", allow_named_versions: false),
            Requirement.new("<", "2.0.0", allow_named_versions: false),
          ]
        ]
      end

      it "deserializes ref requirements" do
        deserialized = described_class.deserialize("= project-branch, < 2.0.0", allow_named_versions: true)

        expect(deserialized).to be_valid
        expect(deserialized.ranges).to match_array [
          [
            Requirement.new("=", "project-branch", allow_named_versions: false),
            Requirement.new("<", "2.0.0", allow_named_versions: false),
          ]
        ]
      end
    end

    describe "#serialize" do
      it "stringifies the requirements" do
        single = described_class.new(
          ranges: [[Requirement.new(">", "1.4.0", allow_named_versions: false)]],
          allow_named_versions: false,
        )
        compound = described_class.new(
          ranges: [[Requirement.new(">", "1.4.0", allow_named_versions: false),
                    Requirement.new("<", "2.0.0", allow_named_versions: false)]],
          allow_named_versions: false,
        )
        multiple = described_class.new(
          ranges: [
            [Requirement.new(">", "1.4.0", allow_named_versions: false),
             Requirement.new("<", "2.0.0", allow_named_versions: false)],
            [Requirement.new("=", "5.0.0", allow_named_versions: false)],
          ], allow_named_versions: false
        )

        expect(single.serialize).to eq "> 1.4.0"
        expect(compound.serialize).to eq "> 1.4.0,< 2.0.0"
        expect(multiple.serialize).to eq "> 1.4.0,< 2.0.0 || = 5.0.0"
      end

      it "handles wildcard requirements" do
        empty = described_class.deserialize(nil, allow_named_versions: false)
        blank = described_class.deserialize("  ", allow_named_versions: false)

        expect(empty).to be_valid
        expect(blank).to be_valid
        expect(empty.serialize).to eq ""
        expect(blank.serialize).to eq ""
      end

      it "stringifies ref requirements" do
        single = described_class.new(
          ranges: [[Requirement.new("=", "main", allow_named_versions: true)]],
          allow_named_versions: false

        )
        compound = described_class.new(
          ranges: [[Requirement.new(">", "1.4.0", allow_named_versions: true), Requirement.new("=", "new-project", allow_named_versions: true)]],
          allow_named_versions: false
        )
        multiple = described_class.new(
          ranges: [
            [Requirement.new(">", "1.4.0", allow_named_versions: true), Requirement.new("=", "main", allow_named_versions: true)],
            [Requirement.new("=", "dev", allow_named_versions: true)],
          ], allow_named_versions: false
        )

        expect(single.serialize).to eq "= main"
        expect(compound.serialize).to eq "> 1.4.0,= new-project"
        expect(multiple.serialize).to eq "> 1.4.0,= main || = dev"
      end
    end

    describe "#encoded_lower_bound" do
      it "returns the lowest possible version in the ranges" do
        single = described_class.new(
          ranges: [[Requirement.new(">", "1.4.0", allow_named_versions: false)]], allow_named_versions: false
        )

        expect(single.encoded_lower_bound).to eq SemanticVersion.new(
          major: 1,
          minor: 4,
          patch: 1
        ).encoded.to_i

        compound = described_class.new(
          ranges: [
            [Requirement.new(">", "1.4.0", allow_named_versions: false),
             Requirement.new("<", "2.0.0", allow_named_versions: false)]
          ], allow_named_versions: false
        )

        expect(compound.encoded_lower_bound).to eq SemanticVersion.new(
          major: 1,
          minor: 4,
          patch: 1
        ).encoded.to_i

        multiple = described_class.new(
          ranges: [
            [Requirement.new(">", "1.4.0", allow_named_versions: false),
             Requirement.new("<", "2.0.0", allow_named_versions: false)],
            [Requirement.new("=", "1.0.0", allow_named_versions: false)],
          ], allow_named_versions: false
        )

        expect(multiple.encoded_lower_bound).to eq SemanticVersion.new(
          major: 1,
          minor: 0,
          patch: 0
        ).encoded.to_i
      end

      it "skips named versions in range that cannot be encoded" do
        single = described_class.new(
          ranges: [[Requirement.new("=", "dev", allow_named_versions: true)]],
          allow_named_versions: false
        )

        compound = described_class.new(
          ranges: [
            [Requirement.new(">", "1.4.0", allow_named_versions: true), Requirement.new("=", "dev", allow_named_versions: true)]
          ], allow_named_versions: false
        )

        expect(single.encoded_lower_bound).to be_nil
        expect(compound.encoded_lower_bound).to be_nil
      end
    end

    describe "#encoded_upper_bound" do
      it "returns the highest possible version in the ranges" do
        single = described_class.new(
          ranges: [[Requirement.new("<", "1.4.0", allow_named_versions: false)]],
          allow_named_versions: false
        )

        expect(single.encoded_upper_bound).to eq SemanticVersion.new(
          major: 1,
          minor: 3,
          patch: Float::INFINITY
        ).encoded.to_i

        compound = described_class.new(
          ranges: [
            [Requirement.new(">", "1.4.0", allow_named_versions: false),
             Requirement.new("<", "2.0.0", allow_named_versions: false)]
          ], allow_named_versions: false
        )

        expect(compound.encoded_upper_bound).to eq SemanticVersion.new(
          major: 1,
          minor: Float::INFINITY,
          patch: Float::INFINITY
        ).encoded.to_i

        multiple = described_class.new(
          ranges: [
            [Requirement.new(">", "1.4.0", allow_named_versions: false),
             Requirement.new("<=", "1.8.0", allow_named_versions: false),
             Requirement.new("<", "2.0.0", allow_named_versions: false)],
            [Requirement.new("=", "1.0.0", allow_named_versions: false)],
          ], allow_named_versions: false
        )

        expect(multiple.encoded_upper_bound).to eq SemanticVersion.new(
          major: 1,
          minor: 8,
          patch: 0
        ).encoded.to_i
      end

      it "skips named versions in range that cannot be encoded" do
        single = described_class.new(
          ranges: [[Requirement.new("=", "main", allow_named_versions: true)]],
          allow_named_versions: false
        )

        compound = described_class.new(
          ranges: [
            [Requirement.new("=", "main", allow_named_versions: true), Requirement.new("<=", "2.0.0", allow_named_versions: true)]
          ], allow_named_versions: false
        )

        expect(single.encoded_upper_bound).to be_nil
        expect(compound.encoded_upper_bound).to be_nil
      end
    end

    describe "#cover?" do
      context "semantic" do
        it "is true if all requirements in a range cover the version" do
          single = described_class.new(
            ranges: [
              [Requirement.new(">", "1.4.0", allow_named_versions: false)]
            ], allow_named_versions: false
          )
          compound = described_class.new(
            ranges: [
              [Requirement.new(">", "1.4.0", allow_named_versions: false),
               Requirement.new("<", "1.5.0", allow_named_versions: false)]
            ], allow_named_versions: false
          )

          expect(single.cover?(SemanticVersion.new(
            major: 1,
            minor: 4,
            patch: 5,
          ))).to be_truthy

          expect(compound.cover?(SemanticVersion.new(
            major: 1,
            minor: 4,
            patch: 5,
          ))).to be_truthy
        end

        it "is false if single requirement in a range does not cover the version" do
          single = described_class.new(
            ranges: [
              [Requirement.new(">", "1.4.0", allow_named_versions: false)]
            ], allow_named_versions: false
          )
          compound = described_class.new(
            ranges: [
              [Requirement.new(">", "1.4.0", allow_named_versions: false), Requirement.new("<", "1.5.0", allow_named_versions: false)]
            ], allow_named_versions: false
          )

          expect(single.cover?(SemanticVersion.new(
            major: 1,
            minor: 4,
            patch: 0,
          ))).to be_falsey

          expect(compound.cover?(SemanticVersion.new(
            major: 1,
            minor: 6,
            patch: 0,
          ))).to be_falsey
        end

        it "is true if at least one range covers the version" do
          multiple_ranges = described_class.new(
            ranges: [
              [Requirement.new("<", "1.4.0", allow_named_versions: false)],
              [Requirement.new("<", "1.5.0", allow_named_versions: false)]
            ], allow_named_versions: false
          )

          expect(multiple_ranges.cover?(SemanticVersion.new(
            major: 1,
            minor: 4,
            patch: 5,
          ))).to be_truthy

          expect(multiple_ranges.cover?(SemanticVersion.new(
            major: 1,
            minor: 6,
            patch: 0,
          ))).to be_falsey
        end
      end

      context "named" do
        it "is true if all requirements in a range cover the version" do
          req_set = described_class.new(
            ranges: [
              [Requirement.new("=", "main", allow_named_versions: true), Requirement.new(">", "1.4.0", allow_named_versions: false)]
            ],
            allow_named_versions: true,
          )

          expect(req_set.cover?(NamedVersion.new(
            name: "main",
          ))).to be_truthy
        end

        it "is false if single requirement in a range does not cover the version" do
          single = described_class.new(
            ranges: [
              [Requirement.new("<", "1.4.0", allow_named_versions: false)]
            ],
            allow_named_versions: false,
          )
          compound = described_class.new(
            ranges: [
              [Requirement.new("=", "main", allow_named_versions: false), Requirement.new("<", "1.5.0" , allow_named_versions: false)]
            ],
            allow_named_versions: true,
          )

          expect(single.cover?(NamedVersion.new(
            name: "main"
          ))).to be_falsey

          expect(compound.cover?(NamedVersion.new(
            name: "main"
          ))).to be_falsey
        end

        it "is true if at least one range covers the version" do
          multiple_ranges = described_class.new(
            ranges: [
              [Requirement.new("=", "main", allow_named_versions: true)],
              [Requirement.new("<", "1.5.0", allow_named_versions: false)]
            ], allow_named_versions: false
          )

          expect(multiple_ranges.cover?(NamedVersion.new(
            name: "main",
          ))).to be_truthy

          expect(multiple_ranges.cover?(NamedVersion.new(
            name: "dev",
          ))).to be_falsey
        end
      end
    end

    describe "#overlap?" do
      describe "a version range" do
        context "semantic" do
          it "is true if all RequirementSet ranges overlap the VersionRange" do
            single = described_class.new(
              ranges: [
                [Requirement.new(">", "1.4.0", allow_named_versions: false)]
              ], allow_named_versions: false
            )
            compound = described_class.new(
              ranges: [
                [Requirement.new(">", "1.4.0", allow_named_versions: false), Requirement.new("<", "1.5.0", allow_named_versions: false)]
              ], allow_named_versions: false
            )

            expect(single.overlap?(VersionRange.new(
              lower_bound: SemanticVersion.new(
                major: 1,
                minor: 3,
                patch: 0,
              ),
              upper_bound: SemanticVersion.new(
                major: 1,
                minor: 5,
                patch: 0,
              )
            ))).to be_truthy

            expect(compound.overlap?(VersionRange.new(
              lower_bound: SemanticVersion.new(
                major: 1,
                minor: 3,
                patch: 0,
              ),
              upper_bound: SemanticVersion.new(
                major: 1,
                minor: 5,
                patch: 0,
              )
            ))).to be_truthy
          end

          it "is false if single RequirementSet range does not overlap the VersionRange" do
            single = described_class.new(
              ranges: [
                [Requirement.new(">", "1.4.0", allow_named_versions: false)]
              ], allow_named_versions: false
            )
            compound = described_class.new(
              ranges: [
                [Requirement.new(">", "1.4.0", allow_named_versions: false), Requirement.new("<", "1.5.0", allow_named_versions: false)]
              ], allow_named_versions: false
            )

            expect(single.overlap?(VersionRange.new(
              lower_bound: SemanticVersion.new(
                major: 1,
                minor: 3,
                patch: 0,
              ),
              upper_bound: SemanticVersion.new(
                major: 1,
                minor: 3,
                patch: 10,
              )
            ))).to be_falsey

            expect(compound.overlap?(VersionRange.new(
              lower_bound: SemanticVersion.new(
                major: 1,
                minor: 3,
                patch: 0,
              ),
              upper_bound: SemanticVersion.new(
                major: 1,
                minor: 3,
                patch: 10,
              )
            ))).to be_falsey
          end

          it "is true if at least one RequirementSet range overlaps the VersionRange" do
            multiple_ranges = described_class.new(
              ranges: [
                [Requirement.new("=", "1.4.0", allow_named_versions: false)],
                [Requirement.new("=", "1.5.0", allow_named_versions: false)]
              ], allow_named_versions: false
            )

            expect(multiple_ranges.overlap?(VersionRange.new(
              lower_bound: SemanticVersion.new(
                major: 1,
                minor: 4,
                patch: 0,
              ),
              upper_bound: SemanticVersion.new(
                major: 1,
                minor: 4,
                patch: 5,
              )
            ))).to be_truthy

            expect(multiple_ranges.overlap?(VersionRange.new(
              lower_bound: SemanticVersion.new(
                major: 1,
                minor: 4,
                patch: 5,
              ),
              upper_bound: SemanticVersion.new(
                major: 1,
                minor: 5,
                patch: 0,
              )
            ))).to be_truthy
          end

          it "is false if the Requirement set is above and very close but not touching, exact" do
            range = described_class.new(
              ranges: [
                [Requirement.new(">=", "6.0.0", allow_named_versions: false), Requirement.new("<", "6.2.1", allow_named_versions: false)],
              ], allow_named_versions: false
            )
            exact = described_class.new(
              ranges: [
                [Requirement.new("=", "6.2.1", allow_named_versions: false)]
              ], allow_named_versions: false
            )
            expect(range.overlap?(exact)).to be_falsey
            expect(exact.overlap?(range)).to be_falsey
          end

          it "is false if the Requirement set is above and very close but not touching, range" do
            range = described_class.new(
              ranges: [
                [Requirement.new(">=", "6.0.0", allow_named_versions: false), Requirement.new("<", "6.2.1", allow_named_versions: false)],
              ], allow_named_versions: false
            )
            just_out_of_range = described_class.new(
              ranges: [
                [Requirement.new(">=", "6.2.1", allow_named_versions: false)]
              ], allow_named_versions: false
            )
            expect(range.overlap?(just_out_of_range)).to be_falsey
            expect(just_out_of_range.overlap?(range)).to be_falsey
          end

          it "is false if the Requirement set is below and very close but not touching, exact" do
            range = described_class.new(
              ranges: [
                [Requirement.new(">", "6.0.0", allow_named_versions: false), Requirement.new("<=", "6.2.1", allow_named_versions: false)],
              ], allow_named_versions: false
            )
            exact = described_class.new(
              ranges: [
                [Requirement.new("=", "6.0.0", allow_named_versions: false)]
              ], allow_named_versions: false
            )
            expect(range.overlap?(exact)).to be_falsey
            expect(exact.overlap?(range)).to be_falsey
          end

          it "is false if the Requirement set is below and very close but not touching, range" do
            range = described_class.new(
              ranges: [
                [Requirement.new(">", "6.0.0", allow_named_versions: false), Requirement.new("<=", "6.2.1", allow_named_versions: false)],
              ], allow_named_versions: false
            )
            exact = described_class.new(
              ranges: [
                [Requirement.new("<=", "6.0.0", allow_named_versions: false)]
              ], allow_named_versions: false
            )
            expect(range.overlap?(exact)).to be_falsey
            expect(exact.overlap?(range)).to be_falsey
          end
        end

        context "named" do
          it "is true if all RequirementSet ranges overlap the VersionRange" do
            req_set = described_class.new(
              ranges: [
                [Requirement.new(">", "1.4.0", allow_named_versions: false)]
              ],
              allow_named_versions: true,
            )

            expect(req_set.overlap?(VersionRange.new(
              lower_bound: NamedVersion.new(
                name: "main",
              ),
              upper_bound: NamedVersion.new(
                name: "main",
              )
            ))).to be_truthy
          end

          it "is false if single RequirementSet does not overlap the VersionRange" do
            single = described_class.new(
              ranges: [
                [Requirement.new("=", "main", allow_named_versions: true)]
              ],
              allow_named_versions: true,
            )
            compound = described_class.new(
              ranges: [
                [Requirement.new(">", "1.4.0", allow_named_versions: false), Requirement.new("<", "1.5.0", allow_named_versions: false)]
              ],
              allow_named_versions: true,
            )

            expect(single.overlap?(VersionRange.new(
              lower_bound: SemanticVersion.new(
                major: 1,
                minor: 3,
                patch: 0,
              ),
              upper_bound: SemanticVersion.new(
                major: 1,
                minor: 3,
                patch: 10,
              )
            ))).to be_falsey

            expect(compound.overlap?(VersionRange.new(
              lower_bound: NamedVersion.new(
                name: "main",
              ),
              upper_bound: NamedVersion.new(
                name: "main",
              )
            ))).to be_falsey
          end

          it "is true if at least one RequirementSet range overlaps the VersionRange" do
            multiple_ranges = described_class.new(
              ranges: [
                [Requirement.new("=", "1.4.0", allow_named_versions: false)],
                [Requirement.new("=", "main", allow_named_versions: true)]
              ],
              allow_named_versions: true,
            )

            expect(multiple_ranges.overlap?(VersionRange.new(
              lower_bound: NamedVersion.new(
                name: "main",
              ),
              upper_bound: NamedVersion.new(
                name: "main",
              ),
            ))).to be_truthy

            expect(multiple_ranges.overlap?(VersionRange.new(
              lower_bound: SemanticVersion.new(
                major: 1,
                minor: 4,
                patch: 0,
              ),
              upper_bound: SemanticVersion.new(
                major: 1,
                minor: 4,
                patch: 5,
              )
            ))).to be_truthy
          end
        end
      end

      describe "a requirements set" do
        context "semantic" do
          it "is true if all requirements in a range overlap" do
            left = described_class.new(
              ranges: [
                [Requirement.new(">", "1.4.0", allow_named_versions: false)]
              ], allow_named_versions: false
            )
            right = described_class.new(
              ranges: [
                [Requirement.new("<", "1.5.0", allow_named_versions: false)]
              ], allow_named_versions: false
            )

            expect(left.overlap?(right)).to be_truthy
            expect(right.overlap?(left)).to be_truthy

            left = described_class.new(
              ranges: [
                [Requirement.new(">", "1.4.0", allow_named_versions: false), Requirement.new("<", "1.6.0", allow_named_versions: false)]
              ], allow_named_versions: false
            )
            right = described_class.new(
              ranges: [
                [Requirement.new("<", "1.5.0", allow_named_versions: false)]
              ], allow_named_versions: false
            )

            expect(left.overlap?(right)).to be_truthy
            expect(right.overlap?(left)).to be_truthy
          end

          it "is false if a single requirement in a range doesn't overlap" do
            left = described_class.new(
              ranges: [
                [Requirement.new(">", "1.4.0", allow_named_versions: false)]
              ], allow_named_versions: false
            )
            right = described_class.new(
              ranges: [
                [Requirement.new("<", "1.4.0", allow_named_versions: false)]
              ], allow_named_versions: false
            )

            expect(left.overlap?(right)).to be_falsey
            expect(right.overlap?(left)).to be_falsey

            left = described_class.new(
              ranges: [
                [Requirement.new(">", "1.4.0", allow_named_versions: false), Requirement.new("<", "1.5.0", allow_named_versions: false)]
              ], allow_named_versions: false
            )
            right = described_class.new(
              ranges: [
                [Requirement.new(">", "1.5.0", allow_named_versions: false)]
              ], allow_named_versions: false
            )

            expect(left.overlap?(right)).to be_falsey
            expect(right.overlap?(left)).to be_falsey
          end
        end

        context "named" do
          it "is true if all requirements in a range overlap" do
            left = described_class.new(
              ranges: [
                [Requirement.new(">", "1.4.0", allow_named_versions: false)]
              ], allow_named_versions: false
            )
            right = described_class.new(
              ranges: [
                [Requirement.new("=", "main", allow_named_versions: true)]
              ], allow_named_versions: false
            )

            expect(left.overlap?(right)).to be_truthy
            expect(right.overlap?(left)).to be_truthy
          end

          it "is false if a single requirement in a range doesn't overlap" do
            left = described_class.new(
              ranges: [
                [Requirement.new("=", "main", allow_named_versions: true)]
              ], allow_named_versions: false
            )
            right = described_class.new(
              ranges: [
                [Requirement.new("=", "dev", allow_named_versions: true)]
              ], allow_named_versions: false
            )

            expect(left.overlap?(right)).to be_falsey
            expect(right.overlap?(left)).to be_falsey

            left = described_class.new(
              ranges: [
                [Requirement.new(">", "1.4.0", allow_named_versions: false), Requirement.new("<", "1.5.0", allow_named_versions: false)]
              ], allow_named_versions: false
            )
            right = described_class.new(
              ranges: [
                [Requirement.new("=", "main", allow_named_versions: true)]
              ], allow_named_versions: false
            )

            expect(left.overlap?(right)).to be_falsey
            expect(right.overlap?(left)).to be_falsey
          end
        end
      end
    end

    describe "#exact_version" do
      it "returns the exact version for a requirement set that has one" do
        set = described_class.new(
          ranges: [[Requirement.new("=", "1.1.0", allow_named_versions: false)]],
          allow_named_versions: false
        )
        expect(set.exact_version).to eq("1.1.0")
      end

      it "returns exact version for a requirement set that has one named version requirement" do
        set = described_class.new(
          ranges: [[Requirement.new("=", "main", allow_named_versions: true)]],
          allow_named_versions: false
        )
        expect(set.exact_version).to eq("main")
      end

      it "returns `nil` for a requirement set that isn't exact" do
        set = described_class.new(
          ranges: [[Requirement.new(">=", "1.1.0", allow_named_versions: false)]],
          allow_named_versions: false
        )
        expect(set.exact_version).to eq(nil)
      end

      it "returns `nil` for a requirement range that has more than one requirement" do
        set = described_class.new(
          ranges: [[Requirement.new("=", "1.1.0", allow_named_versions: false)],
                   [Requirement.new("=", "1.2.0", allow_named_versions: false)]],
          allow_named_versions: false
        )
        expect(set.exact_version).to eq(nil)
      end
    end
  end
end
