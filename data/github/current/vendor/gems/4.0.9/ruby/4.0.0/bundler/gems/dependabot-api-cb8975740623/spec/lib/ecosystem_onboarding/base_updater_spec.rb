# frozen_string_literal: true

require "rails_helper"
require "ecosystem_onboarding"

RSpec.describe EcosystemOnboarding::BaseUpdater do
  subject(:updater) do
    described_class.new(
      ecosystem_name: ecosystem_name,
      package_manager_name: package_manager_name,
      root_path: Pathname.new("/test/path"),
      mode: mode
    )
  end

  let(:ecosystem_name) { "test_ecosystem" }
  let(:package_manager_name) { "test_ecosystem" }
  let(:mode) { "skip" }

  describe "#protobuf_constant_name" do
    it "converts ecosystem name to uppercase" do
      updater = described_class.new(
        ecosystem_name: "conda",
        package_manager_name: "conda",
        root_path: Pathname.new("/test"),
        mode: "skip"
      )
      expect(updater.send(:protobuf_constant_name)).to eq("CONDA")
    end

    it "converts hyphens to underscores" do
      updater = described_class.new(
        ecosystem_name: "docker-compose",
        package_manager_name: "docker-compose",
        root_path: Pathname.new("/test"),
        mode: "skip"
      )
      expect(updater.send(:protobuf_constant_name)).to eq("DOCKER_COMPOSE")
    end
  end

  describe "#package_manager_constant_name" do
    it "converts package manager name to uppercase" do
      updater = described_class.new(
        ecosystem_name: "npm",
        package_manager_name: "npm_and_yarn",
        root_path: Pathname.new("/test"),
        mode: "skip"
      )
      expect(updater.send(:package_manager_constant_name)).to eq("NPM_AND_YARN")
    end
  end

  describe "#should_proceed?" do
    let(:file_path) { Pathname.new("test.rb") }
    let(:change_description) { "Test change" }

    context "with overwrite mode" do
      let(:mode) { "overwrite" }

      it "always returns true" do
        expect(updater.send(:should_proceed?, file_path, change_description)).to be true
      end
    end

    context "with skip mode" do
      let(:mode) { "skip" }

      it "always returns false" do
        expect(updater.send(:should_proceed?, file_path, change_description)).to be false
      end
    end

    context "with interactive mode" do
      let(:mode) { "interactive" }

      it "prompts the user and processes response" do
        allow($stdin).to receive(:gets).and_return("y\n")
        result = updater.send(:should_proceed?, file_path, change_description)
        expect(result).to be true
      end

      it "returns true when user says yes" do
        allow($stdin).to receive(:gets).and_return("yes\n")
        expect(updater.send(:should_proceed?, file_path, change_description)).to be true
      end

      it "returns true when user says y" do
        allow($stdin).to receive(:gets).and_return("y\n")
        expect(updater.send(:should_proceed?, file_path, change_description)).to be true
      end

      it "returns false when user says no" do
        allow($stdin).to receive(:gets).and_return("no\n")
        expect(updater.send(:should_proceed?, file_path, change_description)).to be false
      end

      it "returns false when user presses enter" do
        allow($stdin).to receive(:gets).and_return("\n")
        expect(updater.send(:should_proceed?, file_path, change_description)).to be false
      end
    end
  end

  describe "#update" do
    it "raises NotImplementedError" do
      expect { updater.update }.to raise_error(NotImplementedError, "Subclasses must implement #update")
    end
  end
end
