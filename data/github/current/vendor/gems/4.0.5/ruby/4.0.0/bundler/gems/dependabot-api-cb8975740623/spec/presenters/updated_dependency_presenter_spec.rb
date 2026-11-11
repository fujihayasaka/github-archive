# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdatedDependencyPresenter do
  describe "#update_type" do
    subject { described_class.new(updated_dependency: updated_dependency).update_type }

    let(:updated_dependency) do
      Dependabot::Dependency.new(
        name: "business",
        version: version,
        previous_version: previous_version,
        requirements: requirements,
        previous_requirements: previous_requirements,
        package_manager: "bundler",
      )
    end
    let(:version) { nil }
    let(:previous_version) { nil }
    let(:requirements) { [] }
    let(:previous_requirements) { [] }

    valid_previous_versions = ["1.0.3-alpha.1", "1.0.3", "1.0", "1"]
    patch_upgrades = %w(1.0.4 1.0.5 1.0.4-rc0)
    minor_upgrades = %w(1.1.0 1.2.3 1.3 1.3.0 1.4 1.4.0)
    major_upgrades = %w(2 2.0 2.0.0 3 3.0 3.0.0)

    valid_previous_versions.each do |previous_version|
      context "with a valid previous version #{previous_version}" do
        let(:previous_version) { previous_version }

        patch_upgrades.each do |version|
          context "and a patch update #{version}" do
            let(:version) { version }

            it { is_expected.to eq("semver-patch") }
          end
        end

        minor_upgrades.each do |version|
          context "and a minor update #{version}" do
            let(:version) { version }

            it { is_expected.to eq("semver-minor") }
          end
        end

        major_upgrades.each do |version|
          context "and a major update #{version}" do
            let(:version) { version }

            it { is_expected.to eq("semver-major") }
          end
        end
      end
    end

    context "when the current version isn't known" do
      let(:previous_version) { "1.0.3" }
      let(:version) { nil }

      it { is_expected.to be_nil }
    end

    context "with a non-semver dependency" do
      let(:previous_version) { "Finchley.BR1" }
      let(:version) { "Finchley.SR3" }

      it { is_expected.to be_nil }
    end

    # NOTE: This test case would return `semver-minor` in dependabot preview
    # given the logic in MergeCandidateChecker
    context "with a git requirement and a semver compatible tag" do
      let(:requirements) do
        [{ file: "Gemfile", requirement: "~> 1.2.0", groups: [], source: { type: "git", ref: "v1.2.3" } }]
      end
      let(:previous_requirements) do
        [{ file: "Gemfile", requirement: "~> 1.1.0", groups: [], source: { type: "git", ref: "v1.0.3" } }]
      end

      it { is_expected.to be_nil }
    end

    # NOTE: This test case would return `semver-minor` in dependabot preview
    # given the logic in MergeCandidateChecker
    context "with a previous requirement matching a semver version" do
      let(:version) { "1.2.3" }
      let(:requirements) do
        [{ file: "Gemfile", requirement: "~> 1.2.3", groups: [], source: nil }]
      end
      let(:previous_requirements) do
        [{ file: "Gemfile", requirement: "~> 1.0.3", groups: [], source: nil }]
      end

      it { is_expected.to be_nil }
    end
  end
end
