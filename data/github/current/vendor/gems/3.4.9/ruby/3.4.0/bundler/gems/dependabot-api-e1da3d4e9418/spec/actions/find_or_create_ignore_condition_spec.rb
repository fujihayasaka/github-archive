# frozen_string_literal: true

require "rails_helper"

RSpec.describe FindOrCreateIgnoreCondition do
  subject(:run) { action.run }

  let(:action) do
    described_class.new(
      pull_request: pull_request,
      precision_to_ignore: precision_to_ignore,
      dep_name: dep_name,
    )
  end

  let(:dep_name) { nil }

  let(:pull_request) do
    FactoryBot.create(:pull_request, dependencies: dependencies)
  end
  let(:dependencies) { [dependency] }
  let(:dependency) do
    {
      name: dependency_name,
      version: version,
      previous_version: previous_version,
      requirements: requirements,
      previous_requirements: previous_requirements,
      package_manager: "bundler",
    }
  end
  let(:version) { "1.8.0" }
  let(:previous_version) { "1.3.0" }
  let(:dependency_name) { "business" }
  let(:requirements) { [] }
  let(:previous_requirements) { [] }

  context "asking to ignore the dependency entirely" do
    let(:precision_to_ignore) { 1 }

    it "creates the correct ignore condition" do
      expect(IgnoreCondition.count).to eq(0)
      expect(run).to eq(true)
      expect(IgnoreCondition.count).to eq(1)
      ignore_condition = IgnoreCondition.last
      expect(ignore_condition.parsed_version_requirements).
        to eq([Gem::Requirement.new("> 1.3.0")])
    end

    context "when the PR has been merged" do
      let(:pull_request) do
        FactoryBot.create(:pull_request, :merged, dependencies: dependencies)
      end

      it "uses the updated version" do
        expect(IgnoreCondition.count).to eq(0)
        expect(run).to eq(true)
        expect(IgnoreCondition.count).to eq(1)
        ignore_condition = IgnoreCondition.last
        expect(ignore_condition.parsed_version_requirements).
          to eq([Gem::Requirement.new("> 1.8.0")])
      end
    end

    context "when an ignore condition already exists" do
      before do
        pull_request.update_config.ignore_conditions.create!(
          dependency_name: "business",
          version_requirement: "> 1.3.0",
        )
      end

      it "doesn't create an ignore condition" do
        expect(IgnoreCondition.count).to eq(1)
        expect(run).to eq(true)
        expect(IgnoreCondition.count).to eq(1)
      end
    end

    context "with a non-numeric version" do
      let(:version) { "ab121c5" }
      let(:previous_version) { "c712a6d" }

      it "creates the correct ignore condition" do
        expect(IgnoreCondition.count).to eq(0)
        expect(run).to eq(true)
        expect(IgnoreCondition.count).to eq(1)
        ignore_condition = IgnoreCondition.last
        expect(ignore_condition.parsed_version_requirements).
          to eq([Gem::Requirement.new(">= 0")])
      end
    end

    context "with no version" do
      let(:previous_version) { nil }

      it "creates the correct ignore condition" do
        expect(IgnoreCondition.count).to eq(0)
        expect(run).to eq(true)
        expect(IgnoreCondition.count).to eq(1)
        ignore_condition = IgnoreCondition.last
        expect(ignore_condition.parsed_version_requirements).
          to eq([Gem::Requirement.new(">= 0")])
      end
    end

    context "with a removed transitive dependency" do
      let(:removed_dependency) do
        {
          name: "removed",
          previous_version: "1.4.0",
          requirements: [],
          previous_requirements: [],
          package_manager: "bundler",
          removed: true,
        }
      end
      let(:dependencies) { [removed_dependency, dependency] }

      it "creates the correct ignore condition" do
        expect(IgnoreCondition.count).to eq(0)
        expect(run).to eq(true)
        expect(IgnoreCondition.count).to eq(2)
        parent_ignore_condition = IgnoreCondition.find_by(dependency_name: dependency[:name])
        expect(parent_ignore_condition.parsed_version_requirements).
          to eq([Gem::Requirement.new("> 1.3.0")])
        removed_ignore_condition = IgnoreCondition.find_by(dependency_name: "removed")
        expect(removed_ignore_condition.parsed_version_requirements).
          to eq([Gem::Requirement.new("> 1.4.0")])
      end
    end
  end

  context "asking to ignore a major version" do
    let(:precision_to_ignore) { 2 }

    it "creates the correct ignore condition" do
      expect(IgnoreCondition.count).to eq(0)
      expect(run).to eq(true)
      expect(IgnoreCondition.count).to eq(1)
      ignore_condition = IgnoreCondition.last
      expect(ignore_condition.parsed_version_requirements).
        to eq([Gem::Requirement.new("< 2", "> 1.3.0")])
    end

    context "for a future major version" do
      let(:version) { "5.1.0" }

      it "creates the correct ignore condition" do
        expect(IgnoreCondition.count).to eq(0)
        expect(run).to eq(true)
        expect(IgnoreCondition.count).to eq(1)
        ignore_condition = IgnoreCondition.last
        expect(ignore_condition.parsed_version_requirements).
          to eq([Gem::Requirement.new(">= 5.a", "< 6")])
      end
    end

    context "with a future maven version" do
      let(:version) { "5.1.0" }

      before do
        pull_request.update_config.update!(package_manager: "maven")
      end

      it "creates the correct ignore condition" do
        expect(IgnoreCondition.count).to eq(0)
        expect(run).to eq(true)
        expect(IgnoreCondition.count).to eq(1)
        ignore_condition = IgnoreCondition.last
        expect(ignore_condition.parsed_version_requirements).
          to eq([Gem::Requirement.new(">= 5.a0", "< 6")])
      end
    end

    context "for a version that wouldn't be a valid Gem::Version" do
      let(:version) { "Finchley.SR3" }
      let(:previous_version) { "Edgeware.SR4" }

      before do
        pull_request.update_config.update!(package_manager: "maven")
      end

      it "creates the correct ignore condition" do
        expect(IgnoreCondition.count).to eq(0)
        expect(run).to eq(true)
        expect(IgnoreCondition.count).to eq(1)
        ignore_condition = IgnoreCondition.last
        expect(ignore_condition.parsed_version_requirements).
          to eq([Dependabot::Maven::Requirement.
                new(">= Finchley.a0", "< Finchley.999999")])
      end
    end

    context "with no version" do
      let(:previous_version) { nil }

      it "creates the correct ignore condition" do
        expect(IgnoreCondition.count).to eq(0)
        expect(run).to eq(true)
        expect(IgnoreCondition.count).to eq(1)
        ignore_condition = IgnoreCondition.last
        expect(ignore_condition.parsed_version_requirements).
          to eq([Gem::Requirement.new(">= 1.a", "< 2")])
      end

      context "with a maven version" do
        before do
          pull_request.update_config.update!(package_manager: "maven")
        end

        it "creates the correct ignore condition" do
          expect(IgnoreCondition.count).to eq(0)
          expect(run).to eq(true)
          expect(IgnoreCondition.count).to eq(1)
          ignore_condition = IgnoreCondition.last
          expect(ignore_condition.parsed_version_requirements).
            to eq([Gem::Requirement.new(">= 1.a0", "< 2")])
        end
      end

      context "but with requirements" do
        let(:requirements) do
          [
            {
              file: "Gemfile",
              requirement: "~> 1.8.0",
              groups: [],
              source: nil,
            },
          ]
        end
        let(:previous_requirements) do
          [
            {
              file: "Gemfile",
              requirement: "~> 1.3.0, < 1.8",
              groups: [],
              source: nil,
            },
          ]
        end

        it "creates the correct ignore condition" do
          expect(IgnoreCondition.count).to eq(0)
          expect(run).to eq(true)
          expect(IgnoreCondition.count).to eq(1)
          ignore_condition = IgnoreCondition.last
          expect(ignore_condition.parsed_version_requirements).
            to eq([Gem::Requirement.new("< 2", "> 1.3.0")])
        end
      end
    end
  end

  context "asking to ignore a major version of specific dependency" do
    let(:precision_to_ignore) { 2 }
    let(:dep_name) { "business" }
    let(:dependencies) { [dependency, another_dependency] }
    let(:another_dependency) do
      {
        name: "another_dependency",
        version: "2.2.0",
        previous_version: "2.1.0",
        requirements: requirements,
        previous_requirements: previous_requirements,
        package_manager: "bundler",
      }
    end

    it "creates an ignore condition only for the specified dependency" do
      expect(IgnoreCondition.count).to eq(0)
      expect(run).to eq(true)
      expect(IgnoreCondition.count).to eq(1)
      ignore_condition = IgnoreCondition.last
      expect(ignore_condition.dependency_name).to eq("business")
    end
  end

  context "asking to ignore a minor version of specific dependency" do
    let(:precision_to_ignore) { 3 }
    let(:dep_name) { "business" }
    let(:dependencies) { [dependency, another_dependency] }
    let(:another_dependency) do
      {
        name: "another_dependency",
        version: "2.2.0",
        previous_version: "2.1.0",
        requirements: requirements,
        previous_requirements: previous_requirements,
        package_manager: "bundler",
      }
    end

    it "creates an ignore condition only for the specified dependency" do
      expect(IgnoreCondition.count).to eq(0)
      expect(run).to eq(true)
      expect(IgnoreCondition.count).to eq(1)
      ignore_condition = IgnoreCondition.last
      expect(ignore_condition.dependency_name).to eq("business")
    end
  end
end
