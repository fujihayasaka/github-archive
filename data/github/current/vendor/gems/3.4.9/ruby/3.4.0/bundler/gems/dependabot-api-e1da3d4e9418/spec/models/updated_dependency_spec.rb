# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdatedDependency, type: :model do
  subject(:dependency) { FactoryBot.build_stubbed(:updated_dependency) }

  describe "validations" do
    it { is_expected.to be_valid }

    context "without a pull_request" do
      before { dependency.pull_request = nil }

      it { is_expected.not_to be_valid }
    end

    context "without a name" do
      before { dependency.name = nil }

      it { is_expected.not_to be_valid }
    end

    context "with a name which is too long" do
      before { dependency.name = "X" * (described_class::MAX_CHARS_FOR_NAME + 1) }

      it "is invalid" do
        expect(dependency).not_to be_valid
      end

      it "reports the max size and the actual size" do
        dependency.valid?

        error_message = dependency.errors[:name]

        expect(error_message).to include(/is too long/)
        expect(error_message).
          to include(/(max: #{described_class::MAX_CHARS_FOR_NAME} actual: #{dependency.name.length})/)
      end
    end

    context "without a version" do
      before { dependency.version = nil }

      it { is_expected.not_to be_valid }
    end

    context "removed without a version" do
      before do
        dependency.version = nil
        dependency.removed = true
      end

      it { is_expected.to be_valid }
    end

    context "without a package_manager" do
      before { dependency.package_manager = nil }

      it { is_expected.not_to be_valid }
    end

    context "with an unknown package_manager" do
      before { dependency.package_manager = "fedex" }

      it { is_expected.not_to be_valid }
    end

    context "when serialized requirements are not too long" do
      before do
        dependency.requirements = [{
          "requirement" => "1.0.0",
          "file" => "package.json",
          "groups" => ["devDependencies"],
          "source" => nil,
        }] * 2
      end

      it { is_expected.to be_valid }
    end

    context "when serialized requirements are too long" do
      before do
        dependency.requirements = [{
          "requirement" => "1.0.0",
          "file" => "package.json",
          "groups" => ["devDependencies"],
          "source" => nil,
        }] * 800
      end

      it "is invalid" do
        expect(dependency).not_to be_valid
        expect(dependency.errors[:requirements]).to include(/is too long/)
        expect(dependency.errors[:requirements]).
          to include(/maximum serialized size: #{described_class::REQUIREMENTS_MAX_BYTES} bytes,/o)
        expect(dependency.errors[:requirements]).
          to include(/actual: #{dependency.attributes_for_database['requirements'].bytesize}/)
      end
    end

    context "when serialized previous_requirements are not too long" do
      before do
        dependency.previous_requirements = [{
          "requirement" => "1.0.0",
          "file" => "package.json",
          "groups" => ["devDependencies"],
          "source" => nil,
        }] * 2
      end

      it { is_expected.to be_valid }
    end

    context "when serialized previous_requirements are too long" do
      before do
        dependency.previous_requirements = [{
          "requirement" => "1.0.0",
          "file" => "package.json",
          "groups" => ["devDependencies"],
          "source" => nil,
        }] * 800
      end

      it "is invalid" do
        expect(dependency).not_to be_valid
        expect(dependency.errors[:previous_requirements]).to include(/is too long/)
        expect(dependency.errors[:previous_requirements]).
          to include(/maximum serialized size: #{described_class::REQUIREMENTS_MAX_BYTES} bytes,/o)
        expect(dependency.errors[:previous_requirements]).
          to include(/actual: #{dependency.attributes_for_database['previous_requirements'].bytesize}/)
      end
    end
  end

  describe "callbacks" do
    describe "before validation" do
      before { dependency.previous_version = "1.1.0" }

      it "sets non_breaking_if_semver to true" do
        expect(dependency.non_breaking_if_semver).to be_nil
        dependency.valid?
        expect(dependency.non_breaking_if_semver).to eq(true)
      end

      context "updating to a pre-release" do
        before { dependency.previous_version = "1.3.0.beta" }

        it "sets non_breaking_if_semver to false" do
          expect(dependency.non_breaking_if_semver).to be_nil
          dependency.valid?
          expect(dependency.non_breaking_if_semver).to eq(false)
        end
      end

      context "with a pre-1.0.0 dependency" do
        before { dependency.previous_version = "0.9.0" }

        it "sets non_breaking_if_semver to false" do
          expect(dependency.non_breaking_if_semver).to be_nil
          dependency.valid?
          expect(dependency.non_breaking_if_semver).to eq(false)
        end
      end

      context "with no previous version" do
        before { dependency.previous_version = nil }

        it "sets non_breaking_if_semver to false" do
          expect(dependency.non_breaking_if_semver).to be_nil
          dependency.valid?
          expect(dependency.non_breaking_if_semver).to eq(false)
        end
      end

      context "with a non-version-like previous version" do
        before { dependency.previous_version = "whatever" }

        it "sets non_breaking_if_semver to false" do
          expect(dependency.non_breaking_if_semver).to be_nil
          dependency.valid?
          expect(dependency.non_breaking_if_semver).to eq(false)
        end
      end

      context "with a non-version-like new version" do
        before { dependency.version = "whatever" }

        it "sets non_breaking_if_semver to false" do
          expect(dependency.non_breaking_if_semver).to be_nil
          dependency.valid?
          expect(dependency.non_breaking_if_semver).to eq(false)
        end
      end

      context "with a post-1.0.0 dependency" do
        before { dependency.previous_version = "1.1.0" }

        it "sets non_breaking_if_semver to true" do
          expect(dependency.non_breaking_if_semver).to be_nil
          dependency.valid?
          expect(dependency.non_breaking_if_semver).to eq(true)
        end

        context "updating to a new major version" do
          before { dependency.version = "2.0.0" }

          it "sets non_breaking_if_semver to false" do
            expect(dependency.non_breaking_if_semver).to be_nil
            dependency.valid?
            expect(dependency.non_breaking_if_semver).to eq(false)
          end
        end
      end
    end
  end

  describe "::from_dependabot_dependency" do
    let(:dependabot_dependency) do
      Dependabot::Dependency.new(
        name: "business",
        package_manager: "bundler",
        previous_requirements: [],
        previous_version: "0.9.0",
        removed: false,
        requirements: [],
        version: "1.0.0",
      )
    end

    it "returns a correctly populated UpdatedDependency" do
      object = described_class.from_dependabot_dependency(dependabot_dependency)

      expect(object).to be_a(described_class)
      expect(object.attributes.with_indifferent_access).to include(
        name: "business",
        package_manager: "bundler",
        previous_requirements: [],
        previous_version: "0.9.0",
        removed: false,
        requirements: [],
        version: "1.0.0",
      )
    end
  end

  describe "#to_dependabot_dependency" do
    it "returns a correctly populated Dependabot::Dependency" do
      expect(dependency.to_dependabot_dependency).to eq(
        Dependabot::Dependency.new(
          name: dependency.name,
          package_manager: dependency.package_manager,
          previous_requirements: dependency.previous_requirements,
          previous_version: dependency.previous_version,
          removed: dependency.removed,
          requirements: dependency.requirements,
          version: dependency.version,
        ),
      )
    end
  end
end
