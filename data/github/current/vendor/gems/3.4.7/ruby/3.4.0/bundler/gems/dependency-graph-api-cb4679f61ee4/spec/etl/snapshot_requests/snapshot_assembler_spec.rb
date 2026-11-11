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
  end
end
