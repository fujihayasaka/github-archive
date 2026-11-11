# frozen_string_literal: true

require "rails_helper"

RSpec.describe Routes::UpdateJobs::CreateDependencySubmission do
  subject(:instance) { described_class.new(context) }

  let(:update_job) { create(:update_job, :processed, :graph, github_request_id: 42) }
  let(:context) { { request: request, update_job: update_job } }
  let(:request) { instance_double(ActionDispatch::Request, params: params) }

  let(:params) do
    ActiveSupport::HashWithIndifferentAccess.new(
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
      }
    )
  end

  let(:dg_client) do
    instance_double(DependencyGraph::Client)
  end

  before do
    allow(DependencyGraph::Client).to receive(:new).and_return(dg_client)
  end

  context "for a successful submission" do
    let(:success_response) do
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

    before do
      allow(dg_client).to receive(:create_dependabot_snapshot).and_return(success_response)
    end

    it { is_expected.to respond_with_status(204) }

    it "logs parameters" do
      allow(Dependabot::Logger).to receive(:info)
      instance.call

      expect(Dependabot::Logger).
        to have_received(:info).
        with(a_hash_including(
               "code.namespace": "CreateDependencySubmission",
               "gh.repo.id": update_job.repo.github_id,
               "gh.dependabot_api.update_job.id": update_job.id,
               "gh.dependabot_api.update_config.id": update_job.update_config.id,
               "gh.owner.id": update_job.update_config.account.github_id,
             ))
    end

    it "relays the payload to DS-API with an appended scanned timestamp" do
      expect(dg_client).to receive(:create_dependabot_snapshot) do |req|
        expect(req.repository_id).to eql(update_job.repo.github_id)
        expect(req.payload.job.id).to eql(update_job.id.to_s)
        expect(req.payload.scanned.to_time).to be_within(5).of(Time.now.utc)

        success_response
      end

      instance.call
    end

    it "includes the github_request_id as event_id in the snapshot metadata" do
      expect(dg_client).to receive(:create_dependabot_snapshot) do |req|
        expect(req.payload.metadata.to_h).to include("event_id" => "42")

        success_response
      end

      instance.call
    end

    context "when the payload already has metadata" do
      before do
        params[:data][:metadata] = { "foo" => "bar", "baz" => "qux" }
      end

      it "merges the event_id into the existing metadata" do
        expect(dg_client).to receive(:create_dependabot_snapshot) do |req|
          metadata = req.payload.metadata.to_h
          expect(metadata).to include("foo" => "bar", "baz" => "qux", "event_id" => "42")

          success_response
        end

        instance.call
      end
    end

    context "when the payload already has an event_id in metadata" do
      before do
        params[:data][:metadata] = { "event_id" => "old-value", "foo" => "bar" }
      end

      it "replaces the existing event_id with the update job value" do
        expect(dg_client).to receive(:create_dependabot_snapshot) do |req|
          metadata = req.payload.metadata.to_h
          expect(metadata).to include("event_id" => "42", "foo" => "bar")
          expect(metadata["event_id"]).not_to eq("old-value")

          success_response
        end

        instance.call
      end
    end

    context "when the update job has no github_request_id" do
      let(:update_job) { create(:update_job, :processed, :graph, github_request_id: nil) }

      it "does not include event_id in the snapshot metadata" do
        expect(dg_client).to receive(:create_dependabot_snapshot) do |req|
          expect(req.payload.metadata.to_h).not_to have_key("event_id")

          success_response
        end

        instance.call
      end
    end
  end

  context "for an invalid submission" do
    let(:invalid_response) do
      Twirp::ClientResp.new(
        data: Github::DependencySnapshotsApi::CreateDependabotSnapshotResponse.new(
          snapshot_id: 123,
          created_at: Time.now.utc,
          result: :RESULT_INVALID,
          message: "oh noes"
        ),
        error: nil,
      )
    end

    before do
      allow(dg_client).to receive(:create_dependabot_snapshot).and_return(invalid_response)
    end

    it { is_expected.to respond_with_status(400) }

    it "logs the error" do
      allow(Dependabot::Logger).to receive(:error)
      instance.call

      expect(Dependabot::Logger).
        to have_received(:error).
        with(a_hash_including(
               "code.namespace": "CreateDependencySubmission",
               msg: "Failed to submit dependency snapshot",
               "exception.message": "oh noes",
               "exception.type": "DependencyGraph::Snapshots::InvalidSnapshotError",
               "gh.repo.id": update_job.repo.github_id,
               "gh.dependabot_api.update_job.id": update_job.id,
               "gh.dependabot_api.update_config.id": update_job.update_config.id,
               "gh.owner.id": update_job.update_config.account.github_id,
             ))
    end
  end

  context "for a service error" do
    let(:error_response) do
      Twirp::ClientResp.new(
        data: nil,
        error: Twirp::Error.internal("i smell burning")
      )
    end

    before do
      allow(dg_client).to receive(:create_dependabot_snapshot).and_return(error_response)
    end

    it { is_expected.to respond_with_status(500) }

    it "logs the error" do
      allow(Dependabot::Logger).to receive(:error)
      instance.call

      expect(Dependabot::Logger).
        to have_received(:error).
        with(a_hash_including(
               "code.namespace": "CreateDependencySubmission",
               msg: "Failed to submit dependency snapshot",
               "exception.message": "internal - i smell burning",
               "exception.type": "DependencyGraph::Snapshots::Error",
               "gh.repo.id": update_job.repo.github_id,
               "gh.dependabot_api.update_job.id": update_job.id,
               "gh.dependabot_api.update_config.id": update_job.update_config.id,
               "gh.owner.id": update_job.update_config.account.github_id,
             ))
    end
  end

  context "for an unexpected error" do
    before do
      allow(dg_client).to receive(:create_dependabot_snapshot).and_raise(StandardError.new("Unexpected failure"))
    end

    it { is_expected.to respond_with_status(500) }

    it "logs the error" do
      allow(Dependabot::Logger).to receive(:error)
      instance.call

      expect(Dependabot::Logger).
        to have_received(:error).
        with(a_hash_including(
               "code.namespace": "CreateDependencySubmission",
               msg: "Failed to submit dependency snapshot",
               "exception.message": "Unexpected failure",
               "exception.type": "StandardError",
               "gh.repo.id": update_job.repo.github_id,
               "gh.dependabot_api.update_job.id": update_job.id,
               "gh.dependabot_api.update_config.id": update_job.update_config.id,
               "gh.owner.id": update_job.update_config.account.github_id,
             ))
    end
  end
end
