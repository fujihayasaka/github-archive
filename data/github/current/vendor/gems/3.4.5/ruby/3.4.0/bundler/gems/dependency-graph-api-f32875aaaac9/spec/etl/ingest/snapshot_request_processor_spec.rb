require "rails_helper"

module Ingest
  describe SnapshotRequestProcessor do
    let(:processor) { described_class.new }

    def process
      consumer = processor.spec_consumer
      consumer.each_message do |msg|
        processor.process_with_consumer(msg, consumer)
      end
      processor.spec_reset
    end

    it "doesn't do anything (yet)" do
      processor.publish({
        push_id: 1234,
        before_sha: "791369ea8ad96a4025f3caede4fbe4e5cf9600a8",
        sha: "aeccfe6f3a7e0ed75d59cd1f931ed2a36c1c7263",
        ref: "hydro-gem/snapshot-request",
        pushed_at: 1.second.ago,
        repository: {
          id: 69299342,
          name: "dependency-graph-api"
        },
        manifest_files: [
          {
            filename: "Gemfile",
            path: "",
            blob_oid: "ef3ec74e9161b3966c72250b40a8eef9b7e4b59b",
          }
        ]
      })

      expect(DependencyGraph.logger).to receive(:info).with("SnapshotRequestProcessor#consume_message ran a no-op").once

      process
    end
  end
end
