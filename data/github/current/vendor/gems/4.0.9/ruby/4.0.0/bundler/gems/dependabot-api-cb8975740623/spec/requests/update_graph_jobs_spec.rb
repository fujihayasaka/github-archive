# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/update_jobs/:id/create_dependency_submission" do
  let(:token) { RbNaCl::Random.random_bytes(RbNaCl::SecretBox.key_bytes) }
  let(:base64_job_token) { Base64.strict_encode64(token) }
  let(:hashed_token) { Base64.strict_encode64(RbNaCl::Hash.sha256(token)) }
  let(:token_checksum) { Base62.encode(Zlib.crc32(base64_job_token)).rjust(6, Base62::PRIMITIVES[0]) }
  let(:external_job_token) do
    UpdateJob::DEPENDABOT_JOB_TOKEN_PREFIX +
      base64_job_token +
      token_checksum
  end

  let(:update_config) { create(:update_config) }
  let(:update_job) do
    create(
      :update_job, :processing,
      id: 1001,
      update_config: update_config,
      hashed_token: hashed_token,
      command: :graph,
    )
  end

  let(:mock_success_response) do
    Twirp::ClientResp.new(
      data: Github::DependencySnapshotsApi::CreateDependabotSnapshotResponse.new(
        snapshot_id: 123,
        created_at: Time.now.utc,
        result: :RESULT_ACCEPTED,
        message: "snapshot created"
      ),
      error: nil,
    )
  end

  let(:dg_client) do
    instance_double(DependencyGraph::Client, create_dependabot_snapshot: mock_success_response)
  end

  before do
    allow(DependencyGraph::Client).to receive(:new).and_return(dg_client)
  end

  describe "POST /update_jobs/:id/create_dependency_submission" do
    let(:header) do
      { "Content-Type" => "application/json", "Authorization" => external_job_token }
    end

    context "with a valid payload" do
      let(:params) do
        {
          data: {
            version: 1,
            sha: "ce587453ced02b1526dfb4cb910479d431683101",
            ref: "refs/heads/main",
            job: {
              correlator: "dependabot-experimental",
              id: update_job.id.to_s,
            },
            detector: {
              name: "dependabot",
              version: "1.0.0",
              url: "https://github.com/dependabot/dependabot-core",
            },
            manifests: {
              "package-lock.json": {
                name: "package-lock.json",
                file: {
                  source_location: "src/package-lock.json",
                },
                resolved: {
                  "@actions/core": {
                    package_url: "pkg:/npm/%40actions/core@1.1.9",
                    relationship: "direct",
                    scope: "runtime",
                    dependencies: [
                      "@actions/http-client",
                    ],
                  },
                  "@actions/http-client": {
                    package_url: "pkg:/npm/%40actions/http-client@1.0.7",
                    relationship: "indirect",
                    scope: "runtime",
                    dependencies: [
                      "tunnel",
                    ],
                  },
                  tunnel: {
                    package_url: "pkg:/npm/tunnel@0.0.6",
                    relationship: "indirect",
                    scope: "runtime",
                  },
                  jest: {
                    package_url: "pkg:/npm/jest@30.0.2",
                    relationship: "direct",
                    scope: "development",
                  },
                },
              },
            },
          },
        }
      end

      it "serializes and relays the request to Dependency Graph" do # rubocop:disable RSpec/ExampleLength
        post "/update_jobs/#{update_job.id}/create_dependency_submission", headers: header, params: params.to_json
        expect(response).to have_http_status(:success)

        expect(dg_client).to have_received(:create_dependabot_snapshot) do |req|
          expect(req.repository_id).to eql(update_job.repo.github_id)
          expect(req.payload.job.id).to eql(update_job.id.to_s)

          expect(req.payload.manifests).to have_key("package-lock.json")

          resolved = req.payload.manifests["package-lock.json"].resolved

          expect(resolved.keys).to contain_exactly("@actions/core", "@actions/http-client", "tunnel", "jest")

          # Spot check a few dependencies
          actions_core = resolved["@actions/core"]

          expect(actions_core.package_url).to eql("pkg:/npm/%40actions/core@1.1.9")
          expect(actions_core.relationship).to be(:RELATIONSHIP_DIRECT)
          expect(actions_core.scope).to be(:SCOPE_RUNTIME)
          expect(actions_core.dependencies).to contain_exactly("@actions/http-client")

          actions_http = resolved["@actions/http-client"]

          expect(actions_http.package_url).to eql("pkg:/npm/%40actions/http-client@1.0.7")
          expect(actions_http.relationship).to be(:RELATIONSHIP_INDIRECT)
          expect(actions_http.scope).to be(:SCOPE_RUNTIME)
          expect(actions_http.dependencies).to contain_exactly("tunnel")

          jest = resolved["jest"]

          expect(jest.package_url).to eql("pkg:/npm/jest@30.0.2")
          expect(jest.relationship).to be(:RELATIONSHIP_DIRECT)
          expect(jest.scope).to be(:SCOPE_DEVELOPMENT)
          expect(jest.dependencies).to be_empty
        end
      end
    end

    context "with a valid empty snapshots" do
      let(:params) do
        {
          data: {
            version: 1,
            sha: "ce587453ced02b1526dfb4cb910479d431683101",
            ref: "refs/heads/main",
            job: {
              correlator: "dependabot-experimental",
              id: update_job.id.to_s,
            },
            detector: {
              name: "dependabot",
              version: "1.0.0",
              url: "https://github.com/dependabot/dependabot-core",
            },
            manifests: {},
          },
        }
      end

      it "serializes and relays the request to Dependency Graph" do
        post "/update_jobs/#{update_job.id}/create_dependency_submission", headers: header, params: params.to_json
        expect(response).to have_http_status(:success)

        expect(dg_client).to have_received(:create_dependabot_snapshot) do |req|
          expect(req.repository_id).to eql(update_job.repo.github_id)
          expect(req.payload.job.id).to eql(update_job.id.to_s)

          # Deserialise the protobuf obj as a hash
          expect(req.payload.manifests.to_h).to be_empty
        end
      end
    end

    context "when payload version is zero" do
      let(:params) do
        {
          data: {
            version: 0,
            sha: "ce587453ced02b1526dfb4cb910479d431683101",
            ref: "refs/heads/main",
            job: {
              correlator: "dependabot-experimental",
              id: update_job.id.to_s,
            },
            detector: {
              name: "dependabot",
              version: "1.0.0",
              url: "https://github.com/dependabot/dependabot-core",
            },
            manifests: {},
          },
        }
      end

      it "raises an exception before emitting to Dependency Graph" do
        post "/update_jobs/#{update_job.id}/create_dependency_submission", headers: header,
                                                                           params: params.to_json
        expect(response).to have_http_status(:bad_request)

        expect(dg_client).not_to have_received(:create_dependabot_snapshot)
      end
    end
  end
end
