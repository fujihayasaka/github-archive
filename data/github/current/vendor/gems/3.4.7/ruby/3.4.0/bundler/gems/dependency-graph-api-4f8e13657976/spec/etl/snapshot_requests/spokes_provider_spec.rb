require "rails_helper"
require_relative "../../../etl/snapshot_requests/provider/spokes_provider"

describe SnapshotRequests::Provider::SpokesProvider do
  let(:provider) { described_class.new }
  let(:client) { BlobOperations::Spokes::Client.new }
  let(:trees_client) { GitHub::Spokes::Proto::Trees::V1::TreesAPIClient.new("http://fake.spokes") }

  before do
    allow(provider).to receive(:client).and_return(client).at_least(:once)
    allow(client).to receive(:trees_client).and_return(trees_client).at_least(:once)
  end

  context ".get_tree" do
    it "raises and logs exceptions" do
      expected_exception = BlobOperations::Spokes::SpokesClientError.new("oopsie")
      allow(client).to receive(:get_tree).and_raise(expected_exception)

      expect(DependencyGraph.logger).to receive(:error).once.with("get_tree error",
        hash_including({
          "gh.dependency_graph.blob_operations.provider" => "spokes",
          "gh.repo.id" => 123,
          "gh.commit.sha" => nil,
          "gh.git.ref" => "refs/heads/main",
        }),
        expected_exception
      )

      expect { provider.get_tree(repository_id: 123, ref: "refs/heads/main") }.to raise_error(StandardError)
    end

    it "returns correctly formatted response" do
      path = GitHub::Spokes::Proto::Types::V1::Path.new(name: "Gemfile")
      object = GitHub::Spokes::Proto::Types::V1::Object.new(oid: GitHub::Spokes::Proto::Types::V1::ObjectID.new(id: "100"))
      mode = GitHub::Spokes::Proto::Types::V1::Mode.new(mode: 100644)
      entry = GitHub::Spokes::Proto::Types::V1::TreeEntry.new(path: path, object: object, mode: mode)
      allow(client).to receive(:fetch_full_trees_list).and_return([entry])

      provider_response = provider.get_tree(repository_id: 123, ref: "refs/heads/main")

      assert_instance_of BlobOperations::Responses::GetTree, provider_response
      expect(provider_response.tree_entries.size).to eq 1
      expect(provider_response.tree_entries.first.path).to eq "Gemfile"
    end
  end

  context ".get_blob" do
    it "raises and logs exceptions" do
      expected_exception = BlobOperations::Spokes::SpokesClientError.new("oopsie")
      allow(client).to receive(:get_blob).and_raise(expected_exception)

      expect(DependencyGraph.logger).to receive(:warn).once.with("get_blob error",
        hash_including({
          "gh.dependency_graph.blob_operations.provider" => "spokes",
          "gh.repo.id" => 123,
          "gh.git.oid" => "84542",
        }),
        expected_exception
      )

      expect { provider.get_blob(repository_id: 123, oid: "84542") }.to raise_error(StandardError)
    end

    it "returns correctly formatted response" do
      twirp = Twirp::ClientResp.new(data: {})
      blob = BlobOperations::Responses::GetBlob.new(twirp, content: "beep boop beep", oid: "someoid", size_bytes: 123)

      expect(client).to receive(:get_blob).and_return(blob)

      provider_response = provider.get_blob(repository_id: 123, oid: "84542")

      assert_instance_of BlobOperations::Responses::GetBlob, provider_response
      expect(provider_response.content).to eq "beep boop beep"
    end
  end

  context "resolve_objects" do
    it "raises an error if the selectors are empty" do
      expect { provider.resolve_objects(repository_id: 123, object_selectors: []) }.to raise_error(BlobOperations::Spokes::SpokesClientError, "selectors is required")
    end

    it "returns a list of objects with correct mapping from selectors" do
      selectors = [
        {
          by_treeish_and_path: {
            treeish: { oid: { id: "sha1" } },
            path: { name: "path/to/manifest1.json" }
          }
        },
        {
          by_treeish_and_path: {
            treeish: { oid: { id: "sha2" } },
            path: { name: "path/to/manifest2.json" }
          }
        }
      ]
      resolved_objects = [
        double("ResolvedObject", object: double("Object", oid: double("Oid", id: "sha1"))),
        double("ResolvedObject", object: double("Object", oid: double("Oid", id: "sha2")))
      ]
      expect(client).to receive(:resolve_objects).with(repository_id: 123, object_selectors: selectors).and_return(resolved_objects)

      result = provider.resolve_objects(repository_id: 123, object_selectors: selectors)
      expect(result.size).to eq(2)
      expect(result[0].object.oid.id).to eq("sha1")
      expect(result[1].object.oid.id).to eq("sha2")
    end

    it "batches requests when selectors exceed MAX_SELECTORS_PER_REQUEST" do
      max_batch = described_class::MAX_SELECTORS_PER_REQUEST
      total = max_batch * 2 + 1 # 2001 selectors
      selectors = Array.new(total) do |i|
        {
          by_treeish_and_path: {
            treeish: { oid: { id: "sha#{i}" } },
            path: { name: "path/to/manifest#{i}.json" }
          }
        }
      end
      # Prepare batch results
      batch1 = Array.new(max_batch) { |i| double("ResolvedObject", object: double("Object", oid: double("Oid", id: "sha#{i}"))) }
      batch2 = Array.new(max_batch) { |i| double("ResolvedObject", object: double("Object", oid: double("Oid", id: "sha#{i + max_batch}"))) }
      batch3 = [double("ResolvedObject", object: double("Object", oid: double("Oid", id: "sha#{2 * max_batch}")))]

      expect(client).to receive(:resolve_objects).with(repository_id: 123, object_selectors: selectors[0...max_batch]).and_return(batch1)
      expect(client).to receive(:resolve_objects).with(repository_id: 123, object_selectors: selectors[max_batch...(2 * max_batch)]).and_return(batch2)
      expect(client).to receive(:resolve_objects).with(repository_id: 123, object_selectors: selectors[(2 * max_batch)..]).and_return(batch3)

      result = provider.resolve_objects(repository_id: 123, object_selectors: selectors)
      expect(result.size).to eq(total)
      expect(result.first.object.oid.id).to eq("sha0")
      expect(result.last.object.oid.id).to eq("sha2000")
    end
  end
end
