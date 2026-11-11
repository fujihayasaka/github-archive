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
      [
        {
          hydro_ecosystem: :ECOSYSTEM_GO,
          expected_package_manager: PackageManagers::GO_MODULES,
        },
        {
          hydro_ecosystem: :ECOSYSTEM_NPM,
          expected_package_manager: PackageManagers::NPM_AND_YARN,
        },
        {
          hydro_ecosystem: :ECOSYSTEM_NUGET,
          expected_package_manager: PackageManagers::NUGET,
        },
        {
          hydro_ecosystem: :ECOSYSTEM_PYPI,
          expected_package_manager: PackageManagers::PIP,
        },
      ].each do |msg|
        let(:hydro_payload) do
          {
            graph_changes: [
              {
                ecosystem: msg[:hydro_ecosystem],
                directory: ".",
              },
            ],
          }
        end

        let(:expected_package_manager) { msg[:expected_package_manager] }

        it "correctly maps #{msg[:hydro_ecosystem]} to #{msg[:expected_package_manager]}" do
          graph_changes = described_class.from_message(message)

          changes_array = []
          graph_changes.each { |change| changes_array << change } # rubocop:disable Style/MapIntoArray

          expect(changes_array.size).to eq(1)
          expect(changes_array.first.package_manager).to eq(expected_package_manager)
          expect(changes_array.first.directory).to eq(".")
        end
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
              ecosystem: :ECOSYSTEM_NPM,
              directory: "frontend",
            },
            {
              ecosystem: :ECOSYSTEM_NUGET,
              directory: "dotnet",
            },
            {
              ecosystem: :ECOSYSTEM_PYPI,
              directory: "python",
            },
            {
              ecosystem: :ECOSYSTEM_GO,
              directory: "services",
            },
            {
              ecosystem: :ECOSYSTEM_UNKNOWN,
              directory: "utils",
            },
          ],
        }
      end

      let(:expected_changes) do
        [
          [PackageManagers::GO_MODULES, "backend"],
          [PackageManagers::NPM_AND_YARN, "frontend"],
          [PackageManagers::NUGET, "dotnet"],
          [PackageManagers::PIP, "python"],
          [PackageManagers::GO_MODULES, "services"],
          [nil, "utils"],
        ]
      end

      it "processes all changes correctly" do
        graph_changes = described_class.from_message(message)

        changes_array = []
        graph_changes.each { |change| changes_array << change } # rubocop:disable Style/MapIntoArray

        expect(changes_array.size).to eq(expected_changes.size)
        expected_changes.each_with_index do |(pm, dir), i|
          expect(changes_array[i].package_manager).to eq(pm)
          expect(changes_array[i].directory).to eq(dir)
        end
      end
    end

    context "with commit_oid present" do
      let(:hydro_payload) do
        {
          graph_changes: [
            {
              ecosystem: :ECOSYSTEM_PYPI,
              directory: ".",
              ref_name: "refs/heads/main",
              commit_oid: "abc123def456",
            },
          ],
        }
      end

      it "parses commit_oid from the message" do
        graph_changes = described_class.from_message(message)

        changes_array = []
        graph_changes.each { |change| changes_array << change } # rubocop:disable Style/MapIntoArray

        expect(changes_array.size).to eq(1)
        expect(changes_array.first.commit_oid).to eq("abc123def456")
        expect(changes_array.first.ref_name).to eq("refs/heads/main")
      end
    end

    context "without commit_oid" do
      let(:hydro_payload) do
        {
          graph_changes: [
            {
              ecosystem: :ECOSYSTEM_PYPI,
              directory: ".",
              ref_name: "refs/heads/main",
            },
          ],
        }
      end

      it "defaults commit_oid to nil" do
        graph_changes = described_class.from_message(message)

        changes_array = []
        graph_changes.each { |change| changes_array << change } # rubocop:disable Style/MapIntoArray

        expect(changes_array.size).to eq(1)
        expect(changes_array.first.commit_oid).to be_nil
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
            "ecosystem" => "ECOSYSTEM_NPM",
            "directory" => "frontend",
          },
          {
            "ecosystem" => "ECOSYSTEM_NUGET",
            "directory" => "dotnet",
          },
          {
            "ecosystem" => "ECOSYSTEM_PYPI",
            "directory" => "python",
          },
          {
            "ecosystem" => "ECOSYSTEM_GO",
            "directory" => "services",
          },
          {
            "ecosystem" => "ECOSYSTEM_UNKNOWN",
            "directory" => "utils",
          },
        ],
      }
    end

    let(:expected_changes) do
      [
        [PackageManagers::GO_MODULES, "backend"],
        [PackageManagers::NPM_AND_YARN, "frontend"],
        [PackageManagers::NUGET, "dotnet"],
        [PackageManagers::PIP, "python"],
        [PackageManagers::GO_MODULES, "services"],
        [nil, "utils"],
      ]
    end

    it "processes all changes correctly" do
      graph_changes = described_class.from_active_job(hash)

      changes_array = []
      graph_changes.each { |change| changes_array << change } # rubocop:disable Style/MapIntoArray

      expect(changes_array.size).to eq(expected_changes.size)
      expected_changes.each_with_index do |(pm, dir), i|
        expect(changes_array[i].package_manager).to eq(pm)
        expect(changes_array[i].directory).to eq(dir)
      end
    end

    context "with ref_name and commit_oid in the hash" do
      let(:hash) do
        {
          "graph_changes" => [
            {
              "ecosystem" => "ECOSYSTEM_GO",
              "directory" => ".",
              "ref_name" => "feature-branch",
              "commit_oid" => "abc123def456",
            },
          ],
        }
      end

      it "preserves ref_name and commit_oid" do
        graph_changes = described_class.from_active_job(hash)

        changes_array = []
        graph_changes.each { |change| changes_array << change } # rubocop:disable Style/MapIntoArray

        expect(changes_array.size).to eq(1)
        expect(changes_array.first.ref_name).to eq("feature-branch")
        expect(changes_array.first.commit_oid).to eq("abc123def456")
      end
    end
  end
end
