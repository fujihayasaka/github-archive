# frozen_string_literal: true

require "rails_helper"
require "github/version_range"

RSpec.describe GitHub::VersionRange do
  describe "::new" do
    context "with valid ranges" do
      [
        "= 1",
        "> 0",
        ">= 1.2",
        "< 2",
        "<= 2.0",
        ">= 2.0, < 2.5",
        ">= 5.0.0, <= 5.2.0",
      ].each do |range_string|
        it "does not throw an exception for #{range_string}" do
          expect { described_class.new(range_string) }.not_to raise_error
        end
      end
    end

    context "with invalid ranges" do
      [
        "?invalid?",
        "2",
        "a1b",
        "=< 3",
        "=< 4",
        " < 1.0",
        "> 1.0, > 2",
        ">= 1.0 , < 2",
        "< 1.2.3,",
        "> 1, > 2", # can't re-use >
        "> 1.1, >= 2.2", # can't re-use >
        "< 1.1.0, > 2.2.1", # can't start with < if two-part
        "< 1.1, < 123.0", # can't re-use <
      ].each do |range_string|
        it "throws an exception for #{range_string}" do
          expect { described_class.new(range_string) }.
            to raise_error(GitHub::VersionRange::InvalidRangeError)
        end
      end
    end
  end

  describe "::convert_for_dependabot" do
    context "a maven package" do
      def convert(range)
        described_class.new(range).convert_for_dependabot("maven")
      end

      context "a specific single version" do
        it { expect(convert("= 1.0.0")).to eql "1.0.0" }
        it { expect(convert("= 3.1.12")).to eql "3.1.12" }
        it { expect(convert("= 3.1.12-beta.rc5")).to eql "3.1.12-beta.rc5" }
      end

      context "versions lower than" do
        it { expect(convert("< 2.5.14")).to eql "(,2.5.14)" }
        it { expect(convert("<= 2.5.14")).to eql "(,2.5.14]" }
      end

      context "versions greater than" do
        it { expect(convert("> 2.5.0")).to eql "(2.5.0,)" }
        it { expect(convert(">= 2.5.0")).to eql "[2.5.0,)" }
      end

      context "versions between" do
        it { expect(convert(">= 2.5.0, <= 2.5.14")).to eql "[2.5.0,2.5.14]" }
        it { expect(convert("> 2.5.0, <= 2.5.14")).to eql "(2.5.0,2.5.14]" }
        it { expect(convert(">= 2.5.0, < 2.5.14")).to eql "[2.5.0,2.5.14)" }
        it { expect(convert("> 2.5.0, < 2.5.14")).to eql "(2.5.0,2.5.14)" }
      end

      context "unexpected inputs" do
        it "errors if given garbage" do
          expect { convert("garbage") }.
            to raise_error(GitHub::VersionRange::InvalidRangeError)
        end

        it "errors if given maven notation" do
          expect { convert("[2.5.0,2.5.14]") }.
            to raise_error(GitHub::VersionRange::InvalidRangeError)
        end

        it "errors if given an unintelligable list" do
          expect { convert("< 2.5.0, <= 2.5.14") }.
            to raise_error(GitHub::VersionRange::InvalidRangeError)

          expect { convert("< 2.4, > 2.5.0, <= 2.5.14") }.
            to raise_error(GitHub::VersionRange::InvalidRangeError)

          expect { convert("2.4, > 2.5.0, <= 2.5.14") }.
            to raise_error(GitHub::VersionRange::InvalidRangeError)
        end
      end
    end

    context "an npm package" do
      def convert(range)
        described_class.new(range).convert_for_dependabot("npm_and_yarn")
      end

      context "a specific single version" do
        it { expect(convert("= 1.0.0")).to eql "= 1.0.0" }
        it { expect(convert("= 3.1.12")).to eql "= 3.1.12" }
        it { expect(convert("= 3.1.12-beta.rc5")).to eql "= 3.1.12-beta.rc5" }
      end

      context "versions lower than" do
        it { expect(convert("< 2.5.14")).to eql "< 2.5.14" }
        it { expect(convert("<= 2.5.14")).to eql "<= 2.5.14" }
      end

      context "versions greater than" do
        it { expect(convert("> 2.5.0")).to eql "> 2.5.0" }
        it { expect(convert(">= 2.5.0")).to eql ">= 2.5.0" }
      end

      context "versions between" do
        it { expect(convert("> 2.5.0, <= 2.5.14")).to eql "> 2.5.0 <= 2.5.14" }
      end
    end

    context "anything else" do
      def convert(range)
        described_class.new(range).convert_for_dependabot("anything")
      end

      context "a specific single version" do
        it { expect(convert("= 1.0.0")).to eql "= 1.0.0" }
        it { expect(convert("= 3.1.12")).to eql "= 3.1.12" }
        it { expect(convert("= 3.1.12-beta.rc5")).to eql "= 3.1.12-beta.rc5" }
      end

      context "versions lower than" do
        it { expect(convert("< 2.5.14")).to eql "< 2.5.14" }
        it { expect(convert("<= 2.5.14")).to eql "<= 2.5.14" }
      end

      context "versions greater than" do
        it { expect(convert("> 2.5.0")).to eql "> 2.5.0" }
        it { expect(convert(">= 2.5.0")).to eql ">= 2.5.0" }
      end

      context "versions between" do
        it { expect(convert("> 2.5.0, <= 2.5.14")).to eql "> 2.5.0, <= 2.5.14" }
      end
    end
  end
end
