require "spec_helper"
require "rails_helper"
require "active_support"
require "active_support/core_ext"

module Versioning
  describe Requirement do
    describe "version bounds" do
      let(:infinity) { Float::INFINITY }

      describe "'=' requirements" do
        it "parses all components" do
          requirement = described_class.new("=", "1.4.0", allow_named_versions: false)

          expect(requirement.lower_bound?).to be_truthy
          expect(requirement.lower_bound_inclusive?).to be_truthy
          expect(requirement.lower_bound).to eq SemanticVersion.new(
            major: 1,
            minor: 4,
            patch: 0
          )

          expect(requirement.upper_bound?).to be_truthy
          expect(requirement.upper_bound_inclusive?).to be_truthy
          expect(requirement.upper_bound).to eq SemanticVersion.new(
            major: 1,
            minor: 4,
            patch: 0
          )
        end

        it "parses all components including allows_named_versions" do
          requirement = described_class.new("=", "1.4.0", allow_named_versions: true)

          expect(requirement.lower_bound?).to be_truthy
          expect(requirement.lower_bound_inclusive?).to be_truthy
          expect(requirement.lower_bound).to eq GenericVersionParser.generate(
            allow_named_versions: true,
            primary_identifier: 1,
            minor: 4,
            patch: 0
          )

          expect(requirement.upper_bound?).to be_truthy
          expect(requirement.upper_bound_inclusive?).to be_truthy
          expect(requirement.upper_bound).to eq GenericVersionParser.generate(
            allow_named_versions: true,
            primary_identifier: 1,
            minor: 4,
            patch: 0
          )
          expect(requirement.allow_named_versions).to be_truthy
        end
      end

      it "parses '>=' operators" do
        requirement = described_class.new(">=", "2.2.0", allow_named_versions: true)

        expect(requirement.lower_bound?).to be_truthy
        expect(requirement.lower_bound_inclusive?).to be_truthy
        expect(requirement.lower_bound).to eq SemanticVersion.new(
          major: 2,
          minor: 2,
          patch: 0
        )
        expect(requirement.allow_named_versions).to be_truthy
        expect(requirement.upper_bound?).to be_falsey
      end

      it "parses '>' operators" do
        requirement = described_class.new(">", "2.2.0", allow_named_versions: false)

        expect(requirement.lower_bound?).to be_truthy
        expect(requirement.lower_bound_inclusive?).to be_falsey
        expect(requirement.lower_bound).to eq SemanticVersion.new(
          major: 2,
          minor: 2,
          patch: 0
        )
        expect(requirement.allow_named_versions).to be_falsey
        expect(requirement.upper_bound?).to be_falsey
      end

      it "parses '<=' operators" do
        requirement = described_class.new("<=", "2.2.0-rc1", allow_named_versions: false)

        expect(requirement.lower_bound?).to be_falsey

        expect(requirement.upper_bound?).to be_truthy
        expect(requirement.upper_bound_inclusive?).to be_truthy
        expect(requirement.upper_bound).to eq SemanticVersion.new(
          major: 2,
          minor: 2,
          patch: 0,
          prerelease: "rc1"
        )
        expect(requirement.allow_named_versions).to be_falsey
      end

      it "parses '<' operators" do
        requirement = described_class.new("<", "2.2.5.beta", allow_named_versions: false)

        expect(requirement.lower_bound?).to be_falsey

        expect(requirement.upper_bound?).to be_truthy
        expect(requirement.upper_bound_inclusive?).to be_falsey
        expect(requirement.upper_bound).to eq SemanticVersion.new(
          major: 2,
          minor: 2,
          patch: 5,
          prerelease: "beta",
        )
        expect(requirement.allow_named_versions).to be_falsey
      end

      it "parses '~' operators (unfixed patch)" do
        requirement = described_class.new("~", "2.2.5", allow_named_versions: false)

        expect(requirement.lower_bound?).to be_truthy
        expect(requirement.lower_bound?).to be_truthy
        expect(requirement.lower_bound_inclusive?).to be_truthy
        expect(requirement.lower_bound).to eq SemanticVersion.new(
          major: 2,
          minor: 2,
          patch: 5
        )

        expect(requirement.upper_bound?).to be_truthy
        expect(requirement.upper_bound_inclusive?).to be_truthy
        expect(requirement.upper_bound).to eq SemanticVersion.new(
          major: 2,
          minor: 2,
          patch: infinity
        )
        expect(requirement.allow_named_versions).to be_falsey
      end

      it "parses '~' operators (unfixed minor if none specified)" do
        requirement = described_class.new("~", "2", allow_named_versions: false)

        expect(requirement.lower_bound?).to be_truthy
        expect(requirement.lower_bound?).to be_truthy
        expect(requirement.lower_bound_inclusive?).to be_truthy
        expect(requirement.lower_bound).to eq SemanticVersion.new(
          major: 2,
          minor: 0,
          patch: 0
        )

        expect(requirement.upper_bound?).to be_truthy
        expect(requirement.upper_bound_inclusive?).to be_truthy
        expect(requirement.upper_bound).to eq SemanticVersion.new(
          major: 2,
          minor: infinity,
          patch: infinity
        )
        expect(requirement.allow_named_versions).to be_falsey
      end

      it "parses '~' operators with a prerelease" do
        requirement = described_class.new("~", "1.2.3-beta.2", allow_named_versions: false)

        expect(requirement.lower_bound?).to be_truthy
        expect(requirement.lower_bound_inclusive?).to be_truthy
        expect(requirement.lower_bound).to eq SemanticVersion.new(
          major: 1,
          minor: 2,
          patch: 3,
          prerelease: "beta.2",
        )

        expect(requirement.upper_bound?).to be_truthy
        expect(requirement.upper_bound_inclusive?).to be_truthy
        expect(requirement.upper_bound).to eq SemanticVersion.new(
          major: 1,
          minor: 2,
          patch: infinity
        )
        expect(requirement.allow_named_versions).to be_falsey
      end

      it "parses '^' operators (unfixed patch and minor)" do
        requirement = described_class.new("^", "2.2.5", allow_named_versions: false)

        expect(requirement.lower_bound?).to be_truthy
        expect(requirement.lower_bound_inclusive?).to be_truthy
        expect(requirement.lower_bound).to eq SemanticVersion.new(
          major: 2,
          minor: 2,
          patch: 5
        )

        expect(requirement.upper_bound?).to be_truthy
        expect(requirement.upper_bound_inclusive?).to be_truthy
        expect(requirement.upper_bound).to eq SemanticVersion.new(
          major: 2,
          minor: infinity,
          patch: infinity
        )
        expect(requirement.allow_named_versions).to be_falsey
      end

      it "handles zeroth releases with the '^' operator" do
        requirement = described_class.new("^", "0.2.5", allow_named_versions: false)

        expect(requirement.lower_bound?).to be_truthy
        expect(requirement.lower_bound_inclusive?).to be_truthy
        expect(requirement.lower_bound).to eq SemanticVersion.new(
          major: 0,
          minor: 2,
          patch: 5
        )

        expect(requirement.upper_bound?).to be_truthy
        expect(requirement.upper_bound_inclusive?).to be_truthy
        expect(requirement.upper_bound).to eq SemanticVersion.new(
          major: 0,
          minor: 2,
          patch: infinity
        )
        expect(requirement.allow_named_versions).to be_falsey
      end

      describe "the '~>` operator" do

        it "parses a version with all components" do
          requirement = described_class.new("~>", "2.2.5", allow_named_versions: false)

          expect(requirement.lower_bound?).to be_truthy
          expect(requirement.lower_bound_inclusive?).to be_truthy
          expect(requirement.lower_bound).to eq SemanticVersion.new(
            major: 2,
            minor: 2,
            patch: 5
          )

          expect(requirement.upper_bound?).to be_truthy
          expect(requirement.upper_bound_inclusive?).to be_truthy
          expect(requirement.upper_bound).to eq SemanticVersion.new(
            major: 2,
            minor: 2,
            patch: infinity
          )
          expect(requirement.allow_named_versions).to be_falsey
        end

        it "parses a version with additional components" do
          requirement = described_class.new("~>", "2.2.5.1.2.3", allow_named_versions: false)

          expect(requirement.lower_bound?).to be_truthy
          expect(requirement.lower_bound_inclusive?).to be_truthy
          expect(requirement.lower_bound).to eq SemanticVersion.new(
            major: 2,
            minor: 2,
            patch: 5,
            additional_fields: [1, 2, 3]
          )

          expect(requirement.upper_bound?).to be_truthy
          expect(requirement.upper_bound_inclusive?).to be_truthy
          expect(requirement.upper_bound).to eq SemanticVersion.new(
            major: 2,
            minor: 2,
            patch: 5,
            additional_fields: [1, 2, infinity]
          )
          expect(requirement.allow_named_versions).to be_falsey
        end

        it "parses a version without a patch component" do
          requirement = described_class.new("~>", "2.2", allow_named_versions: false)

          expect(requirement.lower_bound?).to be_truthy
          expect(requirement.lower_bound_inclusive?).to be_truthy
          expect(requirement.lower_bound).to eq SemanticVersion.new(
            major: 2,
            minor: 2,
            patch: 0
          )

          expect(requirement.upper_bound?).to be_truthy
          expect(requirement.upper_bound_inclusive?).to be_truthy
          expect(requirement.upper_bound).to eq SemanticVersion.new(
            major: 2,
            minor: infinity,
            patch: infinity
          )
          expect(requirement.allow_named_versions).to be_falsey
        end
      end

      it "treats a missing patch as 0" do
        requirement = described_class.new(">=", "2.2", allow_named_versions: false)

        expect(requirement.lower_bound?).to be_truthy
        expect(requirement.lower_bound).to eq SemanticVersion.new(
          major: 2,
          minor: 2,
          patch: 0
        )

        expect(requirement.upper_bound?).to be_falsey
        expect(requirement.allow_named_versions).to be_falsey
      end

      it "treats a missing minor version as 0" do
        requirement = described_class.new(">=", "2", allow_named_versions: false)

        expect(requirement.lower_bound?).to be_truthy
        expect(requirement.lower_bound).to eq SemanticVersion.new(
          major: 2,
          minor: 0,
          patch: 0
        )

        expect(requirement.upper_bound?).to be_falsey
        expect(requirement.allow_named_versions).to be_falsey
      end

      it "includes prerelease versions" do
        requirement = described_class.new(">=", "2.0.0.alpha", allow_named_versions: false)

        expect(requirement.lower_bound?).to be_truthy
        expect(requirement.lower_bound).to eq SemanticVersion.new(
          major: 2,
          minor: 0,
          patch: 0,
          prerelease: "alpha",
        )

        expect(requirement.upper_bound?).to be_falsey

        requirement = described_class.new("<=", "2.0.0.alpha", allow_named_versions: false)

        expect(requirement.lower_bound?).to be_falsey

        expect(requirement.upper_bound?).to be_truthy
        expect(requirement.upper_bound).to eq SemanticVersion.new(
          major: 2,
          minor: 0,
          patch: 0,
          prerelease: "alpha",
        )
        expect(requirement.allow_named_versions).to be_falsey
      end
    end

    describe "#valid?" do
      it "is valid with a requirement and operator" do
        expect(described_class.new(">=", "2.2", allow_named_versions: false)).to be_valid
      end

      it "is valid when blank" do
        expect(described_class.new("", allow_named_versions: false)).to be_valid
        expect(described_class.new(nil, allow_named_versions: false)).to be_valid
        expect(described_class.new("", "", allow_named_versions: false)).to be_valid
      end

      it "is invalid with missing components" do
        expect(described_class.new(">=", "", allow_named_versions: false)).to_not be_valid
        expect(described_class.new("", "2.2", allow_named_versions: false)).to_not be_valid
      end
    end

    describe "serialization" do
      it "deserializes requirements" do
        requirement = described_class.new(">=", "2.2", allow_named_versions: false)

        expect(described_class.deserialize(">= 2.2", allow_named_versions: false)).to eq requirement
        expect(described_class.deserialize(">=      2.2", allow_named_versions: false)).to eq requirement
        expect(described_class.deserialize(">=2.2", allow_named_versions: false)).to eq requirement
        expect(described_class.deserialize("  >=2.2", allow_named_versions: false)).to eq requirement
        expect(described_class.deserialize(">=2.2   ", allow_named_versions: false)).to eq requirement
      end

      it "deserializes requirements when named versions are allowed" do
        requirement = described_class.new("=", "main", allow_named_versions: true)

        expect(described_class.deserialize("= main", allow_named_versions: true)).to eq requirement
        expect(described_class.deserialize("=      main", allow_named_versions: true)).to eq requirement
        expect(described_class.deserialize("=main", allow_named_versions: true)).to eq requirement
      end

      it "handles named version if operator is not '='" do
        expect(described_class.deserialize("< main", allow_named_versions: true)).to_not be_valid
      end

      it "handles garbage" do
        expect(described_class.deserialize(">= 2.2,>= 2.2", allow_named_versions: false)).to_not be_valid
        expect(described_class.deserialize(">= 2.2 >= 2.2", allow_named_versions: false)).to_not be_valid
        expect(described_class.deserialize("OMGSPIDERS", allow_named_versions: false)).to_not be_valid
      end

      it "serializes requirements" do
        requirement = described_class.new(">=", "2.2", allow_named_versions: false)

        expect(requirement.serialize).to eq ">= 2.2"
      end

      it "can convert between serialized and deserialized forms" do
        requirement = described_class.new(">=", "2.2", allow_named_versions: false)
        converted = described_class.deserialize(requirement.serialize, allow_named_versions: false)

        expect(converted).to be_valid
        expect(converted).to eq requirement
      end
    end

    describe "#cover?" do
      context "semantic" do
        it "is true if the requirement encompasses a version" do
          requirement = Requirement.new(">=", "5.0.0", allow_named_versions: false)

          expect(requirement.cover?(SemanticVersion.new(
            major: 5,
            minor: 0,
            patch: 0,
          ))).to be_truthy

          expect(requirement.cover?(SemanticVersion.new(
            major: 6,
            minor: 0,
            patch: 0,
          ))).to be_truthy

          requirement = Requirement.new("<", "5.0.0", allow_named_versions: false)

          expect(requirement.cover?(SemanticVersion.new(
            major: 4,
            minor: 99,
            patch: 99,
          ))).to be_truthy
        end

        it "is true if the requirement is the same as a version" do
          requirement = Requirement.new("=", "1.2.3.4", allow_named_versions: false)

          expect(requirement.cover?(SemanticVersion.new(
            major: 1,
            minor: 2,
            patch: 3,
            additional_fields: [4],
          ))).to be_truthy
        end

        it "is false if the requirement does not encompass a version" do
          requirement = Requirement.new(">=", "5.0.0", allow_named_versions: false)

          expect(requirement.cover?(SemanticVersion.new(
            major: 4,
            minor: 99,
            patch: 99,
          ))).to be_falsey

          expect(requirement.cover?(SemanticVersion.new(
            major: 5,
            minor: 0,
            patch: 0,
            prerelease: "beta",
          ))).to be_falsey

          requirement = Requirement.new(">", "5.0.0", allow_named_versions: false)

          expect(requirement.cover?(SemanticVersion.new(
            major: 5,
            minor: 0,
            patch: 0,
          ))).to be_falsey

          requirement = Requirement.new("<=", "5.0.0", allow_named_versions: false)

          expect(requirement.cover?(SemanticVersion.new(
            major: 5,
            minor: 0,
            patch: 1,
          ))).to be_falsey

          requirement = Requirement.new("<", "5.0.0", allow_named_versions: false)

          expect(requirement.cover?(SemanticVersion.new(
            major: 5,
            minor: 0,
            patch: 0,
          ))).to be_falsey
        end
      end

      context "named" do
        it "is true if the ref requirement encompasses a version" do
          requirement = Requirement.new("=", "main", allow_named_versions: true)

          expect(requirement.cover?(NamedVersion.new(
            name: "main",
          ))).to be_truthy

        end

        it "is true if the ref requirement is the same as a version" do
          requirement = Requirement.new("=", "main", allow_named_versions: true)

          expect(requirement.cover?(NamedVersion.new(
            name: "main",
          ))).to be_truthy
        end

        it "is false if the ref requirement does not equal a version" do
          requirement = Requirement.new("=", "anything", allow_named_versions: false)

          expect(requirement.cover?(NamedVersion.new(
            name: "main"
          ))).to be_falsey
        end
      end
    end

    describe "#overlap?" do
      context "semantic" do
        it "is true if the requirement is encompassed by the range" do
          requirement = Requirement.new("=", "5.1.0", allow_named_versions: false)

          expect(requirement.overlap?(VersionRange.new(
            lower_bound: SemanticVersion.new(
              major: 5,
              minor: 0,
              patch: 0,
            ),
            upper_bound: SemanticVersion.new(
              major: 5,
              minor: 2,
              patch: 0,
            )
          ))).to be_truthy

          expect(requirement.overlap?(VersionRange.new(
            lower_bound: SemanticVersion.new(
              major: 5,
              minor: 1,
              patch: 0,
            ),
            upper_bound: SemanticVersion.new(
              major: 5,
              minor: 2,
              patch: 0,
            )
          ))).to be_truthy

          expect(requirement.overlap?(VersionRange.new(
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
          ))).to be_truthy

          expect(requirement.overlap?(VersionRange.new(
            lower_bound: nil, # unbounded
            upper_bound: SemanticVersion.new(
              major: 5,
              minor: 1,
              patch: 0,
            )
          ))).to be_truthy

          expect(requirement.overlap?(VersionRange.new(
            lower_bound: SemanticVersion.new(
              major: 5,
              minor: 0,
              patch: 0,
            ),
            upper_bound: nil # unbounded
          ))).to be_truthy
        end

        it "is true if the requirement overlaps the lower bound" do
          requirement = Requirement.new("<", "5.1.0", allow_named_versions: false)

          expect(requirement.overlap?(VersionRange.new(
            lower_bound: SemanticVersion.new(
              major: 5,
              minor: 0,
              patch: 0,
            ),
            upper_bound: SemanticVersion.new(
              major: 5,
              minor: 2,
              patch: 0,
            )
          ))).to be_truthy

          expect(requirement.overlap?(VersionRange.new(
            lower_bound: SemanticVersion.new(
              major: 5,
              minor: 0,
              patch: 0,
            ),
            upper_bound: nil # unbounded
          ))).to be_truthy
        end

        it "is true if the requirement overlaps the upper bound" do
          requirement = Requirement.new(">", "5.1.0", allow_named_versions: false)

          expect(requirement.overlap?(VersionRange.new(
            lower_bound: SemanticVersion.new(
              major: 5,
              minor: 0,
              patch: 0,
            ),
            upper_bound: SemanticVersion.new(
              major: 5,
              minor: 2,
              patch: 0,
            )
          ))).to be_truthy

          expect(requirement.overlap?(VersionRange.new(
            lower_bound: nil, # unbounded
            upper_bound: SemanticVersion.new(
              major: 5,
              minor: 2,
              patch: 0,
            )
          ))).to be_truthy
        end

        it "is true if the requirement encompasses the bounds" do
          requirement = Requirement.new(">", "4.0.0", allow_named_versions: false)

          expect(requirement.overlap?(VersionRange.new(
            lower_bound: SemanticVersion.new(
              major: 5,
              minor: 0,
              patch: 0,
            ),
            upper_bound: SemanticVersion.new(
              major: 5,
              minor: 2,
              patch: 0,
            )
          ))).to be_truthy

          requirement = Requirement.new("~>", "5.0", allow_named_versions: false)

          expect(requirement.overlap?(VersionRange.new(
            lower_bound: SemanticVersion.new(
              major: 5,
              minor: 1,
              patch: 0,
            ),
            upper_bound: SemanticVersion.new(
              major: 5,
              minor: 2,
              patch: 0,
            )
          ))).to be_truthy
        end

        it "is false if the requirement falls below the lower bound" do
          requirement = Requirement.new("=", "5.1.0", allow_named_versions: false)

          expect(requirement.overlap?(VersionRange.new(
            lower_bound: SemanticVersion.new(
              major: 5,
              minor: 1,
              patch: 1,
            ),
            upper_bound: SemanticVersion.new(
              major: 5,
              minor: 2,
              patch: 0,
            )
          ))).to be_falsey

          requirement = Requirement.new("<", "5.2.0", allow_named_versions: false)

          expect(requirement.overlap?(VersionRange.new(
            lower_bound: SemanticVersion.new(
              major: 5,
              minor: 2,
              patch: 0,
            ),
            upper_bound: SemanticVersion.new(
              major: 5,
              minor: 3,
              patch: 0,
            )
          ))).to be_falsey
        end

        it "is false if the requirement falls above the upper bound" do
          requirement = Requirement.new("=", "5.1.0", allow_named_versions: false)

          expect(requirement.overlap?(VersionRange.new(
            lower_bound: SemanticVersion.new(
              major: 5,
              minor: 0,
              patch: 0,
            ),
            upper_bound: SemanticVersion.new(
              major: 5,
              minor: 0,
              patch: 10,
            )
          ))).to be_falsey

          requirement = Requirement.new(">", "5.1.0", allow_named_versions: false)

          expect(requirement.overlap?(VersionRange.new(
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
          ))).to be_falsey
        end

        it "sets lower bounds to 0 if provided a wildcard" do
          requirement = Requirement.new("=", "5.1.*", allow_named_versions: false)
          expect(requirement.lower_bound).to eq SemanticVersion.new(
            major: 5,
            minor: 1,
            patch: 0,
          )
        end
      end

      context "named" do
        it "is true if the ref requirement is encompassed by the range" do
          requirement = Requirement.new("=", "main", allow_named_versions: true)

          expect(requirement.overlap?(VersionRange.new(
            lower_bound: NamedVersion.new(
              name: "main",
            ),
          ))).to be_truthy

          expect(requirement.overlap?(VersionRange.new(
            lower_bound: SemanticVersion.new(
              major: 5,
              minor: 2,
              patch: 0,
            ),
            upper_bound: NamedVersion.new(
              name: "main"
            ),
          ))).to be_truthy

          expect(requirement.overlap?(VersionRange.new(
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
          ))).to be_falsey

          expect(requirement.overlap?(VersionRange.new(
            lower_bound: nil, # unbounded
            upper_bound: SemanticVersion.new(
              major: 5,
              minor: 1,
              patch: 0,
            )
          ))).to be_falsey

          expect(requirement.overlap?(VersionRange.new(
            lower_bound: SemanticVersion.new(
              major: 5,
              minor: 0,
              patch: 0,
            ),
            upper_bound: nil # unbounded
          ))).to be_truthy
        end

        it "is true if the ref requirement overlaps the upper bound" do
          requirement = Requirement.new("=", "main", allow_named_versions: true)

          expect(requirement.overlap?(VersionRange.new(
            lower_bound: SemanticVersion.new(
              major: 5,
              minor: 2,
              patch: 0,
            ),
            upper_bound: NamedVersion.new(
              name: "main"
            )
          ))).to be_truthy

          expect(requirement.overlap?(VersionRange.new(
            lower_bound: SemanticVersion.new(
              major: 5,
              minor: 0,
              patch: 0,
            ),
            upper_bound: nil # unbounded
          ))).to be_truthy
        end

        it "is true if the ref requirement overlaps the lower bound" do
          requirement = Requirement.new("=", "main", allow_named_versions: true)

          expect(requirement.overlap?(VersionRange.new(
            lower_bound: SemanticVersion.new(
              major: 5,
              minor: 2,
              patch: 0,
            ),
            upper_bound: NamedVersion.new(
              name: "main"
            )
          ))).to be_truthy

          expect(requirement.overlap?(VersionRange.new(
            lower_bound: SemanticVersion.new(
              major: 5,
              minor: 2,
              patch: 0,
            ),
            upper_bound: nil, # unbounded
          ))).to be_truthy
        end

        it "is true if the ref requirement encompasses the bounds" do
          requirement = Requirement.new("=", "main", allow_named_versions: true)

          expect(requirement.overlap?(VersionRange.new(
            lower_bound: SemanticVersion.new(
              major: 5,
              minor: 2,
              patch: 0,
            ),
            upper_bound: NamedVersion.new(
              name: "main"
            ),
          ))).to be_truthy
        end

        it "is false if the ref requirement falls below the lower bound" do
          # dev < main < xyz in alphabetical order
          requirement = Requirement.new("=", "dev", allow_named_versions: true)

          expect(requirement.overlap?(VersionRange.new(
            lower_bound: NamedVersion.new(
              name: "main"
            ),
            upper_bound: NamedVersion.new(
              name: "xyz"
            ),
          ))).to be_falsey
        end

        it "is false if the ref requirement falls above the upper bound" do
          # dev < main < xyz in alphabetical order
          requirement = Requirement.new("=", "xyz", allow_named_versions: true)

          expect(requirement.overlap?(VersionRange.new(
            lower_bound: NamedVersion.new(
              name: "dev"
            ),
            upper_bound: NamedVersion.new(
              name: "main"
            ),
          ))).to be_falsey
        end
      end
    end

    describe "#contain?" do
      context "semantic" do
        it "is true if everything that satisfies the right upper bound also satisfies the left upper bound" do
          left = described_class.new(">", "5.1.0", allow_named_versions: false)

          expect(left.contain?(described_class.new(">", "5.1.0", allow_named_versions: false))).to be_truthy
          expect(left.contain?(described_class.new("=", "5.1.1", allow_named_versions: false))).to be_truthy

          expect(left.contain?(described_class.new("<", "5.2.0", allow_named_versions: false))).to be_falsey
          expect(left.contain?(described_class.new("<=", "5.1.0", allow_named_versions: false))).to be_falsey
          expect(left.contain?(described_class.new("=", "5.1.0", allow_named_versions: false))).to be_falsey
          expect(left.contain?(described_class.new("<", "5.1.0", allow_named_versions: false))).to be_falsey
          expect(left.contain?(described_class.new("=", "5.0.12", allow_named_versions: false))).to be_falsey

          left = described_class.new("<", "5.1.0", allow_named_versions: false)

          expect(left.contain?(described_class.new(">", "5.1.0", allow_named_versions: false))).to be_falsey
          expect(left.contain?(described_class.new("<", "5.2.0", allow_named_versions: false))).to be_falsey
          expect(left.contain?(described_class.new("=", "5.1.1", allow_named_versions: false))).to be_falsey
          expect(left.contain?(described_class.new("<=", "5.1.0", allow_named_versions: false))).to be_falsey
          expect(left.contain?(described_class.new("=", "5.1.0", allow_named_versions: false))).to be_falsey

          expect(left.contain?(described_class.new("<", "5.1.0", allow_named_versions: false))).to be_truthy
          expect(left.contain?(described_class.new("=", "5.0.12", allow_named_versions: false))).to be_truthy

          left = described_class.new("=", "5.1.0", allow_named_versions: false)

          expect(left.contain?(described_class.new("=", "5.1.0", allow_named_versions: false))).to be_truthy
          expect(left.contain?(described_class.new("<", "5.1.0", allow_named_versions: false))).to be_falsey

          expect(left.contain?(described_class.new("<=", "5.1.0", allow_named_versions: false))).to be_falsey
          expect(left.contain?(described_class.new(">=", "5.1.0", allow_named_versions: false))).to be_falsey
          expect(left.contain?(described_class.new(">", "5.1.0", allow_named_versions: false))).to be_falsey
        end
      end

      context "named" do
        it "is true if the left bound equals the right bound" do
          left = described_class.new("=", "main", allow_named_versions: true)

          expect(left.contain?(described_class.new("=", "main", allow_named_versions: true))).to be_truthy

          expect(left.contain?(described_class.new("=", "dev", allow_named_versions: true))).to be_falsey
          expect(left.contain?(described_class.new(">", "1.0.0", allow_named_versions: true))).to be_falsey
          expect(left.contain?(described_class.new("<", "1.0.0", allow_named_versions: true))).to be_falsey
        end
      end
    end
  end
end
