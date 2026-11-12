# frozen_string_literal: true

require "rails_helper"

RSpec.describe HydroHandlers::DependencyGraph::GraphChanges do
  describe ".from_message" do
    let(:message) do
      instance_double(
        Hydro::Consumer::ConsumerMessage,
        value: hydro_payload
      )
    end

    context "with a known ecosystem" do
      let(:hydro_payload) do
        {
          graph_changes: [
            {
              ecosystem: :ECOSYSTEM_GO,
              directory: ".",
            },
          ],
        }
      end

      it "correctly maps the ecosystem string to a package manager" do
        graph_changes = described_class.from_message(message)

        changes_array = []
        graph_changes.each { |change| changes_array << change } # rubocop:disable Style/MapIntoArray

        expect(changes_array.size).to eq(1)
        expect(changes_array.first.package_manager).to eq(PackageManagers::GO_MODULES)
        expect(changes_array.first.directory).to eq(".")
      end
    end

    context "with an unknown ecosystem" do
      let(:hydro_payload) do
        {
          graph_changes: [
            {
              ecosystem: :ECOSYSTEM_UNKNOWN,
              directory: "/some/path",
            },
          ],
        }
      end

      it "sets package_manager to nil for unknown ecosystems" do
        graph_changes = described_class.from_message(message)

        changes_array = []
        graph_changes.each { |change| changes_array << change } # rubocop:disable Style/MapIntoArray

        expect(changes_array.size).to eq(1)
        expect(changes_array.first.package_manager).to be_nil
        expect(changes_array.first.directory).to eq("/some/path")
      end
    end

    context "with multiple graph changes" do
      let(:hydro_payload) do
        {
          graph_changes: [
            {
              ecosystem: :ECOSYSTEM_GO,
              directory: "backend",
            },
            {
              ecosystem: :ECOSYSTEM_UNKNOWN,
              directory: "frontend",
            },
            {
              ecosystem: :ECOSYSTEM_GO,
              directory: "services",
            },
          ],
        }
      end

      it "processes all changes correctly" do
        graph_changes = described_class.from_message(message)

        changes_array = []
        graph_changes.each { |change| changes_array << change } # rubocop:disable Style/MapIntoArray

        expect(changes_array.size).to eq(3)
        expect(changes_array[0].package_manager).to eq(PackageManagers::GO_MODULES)
        expect(changes_array[0].directory).to eq("backend")
        expect(changes_array[1].package_manager).to be_nil
        expect(changes_array[1].directory).to eq("frontend")
        expect(changes_array[2].package_manager).to eq(PackageManagers::GO_MODULES)
        expect(changes_array[2].directory).to eq("services")
      end
    end
  end

  describe ".from_activejob" do
    let(:hash) do
      {
        "graph_changes" => [
          {
            "ecosystem" => "ECOSYSTEM_GO",
            "directory" => "backend",
          },
          {
            "ecosystem" => "ECOSYSTEM_UNKNOWN",
            "directory" => "frontend",
          },
          {
            "ecosystem" => "ECOSYSTEM_GO",
            "directory" => "services",
          },
        ],
      }
    end

    it "processes all changes correctly" do
      graph_changes = described_class.from_active_job(hash)

      changes_array = []
      graph_changes.each { |change| changes_array << change } # rubocop:disable Style/MapIntoArray

      expect(changes_array.size).to eq(3)
      expect(changes_array[0].package_manager).to eq(PackageManagers::GO_MODULES)
      expect(changes_array[0].directory).to eq("backend")
      expect(changes_array[1].package_manager).to be_nil
      expect(changes_array[1].directory).to eq("frontend")
      expect(changes_array[2].package_manager).to eq(PackageManagers::GO_MODULES)
      expect(changes_array[2].directory).to eq("services")
    end
  end
end
