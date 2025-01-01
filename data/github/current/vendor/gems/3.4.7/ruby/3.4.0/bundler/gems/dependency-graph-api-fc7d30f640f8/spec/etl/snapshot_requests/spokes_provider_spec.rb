require "rails_helper"
require_relative "../../../etl/snapshot_requests/provider/spokes_provider"

describe SnapshotRequests::Provider::SpokesProvider do
  let (:provider) { described_class.new }
  let (:client) { BlobOperations::Spokes::Client.new }
  let (:trees_client) { GitHub::Spokes::Proto::Trees::V1::TreesAPIClient.new("http://fake.spokes") }

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
end
