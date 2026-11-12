# frozen_string_literal: true

require "rails_helper"

RSpec.describe HydroHandlers::DependencyGraph::GraphChangesSerializer do
  let(:hydro_payload) do
    {
      graph_changes: [
        {
          ecosystem: :ECOSYSTEM_GO,
          directory: ".",
          ref_name: "feature-branch",
          commit_oid: "abc123def456",
        },
        {
          ecosystem: :ECOSYSTEM_NPM,
          directory: "frontend",
          ref_name: "feature-branch",
          commit_oid: "abc123def456",
        },
      ],
    }
  end

  let(:message) do
    instance_double(Hydro::Consumer::ConsumerMessage, value: hydro_payload)
  end

  let(:graph_changes) { HydroHandlers::DependencyGraph::GraphChanges.from_message(message) }

  describe "#serialize" do
    it "round-trips ref_name and commit_oid" do
      serialized = described_class.instance.serialize(graph_changes)
      deserialized = described_class.instance.deserialize(serialized)

      changes = deserialized.to_a
      expect(changes.size).to eq(2)
      expect(changes.map(&:ref_name)).to all(eq("feature-branch"))
      expect(changes.map(&:commit_oid)).to all(eq("abc123def456"))
    end

    context "when ref_name and commit_oid are absent" do
      let(:hydro_payload) do
        {
          graph_changes: [
            { ecosystem: :ECOSYSTEM_GO, directory: "." },
          ],
        }
      end

      it "round-trips with nil ref_name and commit_oid" do
        serialized = described_class.instance.serialize(graph_changes)
        deserialized = described_class.instance.deserialize(serialized)

        change = deserialized.to_a.first
        expect(change.ref_name).to be_nil
        expect(change.commit_oid).to be_nil
      end
    end
  end
end
