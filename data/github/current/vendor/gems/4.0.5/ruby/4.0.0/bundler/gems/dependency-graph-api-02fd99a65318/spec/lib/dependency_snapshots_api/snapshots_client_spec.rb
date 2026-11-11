require "rails_helper"
require "dependency_snapshots_api/snapshots_client"

describe DependencyGraphAPI::DependencySnapshotsAPI::SnapshotsClient do
  describe "#build_changed_files" do
    subject(:client) { described_class.new }

    it "returns nil when limit_to_files is nil" do
      result = client.send(:build_changed_files, nil)
      expect(result).to be_nil
    end

    it "returns nil when limit_to_files has empty base and target" do
      limit_to_files = DependencyGraphAPI::V1::LimitToFiles.new(base: [], target: [])
      result = client.send(:build_changed_files, limit_to_files)
      expect(result).to be_nil
    end

    it "translates limit_to_files to ChangedFiles with correct field mapping" do
      limit_to_files = DependencyGraphAPI::V1::LimitToFiles.new(
        base: [
          { path: "Gemfile.lock", blob_id: "abc123" },
          { path: "package.json", blob_id: "def456" },
        ],
        target: [
          { path: "Gemfile.lock", blob_id: "ghi789" },
        ],
      )

      result = client.send(:build_changed_files, limit_to_files)

      expect(result).to be_a(Github::DependencySnapshotsApi::ChangedFiles)

      # base maps directly
      expect(result.base.length).to eq(2)
      expect(result.base[0].path).to eq("Gemfile.lock")
      expect(result.base[0].blob_oid).to eq("abc123")
      expect(result.base[1].path).to eq("package.json")
      expect(result.base[1].blob_oid).to eq("def456")

      # target maps to head, blob_id maps to blob_oid
      expect(result.head.length).to eq(1)
      expect(result.head[0].path).to eq("Gemfile.lock")
      expect(result.head[0].blob_oid).to eq("ghi789")
    end

    it "handles base-only files (target empty)" do
      limit_to_files = DependencyGraphAPI::V1::LimitToFiles.new(
        base: [{ path: "removed.lock", blob_id: "aaa111" }],
        target: [],
      )

      result = client.send(:build_changed_files, limit_to_files)

      expect(result).to be_a(Github::DependencySnapshotsApi::ChangedFiles)
      expect(result.base.length).to eq(1)
      expect(result.head).to be_empty
    end

    it "handles target-only files (base empty)" do
      limit_to_files = DependencyGraphAPI::V1::LimitToFiles.new(
        base: [],
        target: [{ path: "new.lock", blob_id: "bbb222" }],
      )

      result = client.send(:build_changed_files, limit_to_files)

      expect(result).to be_a(Github::DependencySnapshotsApi::ChangedFiles)
      expect(result.base).to be_empty
      expect(result.head.length).to eq(1)
      expect(result.head[0].path).to eq("new.lock")
      expect(result.head[0].blob_oid).to eq("bbb222")
    end
  end

  describe "#get_snapshot_diff" do
    subject(:client) { described_class.new }

    let(:repository_id) { 12345 }
    let(:base_sha) { "aaa" * 13 + "a" }
    let(:target_sha) { "bbb" * 13 + "b" }

    before do
      # Stub the twirp client to capture the request
      @captured_request = nil
      fake_client = double("twirp_client")
      allow(fake_client).to receive(:get_snapshot_diff) do |req|
        @captured_request = req
        Twirp::ClientResp.new(data: Github::DependencySnapshotsApi::GetSnapshotDiffResponse.new)
      end
      allow(client).to receive(:client).and_return(fake_client)
    end

    it "sets target_repository_id on the request when provided" do
      fork_repo_id = 99999
      client.get_snapshot_diff(repository_id, base_sha, target_sha, target_repository_id: fork_repo_id)

      expect(@captured_request.target_repository_id).to eq(fork_repo_id)
      expect(@captured_request.repository_id).to eq(repository_id)
    end

    it "defaults target_repository_id to 0 when not provided" do
      client.get_snapshot_diff(repository_id, base_sha, target_sha)

      expect(@captured_request.target_repository_id).to eq(0)
      expect(@captured_request.repository_id).to eq(repository_id)
    end
  end
end
