require "rails_helper"
require_relative "../../../../lib/blob_operations/spokes/client"

describe BlobOperations::Spokes::Client do
  let(:client) { described_class.new }

  # This spokes config uses the default forwarding url from a github/github
  # codespace. To add or change tests, run github/github script/server in a
  # codespace with forwarding set up vcr can record the responses.
  let(:spokes_config) do
    {
      base_uri: "http://github.localhost:28081",
      client_key: "nil",
      ca_file: "nil",
      client_cert: "nil",
      connection_open_timeout: 5,
      connection_read_timeout: 10
    }
  end

  before(:each) do
    allow(Rails.application).to receive(:config_for).with(:spokes).and_return(spokes_config)
  end

  context ".verify_objects" do
    it "verifies a branch", vcr: { cassette_name: "spokes-verify-branch" } do
      expect(
        client.object_exists?(repository_id: 10, object: "refs/heads/main")
      ).to be_truthy
    end

    it "verifies a tag", vcr: { cassette_name: "spokes-verify-tag" } do
      expect(
        client.object_exists?(repository_id: 10, object: "v1.0.1")
      ).to be_truthy
    end

    it "returns false for a nonexistent object", vcr: { cassette_name: "spokes-verify-nonexistent" } do
      expect(
        client.object_exists?(repository_id: 10, object: "thisshouldnotexist")
      ).to be_falsey
    end

    it "logs and instruments timeout errors" do
      objects_client = double("objects_client")
      allow(client).to receive(:objects_client).and_return(objects_client)
      allow(objects_client).to receive(:resolve_object).and_raise(Faraday::TimeoutError)

      expect(Instrument).to receive(:increment).with("blob_operations.spokes.client.requests.object_exists")
      expect(Instrument).to receive(:increment).with("blob_operations.spokes.client.requests.object_exists.timeouts")
      expect(DependencyGraph.logger).to receive(:warn).with(
        "object_exists timeout",
        hash_including(
          "gh.dependency_graph.blob_operations.provider" => "spokes",
          "gh.repo.id" => 123,
          "gh.git.object" => "refs/heads/main"
        )
      )

      expect {
        client.object_exists?(repository_id: 123, object: "refs/heads/main")
      }.to raise_error(Faraday::TimeoutError)
    end

    it "logs and instruments general errors" do
      objects_client = double("objects_client")
      allow(client).to receive(:objects_client).and_return(objects_client)
      allow(objects_client).to receive(:resolve_object).and_raise(StandardError, "test error")

      expect(Instrument).to receive(:increment).with("blob_operations.spokes.client.requests.object_exists")
      expect(Instrument).to receive(:increment).with("blob_operations.spokes.client.requests.object_exists.errors")
      expect(DependencyGraph.logger).to receive(:error).with(
        "object_exists error",
        hash_including(
          "gh.dependency_graph.blob_operations.provider" => "spokes",
          "gh.repo.id" => 123,
          "gh.git.object" => "refs/heads/main"
        ),
        instance_of(StandardError)
      )

      expect {
        client.object_exists?(repository_id: 123, object: "refs/heads/main")
      }.to raise_error(StandardError)
    end
  end

  context ".get_trees" do
    let (:trees_client) { GitHub::Spokes::Proto::Trees::V1::TreesAPIClient.new("http://fake.spokes") }
    let (:trees_response) { GitHub::Spokes::Proto::Trees::V1::ListTreesResponse.new(entries: [GitHub::Spokes::Proto::Types::V1::TreeEntry.new]) }
    let (:client_response) { Twirp::ClientResp.new(data: trees_response) }

    it "returns list of trees successfully", vcr: { cassette_name: "spokes-trees" } do
      response = client.get_tree(repository_id: 1, ref: "refs/heads/main")

      assert_instance_of Array, response.tree_entries
      assert_instance_of BlobOperations::Responses::TreeEntry, response.tree_entries.first
    end

    it "uses cursor for paginated list of trees sucessfully" do
      allow(client).to receive(:trees_client).and_return(trees_client).at_least(:once)

      entry1 = GitHub::Spokes::Proto::Types::V1::TreeEntry.new(object: GitHub::Spokes::Proto::Types::V1::Object.new(oid: GitHub::Spokes::Proto::Types::V1::ObjectID.new(id: "100")))
      entry2 = GitHub::Spokes::Proto::Types::V1::TreeEntry.new(object: GitHub::Spokes::Proto::Types::V1::Object.new(oid: GitHub::Spokes::Proto::Types::V1::ObjectID.new(id: "200")))

      cursor = GitHub::Spokes::Proto::Types::V1::Cursor.new

      first_trees_response = GitHub::Spokes::Proto::Trees::V1::ListTreesResponse.new(entries: [entry1], next_cursor: cursor)
      second_trees_response = GitHub::Spokes::Proto::Trees::V1::ListTreesResponse.new(entries: [entry2])
      first_client_response = Twirp::ClientResp.new(data: first_trees_response)
      second_client_response = Twirp::ClientResp.new(data: second_trees_response)

      expect(trees_client).to receive(:list_trees).with(hash_excluding(cursor: cursor)).and_return(first_client_response)
      expect(trees_client).to receive(:list_trees).with(hash_including(cursor: cursor)).and_return(second_client_response)

      response = client.get_tree(repository_id: 8514, ref: "refs/heads/main")

      assert_instance_of Array, response.tree_entries
      expect(response.tree_entries.size).to eq 2
      expect(response.client_response.data).to include(entry1)
      expect(response.client_response.data).to include(entry2)
    end

    it "returns an error if trees cannot be obtained", vcr: { cassette_name: "spokes-error" } do
      expect { response = client.get_tree(repository_id: 8514, ref: "refs/heads/main") }.to raise_error(BlobOperations::Spokes::SpokesClientError)
    end

    it "logs and instruments timeout errors in fetch_full_trees_list" do
      trees_client = double("trees_client")
      allow(client).to receive(:trees_client).and_return(trees_client)
      allow(trees_client).to receive(:list_trees).and_raise(Faraday::TimeoutError)

      expect(Instrument).to receive(:increment).with("blob_operations.spokes.client.requests.get_tree")
      expect(Instrument).to receive(:increment).with("blob_operations.spokes.client.requests.fetch_full_trees_list.timeouts")
      expect(DependencyGraph.logger).to receive(:warn).with(
        "fetch_full_trees_list timeout",
        hash_including(
          "gh.dependency_graph.blob_operations.provider" => "spokes",
          "gh.repo.id" => 456,
          "gh.dependency_graph.blob_operations.trees_fetched" => 0,
          "gh.dependency_graph.blob_operations.has_cursor" => false
        )
      )

      expect {
        client.get_tree(repository_id: 456, ref: "refs/heads/main")
      }.to raise_error(Faraday::TimeoutError)
    end

    it "logs and instruments general errors in fetch_full_trees_list" do
      trees_client = double("trees_client")
      allow(client).to receive(:trees_client).and_return(trees_client)
      allow(trees_client).to receive(:list_trees).and_raise(StandardError, "test error")

      expect(Instrument).to receive(:increment).with("blob_operations.spokes.client.requests.get_tree")
      expect(Instrument).to receive(:increment).with("blob_operations.spokes.client.requests.fetch_full_trees_list.errors")
      expect(DependencyGraph.logger).to receive(:error).with(
        "fetch_full_trees_list error",
        hash_including(
          "gh.dependency_graph.blob_operations.provider" => "spokes",
          "gh.repo.id" => 456,
          "gh.dependency_graph.blob_operations.trees_fetched" => 0,
          "gh.dependency_graph.blob_operations.has_cursor" => false
        ),
        instance_of(StandardError)
      )

      expect {
        client.get_tree(repository_id: 456, ref: "refs/heads/main")
      }.to raise_error(StandardError)
    end
  end

  context ".resolve_objects" do
    let(:object_selectors) { [{ by_treeish_and_path: { treeish: { oid: { id: "abc123" } }, path: { name: "test.txt" } } }] }

    it "logs and instruments timeout errors" do
      objects_client = double("objects_client")
      allow(client).to receive(:objects_client).and_return(objects_client)
      allow(objects_client).to receive(:resolve_objects).and_raise(Faraday::TimeoutError)

      expect(Instrument).to receive(:increment).with("blob_operations.spokes.client.requests.resolve_objects")
      expect(Instrument).to receive(:increment).with("blob_operations.spokes.client.requests.resolve_objects.timeouts")
      expect(DependencyGraph.logger).to receive(:warn).with(
        "resolve_objects timeout",
        hash_including(
          "gh.dependency_graph.blob_operations.provider" => "spokes",
          "gh.repo.id" => 789,
          "gh.dependency_graph.blob_operations.selectors_size" => 1
        )
      )

      expect {
        client.resolve_objects(repository_id: 789, object_selectors: object_selectors)
      }.to raise_error(Faraday::TimeoutError)
    end

    it "logs and instruments general errors" do
      objects_client = double("objects_client")
      allow(client).to receive(:objects_client).and_return(objects_client)
      allow(objects_client).to receive(:resolve_objects).and_raise(StandardError, "test error")

      expect(Instrument).to receive(:increment).with("blob_operations.spokes.client.requests.resolve_objects")
      expect(Instrument).to receive(:increment).with("blob_operations.spokes.client.requests.resolve_objects.errors")
      expect(DependencyGraph.logger).to receive(:error).with(
        "resolve_objects error",
        hash_including(
          "gh.dependency_graph.blob_operations.provider" => "spokes",
          "gh.repo.id" => 789,
          "gh.dependency_graph.blob_operations.selectors_size" => 1
        ),
        instance_of(StandardError)
      )

      expect {
        client.resolve_objects(repository_id: 789, object_selectors: object_selectors)
      }.to raise_error(StandardError)
    end
  end

  context ".get_blob streaming" do
    let(:stubs) { Faraday::Adapter::Test::Stubs.new }
    let(:connection) { Faraday.new(url: "http://dg.localhost/") { |b| b.adapter(:test, stubs) } }

    before do
      allow(client).to receive(:connection).and_return(connection)
    end

    it "obtains a blob successfully" do
      repo_id = 54321
      oid = "615a1"

      stubs.get("/streaming/v1/repositories/#{repo_id}/blobs/#{oid}") do
        [
          200,
          { 'Content-Type': "application/json" },
          "some fake body"
        ]
      end

      response = client.get_blob(repository_id: repo_id, oid: "615a1")

      assert_instance_of BlobOperations::Responses::GetBlob, response
      expect(response.content).to eq("some fake body")
    end

    it "throws with twirp error embedded" do
      repo_id = 54321
      oid = "615a1"

      fake_response = Faraday::Response.new(body: "It's an error message", status: 500)
      allow(connection).to receive(:get).with("/streaming/v1/repositories/#{repo_id}/blobs/#{oid}").and_return(fake_response)
      expect { response = client.get_blob(repository_id: repo_id, oid: "615a1") }.to raise_error(BlobOperations::Spokes::SpokesClientError)
    end

    it "logs and instruments timeout errors" do
      repo_id = 12345
      oid = "abc123"

      allow(connection).to receive(:get).and_raise(Faraday::TimeoutError)

      expect(Instrument).to receive(:increment).with("blob_operations.spokes.client.requests.get_blob")
      expect(Instrument).to receive(:increment).with("blob_operations.spokes.client.requests.get_blob.timeouts")
      expect(DependencyGraph.logger).to receive(:warn).with(
        "get_blob timeout",
        hash_including(
          "gh.dependency_graph.blob_operations.provider" => "spokes",
          "gh.repo.id" => repo_id,
          "gh.git.content_oid" => oid
        )
      )

      expect {
        client.get_blob(repository_id: repo_id, oid: oid)
      }.to raise_error(Faraday::TimeoutError)
    end

    it "logs and instruments general errors" do
      repo_id = 12345
      oid = "abc123"

      allow(connection).to receive(:get).and_raise(StandardError, "test error")

      expect(Instrument).to receive(:increment).with("blob_operations.spokes.client.requests.get_blob")
      expect(Instrument).to receive(:increment).with("blob_operations.spokes.client.requests.get_blob.errors")
      expect(DependencyGraph.logger).to receive(:error).with(
        "get_blob error",
        hash_including(
          "gh.dependency_graph.blob_operations.provider" => "spokes",
          "gh.repo.id" => repo_id,
          "gh.git.content_oid" => oid
        ),
        instance_of(StandardError)
      )

      expect {
        client.get_blob(repository_id: repo_id, oid: oid)
      }.to raise_error(StandardError)
    end
  end
end
