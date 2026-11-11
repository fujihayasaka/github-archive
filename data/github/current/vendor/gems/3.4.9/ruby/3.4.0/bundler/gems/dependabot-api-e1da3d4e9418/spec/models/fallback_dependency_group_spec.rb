# frozen_string_literal: true

require "rails_helper"

RSpec.describe FallbackDependencyGroup do
  describe "initialization" do
    it "accepts a name" do
      expect { described_class.new(name: "anything") }.not_to raise_error
      expect(described_class.new(name: "anything")).to be_a(described_class)
    end

    it "requires a name" do
      expect { described_class.new(name: nil) }.to raise_error(ArgumentError)
    end
  end

  describe "#name" do
    it "returns the name of the job's package manager" do
      update_job = build_stubbed(:update_job)
      dependency_group = described_class.new(name: update_job.package_manager)

      expect(dependency_group.name).to eq(update_job.package_manager)
    end
  end

  describe "#rules" do
    it "includes a wildcard pattern" do
      update_job = build_stubbed(:update_job)
      dependency_group = described_class.new(name: update_job.package_manager)

      expect(dependency_group.rules).
        to eq(
          {
            "patterns" => ["*"],
          }
        )
    end
  end

  describe "#applies_to" do
    it "returns 'security-updates' when applicable" do
      update_job = build_stubbed(:update_job)
      dependency_group = described_class.new(name: update_job.package_manager)

      expect(dependency_group.applies_to).to eq("security-updates")
    end
  end

  describe "#serialize" do
    it "returns a Hash describing the group" do
      update_job = build_stubbed(:update_job)
      dependency_group = described_class.new(name: update_job.package_manager)

      expect(dependency_group.serialize).
        to eq(
          {
            "name" => dependency_group.name,
            "rules" => dependency_group.rules,
            "applies-to" => dependency_group.applies_to,
          }
        )
    end
  end
end
