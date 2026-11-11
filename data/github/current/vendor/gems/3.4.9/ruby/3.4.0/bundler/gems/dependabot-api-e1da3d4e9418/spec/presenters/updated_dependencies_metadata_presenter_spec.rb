# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdatedDependenciesMetadataPresenter do
  describe "#metadata" do
    subject(:metadata) do
      described_class.new(
        updated_dependencies: updated_dependencies,
        security_updates_only: security_updates_only,
        dependency_group: dependency_group,
      ).metadata
    end

    let(:security_updates_only) { false }
    let(:updated_dependencies) { [updated_dependency] }
    let(:dependency_group) { nil }

    context "with an indirect update" do
      let(:updated_dependency) do
        Dependabot::Dependency.new(
          name: "business",
          version: "1.1.1",
          previous_version: "1.0.0",
          requirements: [],
          previous_requirements: [],
          package_manager: "bundler",
        )
      end

      it {
        expect(metadata).to eq({
                                 "updated-dependencies" => [{
                                   "dependency-name" => "business",
                                   "dependency-version" => "1.1.1",
                                   "dependency-type" => "indirect",
                                   "update-type" => "version-update:semver-minor",
                                 }],
                               })
      }
    end

    context "with an indirect security update" do
      let(:security_updates_only) { true }
      let(:updated_dependency) do
        Dependabot::Dependency.new(
          name: "business",
          version: "1.1.1",
          previous_version: "1.0.0",
          requirements: [],
          previous_requirements: [],
          package_manager: "bundler",
        )
      end

      it {
        expect(metadata).to eq({
                                 "updated-dependencies" => [{
                                   "dependency-name" => "business",
                                   "dependency-version" => "1.1.1",
                                   "dependency-type" => "indirect",
                                 }],
                               })
      }
    end

    context "with a direct update without a group" do
      let(:updated_dependency) do
        Dependabot::Dependency.new(
          name: "business",
          version: "1.1.1",
          previous_version: "1.0.0",
          requirements: [{ file: "Gemfile", requirement: "~> 1.1.1", groups: [], source: nil }],
          previous_requirements: [{ file: "Gemfile", requirement: "~> 1.0.0", groups: [], source: nil }],
          package_manager: "bundler",
        )
      end

      it {
        expect(metadata).to eq({
                                 "updated-dependencies" => [{
                                   "dependency-name" => "business",
                                   "dependency-version" => "1.1.1",
                                   "dependency-type" => "direct:production",
                                   "update-type" => "version-update:semver-minor",
                                 }],
                               })
      }
    end

    context "with a direct update production" do
      let(:updated_dependency) do
        Dependabot::Dependency.new(
          name: "business",
          version: "1.1.1",
          previous_version: "1.0.0",
          requirements: [{ file: "Gemfile", requirement: "~> 1.1.1", groups: ["production"], source: nil }],
          previous_requirements: [{ file: "Gemfile", requirement: "~> 1.0.0", groups: ["production"], source: nil }],
          package_manager: "bundler",
        )
      end

      it {
        expect(metadata).to eq({
                                 "updated-dependencies" => [{
                                   "dependency-name" => "business",
                                   "dependency-version" => "1.1.1",
                                   "dependency-type" => "direct:production",
                                   "update-type" => "version-update:semver-minor",
                                 }],
                               })
      }
    end

    context "with a direct development update" do
      let(:updated_dependency) do
        Dependabot::Dependency.new(
          name: "business",
          version: "1.1.1",
          previous_version: "1.0.0",
          requirements: [{ file: "Gemfile", requirement: "~> 1.1.1", groups: ["development"], source: nil }],
          previous_requirements: [{ file: "Gemfile", requirement: "~> 1.0.0", groups: ["development"], source: nil }],
          package_manager: "bundler",
        )
      end

      it {
        expect(metadata).to eq({
                                 "updated-dependencies" => [{
                                   "dependency-name" => "business",
                                   "dependency-version" => "1.1.1",
                                   "dependency-type" => "direct:development",
                                   "update-type" => "version-update:semver-minor",
                                 }],
                               })
      }
    end

    context "with multiple updates" do
      let(:updated_dependencies) do
        [
          Dependabot::Dependency.new(
            name: "business",
            version: "1.1.1",
            previous_version: "1.0.0",
            requirements: [],
            previous_requirements: [],
            package_manager: "bundler",
          ),
          Dependabot::Dependency.new(
            name: "excon",
            version: "3.0.0",
            previous_version: "2.0.0",
            requirements: [{ file: "Gemfile", requirement: "~> 3.0.0", groups: [], source: nil }],
            previous_requirements: [{ file: "Gemfile", requirement: "~> 2.0.0", groups: [], source: nil }],
            package_manager: "bundler",
          ),
        ]
      end

      it {
        expect(metadata).to eq({
                                 "updated-dependencies" => [{
                                   "dependency-name" => "business",
                                   "dependency-version" => "1.1.1",
                                   "dependency-type" => "indirect",
                                   "update-type" => "version-update:semver-minor",
                                 }, {
                                   "dependency-name" => "excon",
                                   "dependency-version" => "3.0.0",
                                   "dependency-type" => "direct:production",
                                   "update-type" => "version-update:semver-major",
                                 },],
                               })
      }
    end

    context "with a grouped update" do
      let(:dependency_group) do
        create(:dependency_group, name: "my-deps")
      end

      let(:updated_dependencies) do
        [
          Dependabot::Dependency.new(
            name: "business",
            version: "1.1.1",
            previous_version: "1.0.0",
            requirements: [],
            previous_requirements: [],
            package_manager: "bundler",
          ),
          Dependabot::Dependency.new(
            name: "excon",
            version: "3.0.0",
            previous_version: "2.0.0",
            requirements: [{ file: "Gemfile", requirement: "~> 3.0.0", groups: [], source: nil }],
            previous_requirements: [{ file: "Gemfile", requirement: "~> 2.0.0", groups: [], source: nil }],
            package_manager: "bundler",
          ),
        ]
      end

      it {
        expect(metadata).to eq({
                                 "updated-dependencies" => [{
                                   "dependency-name" => "business",
                                   "dependency-version" => "1.1.1",
                                   "dependency-type" => "indirect",
                                   "update-type" => "version-update:semver-minor",
                                   "dependency-group" => "my-deps",
                                 }, {
                                   "dependency-name" => "excon",
                                   "dependency-version" => "3.0.0",
                                   "dependency-type" => "direct:production",
                                   "update-type" => "version-update:semver-major",
                                   "dependency-group" => "my-deps",
                                 },],
                               })
      }
    end
  end
end
