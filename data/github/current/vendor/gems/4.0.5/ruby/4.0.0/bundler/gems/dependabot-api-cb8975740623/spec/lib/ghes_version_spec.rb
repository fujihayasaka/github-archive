# frozen_string_literal: true

require "spec_helper"
require "ghes_version"

RSpec.describe GhesVersion do
  describe "initialization" do
    it "accepts a version string" do
      expect(described_class.new("3.7")).to be_a(described_class)
    end

    it "blows up when given a non-version string" do
      expect { described_class.new("foo") }.to raise_error(ArgumentError)
    end
  end

  describe ".current" do
    it "reflects the version from the dynamic workflow" do
      dynamic_workflow_version_tag = RunUpdater::Actions::Workflow::CURRENT_VERSION_TAG
      dynamic_workflow_version = dynamic_workflow_version_tag.partition("-").last

      expect(described_class.current.to_s).to eq(dynamic_workflow_version)
    end
  end

  describe "#<=>" do
    it "compares version" do
      ghes3point7 = described_class.new("3.7")
      ghes3point8 = described_class.new("3.8")

      expect(ghes3point7 <=> ghes3point8).to eq(-1)
      expect(ghes3point8 > ghes3point7).to be true
      expect(ghes3point8 < ghes3point7).to be false
    end
  end

  describe "#to_s" do
    it "returns the version string" do
      expect(described_class.new("3.7").to_s).to eq("3.7")
    end
  end
end
