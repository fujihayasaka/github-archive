# frozen_string_literal: true

require "rails_helper"

RSpec.describe FindOrRemoveIgnoreCondition do
  subject(:run) { action.run }

  let!(:action) do
    described_class.new(
      pull_request: pull_request,
      dep_name: dep_name,
      version_requirement_to_remove: version_requirement_to_remove,
    )
  end

  let(:dep_name) { "business" }
  let(:version_requirement_to_remove) { "< 1.9.0, > 1.3.0" }

  let!(:pull_request) do
    FactoryBot.create(:pull_request, dependencies: dependencies, github_number: 18)
  end
  let!(:another_pull_request) do
    FactoryBot.create(:pull_request, dependencies: dependencies, github_number: 20)
  end
  let(:dependencies) { [dependency] }
  let!(:dependency) do
    {
      name: "business",
      version: "1.8.0",
      previous_version: "1.3.0",
      requirements: [],
      previous_requirements: [],
      package_manager: "bundler",
    }
  end
  let(:requirements) { [] }
  let(:previous_requirements) { [] }

  context "asking to unignore an ignore condition of a specific dependency in a pull request" do
    let(:dep_name) { "business" }
    let(:version_requirement_to_remove) { "< 1.9.0, > 1.3.0" }
    let(:dependencies) { [dependency, another_dependency] }
    let!(:another_dependency) do
      {
        name: "statesman",
        version: "2.2.0",
        previous_version: "2.1.0",
        requirements: requirements,
        previous_requirements: previous_requirements,
        package_manager: "bundler",
      }
    end
    let!(:ignore_conditions) do
      [
        FactoryBot.create(
          :ignore_condition,
          version_requirement: "< 1.9.0, > 1.3.0",
          dependency_name: "business",
          update_config: pull_request.update_config,
          from_config_file: false,
        ),
        FactoryBot.create(
          :ignore_condition,
          version_requirement: "< 2, > 1.3.0",
          dependency_name: "business",
          update_config: pull_request.update_config,
          from_config_file: false,
        ),
      ]
    end

    it "removes a specific ignore condition of the specified dependency" do
      ignore_conditions
      expect(IgnoreCondition.count).to eq(2)
      expect(run).to eq(true)
      expect(IgnoreCondition.count).to eq(1)
      expect(IgnoreCondition.find_by(dependency_name: "business").version_requirement).to eq("< 2, > 1.3.0")
    end
  end

  context "asking to unignore all ignore conditions of a specific dependency in a pull request" do
    let(:dep_name) { "business" }
    let(:version_requirement_to_remove) { nil }
    let(:dependencies) { [dependency, another_dependency] }
    let!(:another_dependency) do
      {
        name: "statesman",
        version: "2.2.0",
        previous_version: "2.1.0",
        requirements: requirements,
        previous_requirements: previous_requirements,
        package_manager: "bundler",
      }
    end
    let!(:ignore_conditions) do
      [
        FactoryBot.create(
          :ignore_condition,
          version_requirement: "< 1.9.0, > 1.3.0",
          dependency_name: "business",
          update_config: pull_request.update_config,
          from_config_file: false,
        ),
        FactoryBot.create(
          :ignore_condition,
          version_requirement: "< 2, > 1.3.0",
          dependency_name: "business",
          update_config: pull_request.update_config,
          from_config_file: false,
        ),
        FactoryBot.create(
          :ignore_condition,
          version_requirement: "< 2, > 1.3.0",
          dependency_name: "statesman",
          update_config: pull_request.update_config,
          from_config_file: false,
        ),
      ]
    end

    it "removes all the ignore conditions only for the specified dependency" do
      ignore_conditions
      expect(IgnoreCondition.count).to eq(3)
      expect(run).to eq(true)
      expect(IgnoreCondition.count).to eq(1)
      expect(IgnoreCondition.find_by(dependency_name: "business")).to be_nil
    end
  end

  context "when there is an ignore condition of a specific dependency in another pull request" do
    let(:dep_name) { "business" }
    let(:version_requirement_to_remove) { "< 1.9.0, > 1.3.0" }
    let(:dependencies) { [dependency, another_dependency] }
    let!(:another_dependency) do
      {
        name: "statesman",
        version: "2.2.0",
        previous_version: "2.1.0",
        requirements: requirements,
        previous_requirements: previous_requirements,
        package_manager: "bundler",
      }
    end
    let!(:ignore_conditions) do
      [
        FactoryBot.create(
          :ignore_condition,
          version_requirement: "< 1.9.0, > 1.3.0",
          dependency_name: "business",
          update_config: another_pull_request.update_config,
          from_config_file: false,
        ),
        FactoryBot.create(
          :ignore_condition,
          version_requirement: "< 2, > 1.3.0",
          dependency_name: "business",
          update_config: pull_request.update_config,
          from_config_file: false,
        ),
      ]
    end

    it "does not remove it" do
      ignore_conditions
      expect(IgnoreCondition.count).to eq(2)
      expect(run).to eq(false)
      expect(IgnoreCondition.count).to eq(2)
      expect(IgnoreCondition.find_by(dependency_name: "business").version_requirement).to eq("< 1.9.0, > 1.3.0")
    end
  end

  context "does not remove all ignore condition of a specific dependency of an another pull request" do
    let(:dep_name) { "business" }
    let(:dependencies) { [dependency, another_dependency] }
    let!(:another_dependency) do
      {
        name: "statesman",
        version: "2.2.0",
        previous_version: "2.1.0",
        requirements: requirements,
        previous_requirements: previous_requirements,
        package_manager: "bundler",
      }
    end
    let(:specific_version_requirement) { "< 2, > 1.3.0" }
    let!(:ignore_conditions) do
      [
        FactoryBot.create(
          :ignore_condition,
          version_requirement: "< 1.9.0, > 1.3.0",
          dependency_name: "business",
          update_config: pull_request.update_config,
          from_config_file: false,
        ),
        FactoryBot.create(
          :ignore_condition,
          version_requirement: specific_version_requirement,
          dependency_name: "business",
          update_config: another_pull_request.update_config,
          from_config_file: false,
        ),
        FactoryBot.create(
          :ignore_condition,
          version_requirement: ">= 2.2.0, < 2.3.0",
          dependency_name: "statesman",
          update_config: another_pull_request.update_config,
          from_config_file: false,
        ),
      ]
    end

    it "does not removes all the ignore conditions of a specific dependency" do
      ignore_conditions
      expect(IgnoreCondition.count).to eq(3)
      expect(run).to eq(true)
      expect(IgnoreCondition.count).to eq(2)
      matching_conditions = IgnoreCondition.where(
        dependency_name: "business",
        version_requirement: specific_version_requirement
      )
      expect(matching_conditions.count).to eq(1)
      expect(IgnoreCondition.where(dependency_name: "statesman").count).to eq(1)
    end
  end

  context "does not remove all ignore condition of all the dependency of an another pull request" do
    let(:dep_name) { "*" }
    let(:dependencies) { [dependency, another_dependency] }
    let!(:another_dependency) do
      {
        name: "statesman",
        version: "2.2.0",
        previous_version: "2.1.0",
        requirements: requirements,
        previous_requirements: previous_requirements,
        package_manager: "bundler",
      }
    end
    let!(:ignore_conditions) do
      [
        FactoryBot.create(
          :ignore_condition,
          version_requirement: "< 1.9.0, > 1.3.0",
          dependency_name: "business",
          update_config: another_pull_request.update_config,
          from_config_file: false,
        ),
        FactoryBot.create(
          :ignore_condition,
          version_requirement: "< 2, > 1.3.0",
          dependency_name: "business",
          update_config: another_pull_request.update_config,
          from_config_file: false,
        ),
        FactoryBot.create(
          :ignore_condition,
          version_requirement: ">= 2.2.0, < 2.3.0",
          dependency_name: "statesman",
          update_config: another_pull_request.update_config,
          from_config_file: false,
        ),
      ]
    end

    it "does not removes all the ignore conditions of all dependencies" do
      ignore_conditions
      expect(IgnoreCondition.count).to eq(3)
      expect(run).to eq(false)
      expect(IgnoreCondition.count).to eq(3)
      expect(IgnoreCondition.find_by(dependency_name: "business")).not_to be_nil
      expect(IgnoreCondition.find_by(dependency_name: "statesman")).not_to be_nil
    end
  end

  context "does not remove ignore condition on dependencies from the config file" do
    let(:dep_name) { "business" }
    let(:version_requirement_to_remove) { "< 1.9.0, > 1.3.0" }
    let(:dependencies) { [dependency, another_dependency] }
    let!(:another_dependency) do
      {
        name: "statesman",
        version: "2.2.0",
        previous_version: "2.1.0",
        requirements: requirements,
        previous_requirements: previous_requirements,
        package_manager: "bundler",
      }
    end
    let!(:ignore_conditions) do
      [
        FactoryBot.create(
          :ignore_condition,
          version_requirement: "< 1.9.0, > 1.3.0",
          dependency_name: "business",
          update_config: pull_request.update_config,
          from_config_file: false,
        ),
        FactoryBot.create(
          :ignore_condition,
          version_requirement: "< 2, > 1.3.0",
          dependency_name: "business",
          update_config: pull_request.update_config,
          from_config_file: true,
        ),
      ]
    end

    it "does not remove ignore conditions from config file" do
      ignore_conditions
      expect(IgnoreCondition.count).to eq(2)
      expect(run).to eq(true)
      expect(IgnoreCondition.count).to eq(1)
      expect(IgnoreCondition.find_by(dependency_name: "business").version_requirement).to eq("< 2, > 1.3.0")
    end
  end

  context "when ignore condition is empty" do
    let(:dep_name) { "business" }
    let(:version_requirement_to_remove) { "< 1.9.0, > 1.3.0" }
    let(:dependencies) { [dependency, another_dependency] }
    let!(:another_dependency) do
      {
        name: "statesman",
        version: "2.2.0",
        previous_version: "2.1.0",
        requirements: requirements,
        previous_requirements: previous_requirements,
        package_manager: "bundler",
      }
    end
    let(:ignore_conditions) do
      []
    end

    it "No not remove ignore conditions" do
      ignore_conditions
      expect(IgnoreCondition.count).to eq(0)
      expect(run).to eq(false)
    end
  end

  context "asking to unignore an ignore condition of a specific dependency in a GU pull request" do
    let(:dep_name) { "business" }
    let(:version_requirement_to_remove) { "< 1.9.0, > 1.3.0" }
    let(:dependencies) { [dependency, another_dependency] }
    let!(:another_dependency) do
      {
        name: "statesman",
        version: "2.2.0",
        previous_version: "2.1.0",
        requirements: requirements,
        previous_requirements: previous_requirements,
        package_manager: "bundler",
      }
    end
    let!(:ignore_conditions) do
      [
        FactoryBot.create(
          :ignore_condition,
          version_requirement: "< 1.9.0, > 1.3.0",
          dependency_name: "business",
          update_config: pull_request.update_config,
          from_config_file: false,
        ),
        FactoryBot.create(
          :ignore_condition,
          version_requirement: "< 2, > 1.3.0",
          dependency_name: "business",
          update_config: pull_request.update_config,
          from_config_file: false,
        ),
      ]
    end

    before do
      pull_request.update(grouped_update: true)
    end

    it "removes a specific ignore condition of the specified dependency" do
      ignore_conditions
      expect(IgnoreCondition.count).to eq(2)
      expect(run).to eq(true)
      expect(IgnoreCondition.count).to eq(1)
      expect(IgnoreCondition.find_by(dependency_name: "business").version_requirement).to eq("< 2, > 1.3.0")
    end
  end

  context "asking to unignore all ignore conditions of a specific dependency in a GU pull request" do
    let(:dep_name) { "business" }
    let(:version_requirement_to_remove) { nil }
    let(:dependencies) { [dependency, another_dependency] }
    let!(:another_dependency) do
      {
        name: "statesman",
        version: "2.2.0",
        previous_version: "2.1.0",
        requirements: requirements,
        previous_requirements: previous_requirements,
        package_manager: "bundler",
      }
    end
    let(:ignore_conditions) do
      [
        FactoryBot.create(
          :ignore_condition,
          version_requirement: "< 1.9.0, > 1.3.0",
          dependency_name: "business",
          update_config: pull_request.update_config,
          from_config_file: false,
        ),
        FactoryBot.create(
          :ignore_condition,
          version_requirement: "< 2, > 1.3.0",
          dependency_name: "business",
          update_config: pull_request.update_config,
          from_config_file: false,
        ),
        FactoryBot.create(
          :ignore_condition,
          version_requirement: "< 2, > 1.3.0",
          dependency_name: "statesman",
          update_config: pull_request.update_config,
          from_config_file: false,
        ),
      ]
    end

    before do
      pull_request.update(grouped_update: true)
    end

    it "removes all the ignore conditions only for the specified dependency" do
      ignore_conditions
      expect(IgnoreCondition.count).to eq(3)
      expect(run).to eq(true)
      expect(IgnoreCondition.count).to eq(1)
      expect(IgnoreCondition.find_by(dependency_name: "business")).to be_nil
    end
  end

  context "does not remove an ignore condition of a specific dependency of an another GU pull request" do
    let(:dep_name) { "business" }
    let(:version_requirement_to_remove) { "< 1.9.0, > 1.3.0" }
    let(:dependencies) { [dependency, another_dependency] }
    let!(:another_dependency) do
      {
        name: "statesman",
        version: "2.2.0",
        previous_version: "2.1.0",
        requirements: requirements,
        previous_requirements: previous_requirements,
        package_manager: "bundler",
      }
    end
    let!(:ignore_conditions) do
      [
        FactoryBot.create(
          :ignore_condition,
          version_requirement: "< 1.9.0, > 1.3.0",
          dependency_name: "business",
          update_config: another_pull_request.update_config,
          from_config_file: false,
        ),
        FactoryBot.create(
          :ignore_condition,
          version_requirement: "< 2, > 1.3.0",
          dependency_name: "business",
          update_config: pull_request.update_config,
          from_config_file: false,
        ),
      ]
    end

    before do
      pull_request.update(grouped_update: true)
      another_pull_request.update(grouped_update: true)
    end

    it "removes a specific ignore condition of the specified dependency" do
      ignore_conditions
      expect(IgnoreCondition.count).to eq(2)
      expect(run).to eq(false)
      expect(IgnoreCondition.count).to eq(2)
      expect(IgnoreCondition.find_by(dependency_name: "business").version_requirement).to eq("< 1.9.0, > 1.3.0")
    end
  end

  context "does not remove all ignore condition of a specific dependency of an another GU pull request" do
    let(:dep_name) { "business" }
    let(:dependencies) { [dependency, another_dependency] }
    let!(:another_dependency) do
      {
        name: "statesman",
        version: "2.2.0",
        previous_version: "2.1.0",
        requirements: requirements,
        previous_requirements: previous_requirements,
        package_manager: "bundler",
      }
    end
    let(:specific_version_requirement) { "< 2, > 1.3.0" }
    let!(:ignore_conditions) do
      [
        FactoryBot.create(
          :ignore_condition,
          version_requirement: "< 1.9.0, > 1.3.0",
          dependency_name: "business",
          update_config: pull_request.update_config,
          from_config_file: false,
        ),
        FactoryBot.create(
          :ignore_condition,
          version_requirement: specific_version_requirement,
          dependency_name: "business",
          update_config: another_pull_request.update_config,
          from_config_file: false,
        ),
        FactoryBot.create(
          :ignore_condition,
          version_requirement: ">= 2.2.0, < 2.3.0",
          dependency_name: "statesman",
          update_config: another_pull_request.update_config,
          from_config_file: false,
        ),
      ]
    end

    before do
      pull_request.update(grouped_update: true)
      another_pull_request.update(grouped_update: true)
    end

    it "does not removes all the ignore conditions of a specific dependency" do
      ignore_conditions
      expect(IgnoreCondition.count).to eq(3)
      expect(run).to eq(true)
      expect(IgnoreCondition.count).to eq(2)
      matching_conditions = IgnoreCondition.where(
        dependency_name: "business",
        version_requirement: specific_version_requirement
      )
      expect(matching_conditions.count).to eq(1)
      expect(IgnoreCondition.where(dependency_name: "statesman").count).to eq(1)
    end
  end

  context "does not remove all ignore condition of all the dependency of an another GU pull request" do
    let(:dep_name) { "*" }
    let(:dependencies) { [dependency, another_dependency] }
    let!(:another_dependency) do
      {
        name: "statesman",
        version: "2.2.0",
        previous_version: "2.1.0",
        requirements: requirements,
        previous_requirements: previous_requirements,
        package_manager: "bundler",
      }
    end

    let!(:ignore_conditions) do
      [
        FactoryBot.create(
          :ignore_condition,
          version_requirement: "< 1.9.0, > 1.3.0",
          dependency_name: "business",
          update_config: another_pull_request.update_config,
          from_config_file: false,
        ),
        FactoryBot.create(
          :ignore_condition,
          version_requirement: "< 2, > 1.3.0",
          dependency_name: "business",
          update_config: another_pull_request.update_config,
          from_config_file: false,
        ),
        FactoryBot.create(
          :ignore_condition,
          version_requirement: ">= 2.2.0, < 2.3.0",
          dependency_name: "statesman",
          update_config: another_pull_request.update_config,
          from_config_file: false,
        ),
      ]
    end

    before do
      pull_request.update(grouped_update: true)
      another_pull_request.update(grouped_update: true)
    end

    it "does not removes all the ignore conditions of all dependencies" do
      ignore_conditions
      expect(IgnoreCondition.count).to eq(3)
      expect(run).to eq(false)
      expect(IgnoreCondition.count).to eq(3)
      expect(IgnoreCondition.find_by(dependency_name: "business")).not_to be_nil
      expect(IgnoreCondition.find_by(dependency_name: "statesman")).not_to be_nil
    end
  end

  context "does not remove ignore condition on dependencies from the config file (GU)" do
    let(:dep_name) { "business" }
    let(:version_requirement_to_remove) { "< 1.9.0, > 1.3.0" }
    let(:dependencies) { [dependency, another_dependency] }
    let!(:another_dependency) do
      {
        name: "statesman",
        version: "2.2.0",
        previous_version: "2.1.0",
        requirements: requirements,
        previous_requirements: previous_requirements,
        package_manager: "bundler",
      }
    end
    let!(:ignore_conditions) do
      [
        FactoryBot.create(
          :ignore_condition,
          version_requirement: "< 1.9.0, > 1.3.0",
          dependency_name: "business",
          update_config: pull_request.update_config,
          from_config_file: false,
        ),
        FactoryBot.create(
          :ignore_condition,
          version_requirement: "< 2, > 1.3.0",
          dependency_name: "business",
          update_config: pull_request.update_config,
          from_config_file: true,
        ),
      ]
    end

    before do
      pull_request.update(grouped_update: true)
    end

    it "does not remove ignore conditions from config file" do
      ignore_conditions
      expect(IgnoreCondition.count).to eq(2)
      expect(run).to eq(true)
      expect(IgnoreCondition.count).to eq(1)
      expect(IgnoreCondition.find_by(dependency_name: "business").version_requirement).to eq("< 2, > 1.3.0")
    end
  end

  context "when ignore condition is empty (GU)" do
    let(:dep_name) { "business" }
    let(:version_requirement_to_remove) { "< 1.9.0, > 1.3.0" }
    let(:dependencies) { [dependency, another_dependency] }
    let!(:another_dependency) do
      {
        name: "statesman",
        version: "2.2.0",
        previous_version: "2.1.0",
        requirements: requirements,
        previous_requirements: previous_requirements,
        package_manager: "bundler",
      }
    end
    let(:ignore_conditions) do
      []
    end

    before do
      pull_request.update(grouped_update: true)
    end

    it "does not remove ignore conditions" do
      ignore_conditions
      expect(IgnoreCondition.count).to eq(0)
      expect(run).to eq(false)
    end
  end
end
