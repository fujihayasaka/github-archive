# frozen_string_literal: true

require "rails_helper"
require "ecosystem_onboarding"

RSpec.describe EcosystemOnboarding do
  subject(:onboarding) do
    described_class.new(
      ecosystem_name: ecosystem_name,
      package_manager_name: package_manager_name,
      mode: mode
    )
  end

  let(:ecosystem_name) { "test_ecosystem" }
  let(:package_manager_name) { "test_ecosystem" }
  let(:mode) { "skip" }

  describe "#initialize" do
    it "sets the ecosystem name" do
      expect(onboarding.ecosystem_name).to eq("test_ecosystem")
    end

    it "sets the package manager name" do
      expect(onboarding.package_manager_name).to eq("test_ecosystem")
    end

    it "defaults package manager name to ecosystem name when not provided" do
      onboarding = described_class.new(ecosystem_name: "conda", mode: "skip")
      expect(onboarding.package_manager_name).to eq("conda")
    end

    it "sets the mode" do
      expect(onboarding.mode).to eq("skip")
    end

    it "converts ecosystem name to lowercase" do
      onboarding = described_class.new(ecosystem_name: "CONDA", mode: "skip")
      expect(onboarding.ecosystem_name).to eq("conda")
    end

    it "converts package manager name to lowercase" do
      onboarding = described_class.new(
        ecosystem_name: "test",
        package_manager_name: "TEST_PM",
        mode: "skip"
      )
      expect(onboarding.package_manager_name).to eq("test_pm")
    end

    context "with invalid mode" do
      let(:mode) { "invalid" }

      it "raises an ArgumentError" do
        expect { onboarding }.to raise_error(
          ArgumentError,
          /Invalid mode: invalid/
        )
      end
    end

    context "with valid modes" do
      %w(interactive skip overwrite).each do |valid_mode|
        it "accepts mode '#{valid_mode}'" do
          expect do
            described_class.new(ecosystem_name: "test", mode: valid_mode)
          end.not_to raise_error
        end
      end
    end
  end

  describe "#run" do
    let(:mode) { "skip" }

    it "completes without errors in skip mode" do
      expect { onboarding.run }.not_to raise_error
    end

    it "executes all updaters and collects results" do
      onboarding.run
      # In skip mode, no changes are made but execution completes successfully
      expect(onboarding.changes_made).to be_an(Array)
      expect(onboarding.manual_steps).to be_an(Array)
    end
  end

  describe "change tracking" do
    let(:mode) { "skip" }

    it "initializes with empty changes_made array" do
      expect(onboarding.changes_made).to eq([])
    end

    it "initializes with empty manual_steps array" do
      expect(onboarding.manual_steps).to eq([])
    end
  end
end
