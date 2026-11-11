# frozen_string_literal: true

require "rails_helper"
require "labelizer"

RSpec.describe Labelizer do
  subject(:labelizer) { described_class.new(update_config: update_config, dependencies: dependencies) }

  let(:update_config) { create(:update_config, package_manager: "bundler") }
  let(:update_job) { create(:update_job, update_config: update_config) }
  let(:dependencies) do
    [
      Dependabot::Dependency.new(
        name: "foo",
        version: "1.0.0",
        requirements: [],
        package_manager: "bundler",
        previous_version: "0.9.0",
        previous_requirements: []
      ),
    ]
  end

  describe "#labels" do
    context "when custom labels are not set" do
      it "returns the default labels and the semver" do
        expect(labelizer.labels).to eq(
          [
            {
              name: "dependencies",
              color: Labelizer::LIGHT_BLUE,
              description: "Pull requests that update a dependency file",
              is_custom: false,
            },
            { name: "ruby", color: "ce2d2d", description: "Pull requests that update ruby code", is_custom: false },
            { name: "major", is_custom: false },
          ].map { |label| MonolithTwirp::Dependabot::PullRequests::V1::Label.new(label) }
        )
      end
    end

    context "when custom labels are set" do
      let(:update_config) { create(:update_config, custom_labels: ["foo"]) }

      it "returns the custom labels and the semver" do
        expect(labelizer.labels).to eq(
          [
            MonolithTwirp::Dependabot::PullRequests::V1::Label.new(name: "foo", is_custom: true),
            MonolithTwirp::Dependabot::PullRequests::V1::Label.new(name: "major", is_custom: false),
          ]
        )
      end
    end

    context "when the dependency does not have a version" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "foo",
            requirements: [],
            package_manager: "bundler",
            previous_version: "world",
            previous_requirements: []
          ),
        ]
      end

      it "does not return a semver label" do
        expect(labelizer.labels).to eq(
          [
            {
              name: "dependencies",
              color: Labelizer::LIGHT_BLUE,
              description: "Pull requests that update a dependency file",
              is_custom: false,
            },
            { name: "ruby", color: "ce2d2d", description: "Pull requests that update ruby code", is_custom: false },
          ].map { |label| MonolithTwirp::Dependabot::PullRequests::V1::Label.new(label) }
        )
      end
    end

    context "when the dependency is non-semver" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "foo",
            version: "hello",
            requirements: [],
            package_manager: "bundler",
            previous_version: "world",
            previous_requirements: []
          ),
        ]
      end

      it "returns the non-semver label" do
        expect(labelizer.labels).to eq(
          [
            {
              name: "dependencies",
              color: Labelizer::LIGHT_BLUE,
              description: "Pull requests that update a dependency file",
              is_custom: false,
            },
            { name: "ruby", color: "ce2d2d", description: "Pull requests that update ruby code", is_custom: false },
            { name: "non-semver", is_custom: false },
          ].map { |label| MonolithTwirp::Dependabot::PullRequests::V1::Label.new(label) }
        )
      end
    end

    context "when the dependency is minor" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "foo",
            version: "1.1.0",
            requirements: [],
            package_manager: "bundler",
            previous_version: "1.0.0",
            previous_requirements: []
          ),
        ]
      end

      it "returns the minor label" do
        expect(labelizer.labels).to eq(
          [
            {
              name: "dependencies",
              color: Labelizer::LIGHT_BLUE,
              description: "Pull requests that update a dependency file",
              is_custom: false,
            },
            { name: "ruby", color: "ce2d2d", description: "Pull requests that update ruby code", is_custom: false },
            { name: "minor", is_custom: false },
          ].map { |label| MonolithTwirp::Dependabot::PullRequests::V1::Label.new(label) }
        )
      end
    end

    context "when the dependency is patch" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "foo",
            version: "1.0.1",
            requirements: [],
            package_manager: "bundler",
            previous_version: "1.0.0",
            previous_requirements: []
          ),
        ]
      end

      it "returns the patch label" do
        expect(labelizer.labels).to eq(
          [
            {
              name: "dependencies",
              color: Labelizer::LIGHT_BLUE,
              description: "Pull requests that update a dependency file",
              is_custom: false,
            },
            { name: "ruby", color: "ce2d2d", description: "Pull requests that update ruby code", is_custom: false },
            { name: "patch", is_custom: false },
          ].map { |label| MonolithTwirp::Dependabot::PullRequests::V1::Label.new(label) }
        )
      end
    end
  end
end
