# frozen_string_literal: true

require "rails_helper"

RSpec.describe IgnoreCondition, type: :model do
  def build_ignore_condition(version_requirement, package_manager:, update_types: [])
    update_config = FactoryBot.build_stubbed(:update_config, package_manager: package_manager)
    FactoryBot.build_stubbed(
      :ignore_condition,
      version_requirement: version_requirement,
      update_config: update_config,
      update_types: update_types
    )
  end

  describe "validations" do
    it "when version requirement matches package manager" do
      expect(build_ignore_condition(">= 2.0, < 3", package_manager: "bundler")).to be_valid
    end

    it "with a bad version_requirement string" do
      ignore_condition = build_ignore_condition("a", package_manager: "bundler")
      expect(ignore_condition).not_to be_valid
      expect(ignore_condition.errors).to include(:version_requirement)
    end

    it "ensures presence of update types XOR version requirement" do
      ignore_condition = FactoryBot.build(:ignore_condition, version_requirement: nil, update_types: nil)
      expect(ignore_condition).not_to be_valid
      expect(ignore_condition.errors).to include(:version_requirement, :update_types)

      ignore_condition.update(version_requirement: "4.x", update_types: ["version-update:semver-patch"])
      expect(ignore_condition).not_to be_valid
      expect(ignore_condition.errors).to include(:version_requirement, :update_types)

      ignore_condition.update(version_requirement: "4.x", update_types: nil)
      expect(ignore_condition).to be_valid

      ignore_condition.update(version_requirement: nil, update_types: ["version-update:semver-patch"])
      expect(ignore_condition).to be_valid
    end
  end

  describe "#parsed_version_requirements" do
    def parsed_version_requirements(version_requirement, package_manager)
      build_ignore_condition(version_requirement, package_manager: package_manager).parsed_version_requirements
    end

    it do
      expect(parsed_version_requirements(">= 2.0, < 3", "bundler")).
        to eq([Gem::Requirement.new(">= 2.0", "< 3")])
    end

    it "with multiple gradle requirements" do
      expect(parsed_version_requirements("(,1.0.0),(2.0.0,)", "gradle")).
        to eq([
                Dependabot::Gradle::Requirement.new("< 1.0.0"),
                Dependabot::Gradle::Requirement.new("> 2.0.0"),
              ])
    end

    it "when only update types is set" do
      ignore_condition = build_ignore_condition(
        nil,
        package_manager: "bundler",
        update_types: ["version-update:semver-patch"]
      )
      expect(ignore_condition.parsed_version_requirements).to eq([])
    end
  end

  describe "#includes?" do
    def includes?(version_requirement, package_manager, version_string)
      build_ignore_condition(version_requirement, package_manager: package_manager).includes?(version_string)
    end

    it "with an in-range version string" do
      expect(includes?(">= 2.0, < 3", "bundler", "2.2.0")).to be_truthy
    end

    it "with an out of range version string" do
      expect(includes?(">= 2.0, < 3", "bundler", "1.2.0")).to be_falsy
    end

    it "with an invalid version" do
      expect(includes?(">= 2.0, < 3", "bundler", "a")).to be_falsy
    end

    it "when ignoring all versions" do
      version_requirement = ">= 0"
      package_manager = "bundler"
      expect(includes?(version_requirement, package_manager, "asdfasdfasd")).to be_truthy
      expect(includes?(version_requirement, package_manager, "1.0")).to be_truthy
    end

    it "doesn't check includes when only update types is set" do
      ignore_condition = build_ignore_condition(
        nil,
        package_manager: "bundler",
        update_types: ["version-update:semver-patch"]
      )
      expect(ignore_condition).not_to be_includes("2.2.0")
    end

    [
      ["npm_and_yarn",   "> 2.0, < 4.3.1", "2.1"],
      ["npm_and_yarn",   "4.3.1", "4.3.1"],

      ["bundler",        ">= 2.0, < 4.3.1", "3.0.0"],
      ["bundler",        "2.0.1", "2.0.1"],

      ["cargo",          "> 2.0.1-pre, <= 3.0.0-pre1", "2.9.9-pre1"],
      ["cargo",          ">= 2.0.1, < 3.0.0", "2.6.9"],
      ["cargo",          "2.0.1", "2.0.1"],

      ["docker",         ">= 2.0.1, < 3.0.0", "2.9.9"],
      ["docker",         "2.0.1", "2.0.1"],

      ["elm",            ">= 2.0.1, < 3.0.0", "2.0.1"],
      ["elm",            "2.0.1", "2.0.1"],

      ["submodules",     ">= 2.0.1, < 3.0.0", "2.2.0"],
      ["submodules",     "2.0.1", "2.0.1"],

      ["github_actions", ">= 2.0.1, < 3.0.0", "2.8.9"],
      ["github_actions", "2.0.1", "2.0.1"],

      ["go_modules",     ">= 2.0.1, < v3.0.0+incompatible", "v2.2.0+incompatible"],
      ["go_modules",     "> 1.0.0.pre1, < 2.0.0.pre1", "1.2.0.pre1"],
      ["go_modules",     "2.0.1", "2.0.1"],

      ["hex",            ">= 2.0.1, < 3.0.0", "2.2.0"],
      ["hex",            "2.0.1", "2.0.1"],

      ["composer",       ">= 2.0.1, < 3.0.0", "2.2.0"],
      ["composer",       "2.0.1", "2.0.1"],

      ["pip",            ">= 2.0.1+abc.1, < 3.0.0", "2.2.0+abc.2"],
      ["pip",            "2.0.1", "2.0.1"],

      ["terraform",      ">= 2.0.1, < 3.0.0", "2.2.0"],
      ["terraform",      "2.0.1", "2.0.1"],

      ["nuget",          ">= 2.0.1, < 3.0.0", "2.2.0"],
      ["nuget",          "1.0", "1.0"],
      ["nuget",          "(,2.0.1]", "1.9.0"],
      ["nuget",          "[1,2.0.1]", "1.1.1"],
      ["nuget",          "[1.3.2,1.5)", "1.3.3"],

      ["gradle",         ">= 2.0.11.40-eap13-67, < 3.0.0", "2.2.0.40-eap13-67"],
      ["gradle",         ">= Finchley.SR3, < Finchley.9999999", "Finchley.SR4"],
      ["gradle",         "1.0", "1.0"],
      ["gradle",         "(,2.0.1]", "1.9.0"],
      ["gradle",         "[1,2.0.1]", "1.1.1"],
      ["gradle",         "[1.3.2,1.5)", "1.3.3"],

      ["maven",          ">= 2.0.1.40-eap13-67, < 3.0.0", "2.2.0.40-eap13-67"],
      ["maven",          ">= Finchley.SR3, < Finchley.9999999", "Finchley.SR4"],
      ["maven",          "1.0", "1.0"],
      ["maven",          "(,2.0.1]", "1.9.0"],
      ["maven",          "[1,2.0.1]", "1.1.1"],
      ["maven",          "[1.3.2,1.5)", "1.3.3"],
    ].each do |package_manager, version_requirement, version_string|
      it "includes #{package_manager} version #{version_requirement}" do
        expect(includes?(version_requirement, package_manager, version_string)).to be_truthy
      end
    end
  end
end
