require "rails_helper"
require_relative "../../support/blob_operations_responses_helper"

module Ingest
  describe ::SnapshotRequests::SnapshotAssembler do
    describe "#assemble_snapshot" do
      let (:blob_operations_provider) { SnapshotRequests::Provider::NoOpProvider.new }
      let (:snapshot_assembler) { SnapshotRequests::SnapshotAssembler.new(blob_operations_provider) }
      let (:responses_helper) { BlobOperationsResponseHelper.new }
      let(:snapshot_request) {
        {
          push_id: 123456,
          before_sha: "ff8f40e7223180cd6cdecff48a7757abe815a21b",
          sha: "28d815b89487ce4001a3f6f0ab684e6f9c017ed0",
          ref: "origin/master",
          owner_name: "rails",
          repository: {
            id: 8514,
            name: "rails",
            owner_id: 4223,
            visibility: "PUBLIC",
            primary_language_name: "ruby"
          },
          tree: nil
        }
      }

      it "tries to fetch the git tree if no tree is supplied" do
        tree_response = responses_helper.tree_response

        allow(blob_operations_provider).to receive(:get_tree).and_return(tree_response)
        expect(blob_operations_provider).to receive(:get_tree).once

        snapshot_assembler.assemble_snapshot(snapshot_request)
      end

      it "does not fetch the git tree if it is supplied" do
        ChangedFile = Struct.new(:path, :blob_id)
        gemfile_a = ChangedFile.new("Gemfile", "abc123")
        gemfile_b = ChangedFile.new("Gemfile", "def123")
        package_lock = ChangedFile.new("package-lock.json", "cab321")

        snapshot_request[:tree] = [gemfile_a, gemfile_b, package_lock]

        expect(blob_operations_provider).to receive(:get_blob).exactly(3).times.and_return(responses_helper.blob_response)
        expect(blob_operations_provider).not_to receive(:get_tree)
        snapshot_assembler.assemble_snapshot(snapshot_request)
      end

      it "does not fetch blobs of files that are not supported manifests" do
        tree_response = responses_helper.tree_response(
          entries: responses_helper.tree_response_entries(
            [
              {
                path: "README.md",
                mode: "100644",
                object_id: "object_id"
              }
            ]
          )
        )

        allow(blob_operations_provider).to receive(:get_tree).and_return(tree_response)

        expect(blob_operations_provider).to receive(:get_tree).once
        expect(blob_operations_provider).not_to receive(:get_blob)

        snapshot_assembler.assemble_snapshot(snapshot_request)
      end

      it "performs blob fetching only on supported manifest" do
        tree_response = responses_helper.tree_response(
          entries: responses_helper.tree_response_entries(
            [
              {
                path: "README.md",
                mode: "100644",
                object_id: "object_id1"
              },
              {
                path: "Gemfile",
                mode: "100644",
                object_id: "object_id2"
              }
            ]
          )
        )

        blob_response = responses_helper.blob_response

        allow(blob_operations_provider).to receive(:get_tree).and_return(tree_response)
        allow(blob_operations_provider).to receive(:get_blob).and_return(blob_response)

        expect(blob_operations_provider).to receive(:get_tree).once
        expect(blob_operations_provider).to receive(:get_blob).once

        snapshot_assembler.assemble_snapshot(snapshot_request)
      end

      it "performs blob fetching on manifests with special path syntax" do
        tree_response = responses_helper.tree_response(
          entries: responses_helper.tree_response_entries(
            [
              {
                path: "README.md",
                mode: "100644",
                object_id: "object_id1"
              },
              {
                path: "Gemfile",
                mode: "100644",
                object_id: "object_id2"
              },
              {
                path: ".github/workflows/workflow.yaml",
                mode: "100644",
                object_id: "object_id3"
              },
            ]
          )
        )

        blob_response = responses_helper.blob_response

        allow(blob_operations_provider).to receive(:get_tree).and_return(tree_response)
        allow(blob_operations_provider).to receive(:get_blob).and_return(blob_response)

        expect(blob_operations_provider).to receive(:get_tree).once
        expect(blob_operations_provider).to receive(:get_blob).exactly(2).times

        snapshot_assembler.assemble_snapshot(snapshot_request)
      end

      it "creates a snapshot with dependencies populated for each manifest supported" do
        tree_response = responses_helper.tree_response(
          entries: responses_helper.tree_response_entries(
            [
              {
                path: "sample.gemspec",
                mode: "100644",
                object_id: "object_id1"
              },
              {
                path: "README.md",
                mode: "100644",
                object_id: "object_id2"
              }
            ]
          )
        )

        blob_response = responses_helper.blob_response(
          content: file_fixture("sample.gemspec").read,
          size_bytes: 500
        )

        allow(blob_operations_provider).to receive(:get_tree).and_return(tree_response)
        allow(blob_operations_provider).to receive(:get_blob).and_return(blob_response)

        expect(blob_operations_provider).to receive(:get_tree).once
        expect(blob_operations_provider).to receive(:get_blob).once

        snapshot = snapshot_assembler.assemble_snapshot(snapshot_request)

        manifests = snapshot.manifests
        expect(manifests.length).to eq(1)

        expect(manifests.first.path).to eq("sample.gemspec")

        dependencies = manifests.first.dependencies
        expect(dependencies.length).to eq(3)
      end
    end

    describe "#should_fetch_concurrently?" do
      let(:blob_operations_provider) { SnapshotRequests::Provider::NoOpProvider.new }
      let(:snapshot_assembler) { SnapshotRequests::SnapshotAssembler.new(blob_operations_provider) }
      let(:repository_id) { 12345 }

      it "returns false when manifest count is below threshold" do
        result = snapshot_assembler.send(:should_fetch_concurrently?, SnapshotRequests::SnapshotAssembler::CONCURRENT_BLOB_P95_THRESHOLD, repository_id)
        expect(result).to be false
      end

      it "returns true when manifest count exceeds threshold" do
        result = snapshot_assembler.send(:should_fetch_concurrently?, SnapshotRequests::SnapshotAssembler::CONCURRENT_BLOB_P95_THRESHOLD + 1, repository_id)
        expect(result).to be true
      end
    end

    describe "#fetch_blobs_concurrently" do
      let(:blob_operations_provider) { SnapshotRequests::Provider::NoOpProvider.new }
      let(:snapshot_assembler) { SnapshotRequests::SnapshotAssembler.new(blob_operations_provider) }
      let(:responses_helper) { BlobOperationsResponseHelper.new }
      let(:repository_id) { 12345 }
      let(:snapshot_request) do
        {
          repository: { id: repository_id },
          sha: "abc123",
          ref: "main"
        }
      end

      it "fetches blobs in chunks and returns all results" do
        # Create more manifest entries than CONCURRENT_BLOB_CHUNK_SIZE
        chunk_size = SnapshotRequests::SnapshotAssembler::CONCURRENT_BLOB_CHUNK_SIZE
        manifest_count = chunk_size * 2 + 1

        manifest_entries = manifest_count.times.map do |i|
          oid = "oid_#{i}"
          entry = SnapshotRequests::SnapshotAssembler::RequestTreeEntry.new("Gemfile_#{i}", oid)
          [oid, entry]
        end

        blob_response = responses_helper.blob_response

        allow(blob_operations_provider).to receive(:get_blob).and_return(blob_response)
        expect(blob_operations_provider).to receive(:get_blob).exactly(manifest_count).times

        results = snapshot_assembler.send(:fetch_blobs_concurrently, snapshot_request, manifest_entries, {})

        expect(results.size).to eq(manifest_count)
      end

      it "skips pre-processed blobs" do
        manifest_entries = [
          ["oid_1", SnapshotRequests::SnapshotAssembler::RequestTreeEntry.new("Gemfile", "oid_1")],
          ["oid_2", SnapshotRequests::SnapshotAssembler::RequestTreeEntry.new("package.json", "oid_2")]
        ]

        pre_processed = { "oid_1" => { oid: "oid_1", path: "Gemfile", content: "existing" } }
        blob_response = responses_helper.blob_response

        allow(blob_operations_provider).to receive(:get_blob).and_return(blob_response)
        # Should only fetch the one that wasn't pre-processed
        expect(blob_operations_provider).to receive(:get_blob).once

        results = snapshot_assembler.send(:fetch_blobs_concurrently, snapshot_request, manifest_entries, pre_processed)

        expect(results.size).to eq(2)
        expect(results["oid_1"][:content]).to eq("existing")
      end
    end
  end
end
