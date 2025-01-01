require "rails_helper"

describe DependencySnapshotService::V1::Handler do
  let(:handler) { DependencySnapshotService::V1::Handler.new }

  let(:noop_snapshots_client) { NoOpTestSnapshotClient::new }

  let(:repository_id) { 23456 }

  # TODO: matches stub embedded in create_dependency_snapshot resp
  let(:snapshot_id) { 1234 }

  let(:repository_metadata) { { nwo: "monalisa/monarepo", owner_id: 2, public: true } }

  # TODO: matches stub returned from well-formed get_dependency_snapshot req
  # not JSON-serialized here, for easy expectation checking after op under test
  let(:payload) {
    {
      version: 0,
      job: {
        id: "snapshot_id",
        correlator: "data_not_stored",
    },
      detector: {
        name: "rspec_tests",
      },
      scanned: "2021-10-31T10:31:00-08:00",
      ref: "refs/heads/main",
      sha: "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
    }
  }

  describe "create dependency snapshot" do
    it "creates snapshot and returns snapshot id", vcr: { cassette_name: "create-dependency-snapshot-happy" } do
      req = DependencyGraphAPI::V1::CreateDependencySnapshotRequest.new(
        repository_id: repository_id,
        repository_metadata: repository_metadata,
        payload: payload.to_json
      )

      created_snapshot = handler.create_dependency_snapshot(req, {})

      expect(created_snapshot.snapshot_id).to be >= 1
      expect(created_snapshot.created_at).to_not be nil
    end

    it "returns Twirp error when repository ID is missing" do
      req = DependencyGraphAPI::V1::CreateDependencySnapshotRequest.new(
        repository_metadata: repository_metadata,
        payload: payload.to_json
      )

      response = handler.create_dependency_snapshot(req, {})
      expect(response.class).to eq(Twirp::Error)
      expect(response.msg).to eq("mandatory fields")
      expect(response.meta[:argument]).to eq("repository_id")
    end

    it "returns Twirp error when submission payload is invalid JSON", vcr: { cassette_name: "create-dependency-snapshot-bad-json" } do
      req = DependencyGraphAPI::V1::CreateDependencySnapshotRequest.new(
        repository_id: repository_id,
        repository_metadata: repository_metadata,
        payload: "{oops]"
      )

      # DS-API provides the Twirp error resp here, captured by VCR.
      # DG-API will proxy the payload from dotcom to DS-API without
      # deserializing or introspecting on the JSON at all.
      response = handler.create_dependency_snapshot(req, {})
      expect(response.class).to eq(Twirp::Error)
    end
  end

  describe "get dependency snapshot" do
    it "get dependency snapshot by id", vcr: { cassette_name: "get-dependency-snapshot-happy" } do
      req = DependencyGraphAPI::V1::CreateDependencySnapshotRequest.new(
        repository_id: repository_id,
        repository_metadata: repository_metadata,
        payload: payload.to_json
      )

      created_snapshot = handler.create_dependency_snapshot(req, {})

      req = DependencyGraphAPI::V1::GetDependencySnapshotRequest.new(
        repository_id: repository_id,
        snapshot_id: created_snapshot.snapshot_id
      )

      resp = handler.get_dependency_snapshot(req, {})
      snapshot = JSON.parse(resp.payload)
      expect(snapshot["job"]["id"]).to eq payload[:job][:id]
      expect(snapshot["job"]["correlator"]).to eq payload[:job][:correlator]
      expect(snapshot["ref"]).to eq payload[:ref]
      expect(snapshot["sha"]).to eq payload[:sha]
      expect(snapshot["scanned"]).to eq payload[:scanned]
    end

    it "returns Twirp error when repository_id is missing" do
      req = DependencyGraphAPI::V1::GetDependencySnapshotRequest.new(
        snapshot_id: snapshot_id
      )

      response = handler.get_dependency_snapshot(req, {})
      expect(response.class).to eq(Twirp::Error)
      expect(response.msg).to eq("mandatory fields")
      expect(response.meta[:argument]).to eq("repository_id")
    end

    it "returns Twirp error when snapshot_id is missing" do
      req = DependencyGraphAPI::V1::GetDependencySnapshotRequest.new(
        repository_id: repository_id
      )

      response = handler.get_dependency_snapshot(req, {})
      expect(response.class).to eq(Twirp::Error)
      expect(response.msg).to eq("mandatory fields")
      expect(response.meta[:argument]).to eq("snapshot_id")
    end
  end

  describe "GHES behavior" do
    before do
      allow(DependencyGraphAPI).to receive(:enterprise?).and_return(true)
    end

    it "404s on gets" do
      # this test is imperfect because theoretically we would 404 if an invalid snapshot_id is used and we can't
      # create with enterprise? = false, but we're OK with that.
      req = DependencyGraphAPI::V1::GetDependencySnapshotRequest.new(
        repository_id: repository_id,
        snapshot_id: 123456
      )

      resp = handler.get_dependency_snapshot(req, {})
      expect(resp.class).to eq(Twirp::Error)
      expect(resp.code).to eq(:not_found)
      expect(resp.msg).to eq("not found")
    end

    it "404s on creates" do
      req = DependencyGraphAPI::V1::CreateDependencySnapshotRequest.new(
        repository_id: repository_id,
        repository_metadata: repository_metadata,
        payload: payload.to_json
      )

      resp = handler.create_dependency_snapshot(req, {})
      expect(resp.class).to eq(Twirp::Error)
      expect(resp.code).to eq(:not_found)
      expect(resp.msg).to eq("not found")
    end
  end
end
