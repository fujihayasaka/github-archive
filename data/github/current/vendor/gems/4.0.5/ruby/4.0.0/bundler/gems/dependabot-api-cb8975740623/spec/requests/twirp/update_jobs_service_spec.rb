# frozen_string_literal: true

require "twirp_helper"

RSpec.describe DependabotApi::V1::UpdateJobsService, type: :request do
  include_context "internal twirp api"

  let(:start_time) { Time.now.utc }
  let(:end_time) { start_time + 1.second }

  before do
    allow(Failbot).to receive(:report)
    allow(MetricsClient).to receive(:timing)
    allow_any_instance_of(Services::RackApp).
      to receive(:time_now).and_return(start_time, end_time)
  end

  describe "GetJobStatus" do
    let(:expected_context) do
      {
        content_type: "application/protobuf",
        rpc_method: :GetJobStatus,
      }
    end

    let(:expected_error_context) do
      {
        "http.request.header.content-type": "application/protobuf",
        "rpc.method": :GetJobStatus,
      }
    end

    let(:repo) do
      FactoryBot.create(:repo, github_id: 42)
    end

    let(:update_config) do
      FactoryBot.create(:update_config, repo: repo)
    end

    let(:update_job) do
      FactoryBot.create(:update_job, update_config: update_config)
    end

    let(:params) do
      {
        repository_github_id: repo.github_id,
        update_job_id: update_job.id,
      }
    end

    context "authentication" do
      let(:hmac_token) do
        "garbage"
      end

      let(:expected_tags) do
        expected_context.merge({
                                 success: false,
                                 error_code: :unauthenticated,
                               })
      end

      before do
        rpc_call method: "GetJobStatus", params: params
      end

      it "returns a 401" do
        expect(response.status).to be(401)
      end

      it "does not raise it as an exception" do
        expect(Failbot).not_to have_received(:report)
      end

      it "increments an error metric" do
        expect(MetricsClient).
          to have_received(:timing).with("twirp.request",
                                         1.0,
                                         tags: expected_tags)
      end
    end

    context "with a valid request message" do
      context "and the update job exists, belonging to the repository" do
        let(:expected_tags) do
          expected_context.merge({
                                   success: true,
                                   error_code: nil,
                                 })
        end

        before do
          rpc_call method: "GetJobStatus", params: params
        end

        it "returns a 200" do
          expect(response.status).to be(200)
        end

        it "increments a success metric" do
          expect(MetricsClient).
            to have_received(:timing).with("twirp.request",
                                           1.0,
                                           tags: expected_tags)
        end
      end

      context "and the repository does not exist" do
        let(:params) do
          {
            repository_github_id: repo.github_id + 1,
            update_job_id: update_job.id,
          }
        end

        let(:expected_tags) do
          expected_context.merge({
                                   success: false,
                                   error_code: :not_found,
                                 })
        end

        before do
          rpc_call method: "GetJobStatus", params: params
        end

        it "returns a 404" do
          expect(response.status).to be(404)
        end

        it "increments an error metric" do
          expect(MetricsClient).
            to have_received(:timing).with("twirp.request",
                                           1.0,
                                           tags: expected_tags)
        end

        it "does not raise it as an exception" do
          expect(Failbot).not_to have_received(:report)
        end
      end

      context "and the update job does not exist" do
        let(:params) do
          {
            repository_github_id: repo.github_id,
            update_job_id: update_job.id + 1,
          }
        end

        let(:expected_tags) do
          expected_context.merge({
                                   success: false,
                                   error_code: :not_found,
                                 })
        end

        before do
          rpc_call method: "GetJobStatus", params: params
        end

        it "returns a 404" do
          expect(response.status).to be(404)
        end

        it "increments an error metric" do
          expect(MetricsClient).
            to have_received(:timing).with("twirp.request",
                                           1.0,
                                           tags: expected_tags)
        end

        it "does not raise it as an exception" do
          expect(Failbot).not_to have_received(:report)
        end
      end

      context "and the update job does not belong to the repository" do
        let(:update_job) do
          FactoryBot.create(:update_job)
        end

        let(:expected_tags) do
          expected_context.merge({
                                   success: false,
                                   error_code: :not_found,
                                 })
        end

        before do
          rpc_call method: "GetJobStatus", params: params
        end

        it "returns a 404" do
          expect(response.status).to be(404)
        end

        it "increments an error metric" do
          expect(MetricsClient).
            to have_received(:timing).with("twirp.request",
                                           1.0,
                                           tags: expected_tags)
        end

        it "does not raise it as an exception" do
          expect(Failbot).not_to have_received(:report)
        end
      end

      context "and the handler raises an exception" do
        let(:error) { StandardError.new("database is gone.") }

        let(:expected_tags) do
          expected_context.merge({
                                   success: false,
                                   error_code: :internal,
                                 })
        end

        before do
          allow_any_instance_of(UpdateJobsService::V1::Handler).
            to receive(:get_job_status).and_raise(error)

          rpc_call method: "GetJobStatus", params: params
        end

        it "returns a 500" do
          expect(response.status).to be(500)
        end

        it "increments an exception metric" do
          expect(MetricsClient).
            to have_received(:timing).with("twirp.request",
                                           1.0,
                                           tags: expected_tags)
        end

        it "tracks the request as an exception" do
          error_context = expected_error_context.merge(
            transaction: "GetJobStatus",
            rollup: "4cc2f575a441560b44d6879220c6a0044c428896c6378017cce48a6a2cc86595",
          )
          expect(Failbot).
            to have_received(:report).with(error, error_context)
        end
      end
    end

    context "with an invalid request message" do
      before do
        rpc_call method: "GetJobStatus", params: "Hello World!"
      end

      it "returns a 400" do
        expect(response.status).to be(400)
      end

      it "does not raise it as an exception" do
        expect(Failbot).not_to have_received(:report)
      end

      it "does not increment an error metric" do
        expect(MetricsClient).
          not_to have_received(:timing).
          with("twirp.request", anything, anything)
      end
    end
  end

  describe "GetJobStatusByGithubRequestId" do
    let(:expected_context) do
      {
        content_type: "application/protobuf",
        rpc_method: :GetJobStatusByGithubRequestId,
      }
    end

    let(:expected_error_context) do
      {
        "http.request.header.content-type": "application/protobuf",
        "rpc.method": :GetJobStatusByGithubRequestId,
      }
    end

    let(:repo) do
      FactoryBot.create(:repo, github_id: 42)
    end

    let(:update_config) do
      FactoryBot.create(:update_config, repo: repo)
    end

    let(:update_job) do
      FactoryBot.create(:update_job, update_config: update_config)
    end

    let(:params) do
      {
        repository_github_id: repo.github_id,
        github_request_id: update_job.github_request_id,
      }
    end

    context "authentication" do
      let(:hmac_token) do
        "garbage"
      end

      let(:expected_tags) do
        expected_context.merge({
                                 success: false,
                                 error_code: :unauthenticated,
                               })
      end

      before do
        rpc_call method: "GetJobStatusByGithubRequestId", params: params
      end

      it "returns a 401" do
        expect(response.status).to be(401)
      end

      it "does not raise it as an exception" do
        expect(Failbot).not_to have_received(:report)
      end

      it "increments an error metric" do
        expect(MetricsClient).
          to have_received(:timing).with("twirp.request",
                                         1.0,
                                         tags: expected_tags)
      end
    end

    context "with a valid request message" do
      context "and the update job exists, belonging to the repository" do
        let(:expected_tags) do
          expected_context.merge({
                                   success: true,
                                   error_code: nil,
                                 })
        end

        before do
          rpc_call method: "GetJobStatusByGithubRequestId", params: params
        end

        it "returns a 200" do
          expect(response.status).to be(200)
        end

        it "increments a success metric" do
          expect(MetricsClient).
            to have_received(:timing).with("twirp.request",
                                           1.0,
                                           tags: expected_tags)
        end
      end

      context "and the repository does not exist" do
        let(:params) do
          {
            repository_github_id: repo.github_id + 1,
            github_request_id: update_job.github_request_id,
          }
        end

        let(:expected_tags) do
          expected_context.merge({
                                   success: false,
                                   error_code: :not_found,
                                 })
        end

        before do
          rpc_call method: "GetJobStatusByGithubRequestId", params: params
        end

        it "returns a 404" do
          expect(response.status).to be(404)
        end

        it "increments an error metric" do
          expect(MetricsClient).
            to have_received(:timing).with("twirp.request",
                                           1.0,
                                           tags: expected_tags)
        end

        it "does not raise it as an exception" do
          expect(Failbot).not_to have_received(:report)
        end
      end

      context "and the update job does not exist" do
        let(:params) do
          {
            repository_github_id: repo.github_id,
            github_request_id: update_job.github_request_id + 1,
          }
        end

        let(:expected_tags) do
          expected_context.merge({
                                   success: false,
                                   error_code: :not_found,
                                 })
        end

        before do
          rpc_call method: "GetJobStatusByGithubRequestId", params: params
        end

        it "returns a 404" do
          expect(response.status).to be(404)
        end

        it "increments an error metric" do
          expect(MetricsClient).
            to have_received(:timing).with("twirp.request",
                                           1.0,
                                           tags: expected_tags)
        end

        it "does not raise it as an exception" do
          expect(Failbot).not_to have_received(:report)
        end
      end

      context "and the update job does not belong to the repository" do
        let(:update_job) do
          FactoryBot.create(:update_job)
        end

        let(:expected_tags) do
          expected_context.merge({
                                   success: false,
                                   error_code: :not_found,
                                 })
        end

        before do
          rpc_call method: "GetJobStatusByGithubRequestId", params: params
        end

        it "returns a 404" do
          expect(response.status).to be(404)
        end

        it "increments an error metric" do
          expect(MetricsClient).
            to have_received(:timing).with("twirp.request",
                                           1.0,
                                           tags: expected_tags)
        end

        it "does not raise it as an exception" do
          expect(Failbot).not_to have_received(:report)
        end
      end

      context "and the handler raises an exception" do
        let(:error) { StandardError.new("database is gone.") }

        let(:expected_tags) do
          expected_context.merge({
                                   success: false,
                                   error_code: :internal,
                                 })
        end

        before do
          allow_any_instance_of(UpdateJobsService::V1::Handler).
            to receive(:get_job_status_by_github_request_id).and_raise(error)

          rpc_call method: "GetJobStatusByGithubRequestId", params: params
        end

        it "returns a 500" do
          expect(response.status).to be(500)
        end

        it "increments an exception metric" do
          expect(MetricsClient).
            to have_received(:timing).with("twirp.request",
                                           1.0,
                                           tags: expected_tags)
        end

        it "tracks the request as an exception" do
          error_context = expected_error_context.merge(
            transaction: "GetJobStatusByGithubRequestId",
            rollup: "17a47af71e5e9c4cf4ec4ddd21a62df2b313e245a83a051e3b8965f28f3de464",
          )
          expect(Failbot).
            to have_received(:report).with(error, error_context)
        end
      end
    end

    context "with an invalid request message" do
      before do
        rpc_call method: "GetJobStatusByGithubRequestId", params: "Hello World!"
      end

      it "returns a 400" do
        expect(response.status).to be(400)
      end

      it "does not raise it as an exception" do
        expect(Failbot).not_to have_received(:report)
      end

      it "does not increment an error metric" do
        expect(MetricsClient).
          not_to have_received(:timing).
          with("twirp.request", anything, anything)
      end
    end
  end

  describe "GetJobLogs" do
    let(:expected_context) do
      {
        content_type: "application/protobuf",
        rpc_method: :GetJobLogs,
      }
    end

    let(:expected_error_context) do
      {
        "http.request.header.content-type": "application/protobuf",
        "rpc.method": :GetJobLogs,
      }
    end

    let(:repo) do
      FactoryBot.create(:repo, github_id: 42)
    end

    let(:update_config) do
      FactoryBot.create(:update_config, repo: repo)
    end

    let(:update_job) do
      FactoryBot.create(:update_job, update_config: update_config)
    end

    let(:params) do
      {
        repository_github_id: repo.github_id,
        update_job_id: update_job.id,
      }
    end

    context "authentication" do
      let(:hmac_token) do
        "garbage"
      end

      let(:expected_tags) do
        expected_context.merge({
                                 success: false,
                                 error_code: :unauthenticated,
                               })
      end

      before do
        rpc_call method: "GetJobLogs", params: params
      end

      it "returns a 401" do
        expect(response.status).to be(401)
      end

      it "does not raise it as an exception" do
        expect(Failbot).not_to have_received(:report)
      end

      it "increments an error metric" do
        expect(MetricsClient).
          to have_received(:timing).with("twirp.request",
                                         1.0,
                                         tags: expected_tags)
      end
    end

    context "with a valid request message" do
      context "and the update job exists, belonging to the repository" do
        let(:expected_tags) do
          expected_context.merge({
                                   success: true,
                                   error_code: nil,
                                 })
        end
        let(:job_logs) { instance_double(UpdateJobLogs, user_readable: "") }

        before do
          allow(UpdateJobLogs).to receive(:new).and_return(job_logs)
          rpc_call method: "GetJobLogs", params: params
        end

        it "returns a 200" do
          expect(response.status).to be(200)
        end

        it "increments a success metric" do
          expect(MetricsClient).
            to have_received(:timing).with("twirp.request",
                                           1.0,
                                           tags: expected_tags)
        end
      end

      context "and the update job was processed by GH Actions" do
        let(:update_job) { FactoryBot.create(:update_job, :on_gh_actions, update_config: update_config) }

        before do
          rpc_call method: "GetJobLogs", params: params
        end

        specify { expect(response).to have_http_status(:ok) }
      end

      context "and the repository does not exist" do
        let(:params) do
          {
            repository_github_id: repo.github_id + 1,
            update_job_id: update_job.id,
          }
        end

        let(:expected_tags) do
          expected_context.merge({
                                   success: false,
                                   error_code: :not_found,
                                 })
        end

        before do
          rpc_call method: "GetJobLogs", params: params
        end

        it "returns a 404" do
          expect(response.status).to be(404)
        end

        it "increments an error metric" do
          expect(MetricsClient).
            to have_received(:timing).with("twirp.request",
                                           1.0,
                                           tags: expected_tags)
        end

        it "does not raise it as an exception" do
          expect(Failbot).not_to have_received(:report)
        end
      end

      context "and the update job does not exist" do
        let(:params) do
          {
            repository_github_id: repo.github_id,
            update_job_id: update_job.id + 1,
          }
        end

        let(:expected_tags) do
          expected_context.merge({
                                   success: false,
                                   error_code: :not_found,
                                 })
        end

        before do
          rpc_call method: "GetJobLogs", params: params
        end

        it "returns a 404" do
          expect(response.status).to be(404)
        end

        it "increments an error metric" do
          expect(MetricsClient).
            to have_received(:timing).with("twirp.request",
                                           1.0,
                                           tags: expected_tags)
        end

        it "does not raise it as an exception" do
          expect(Failbot).not_to have_received(:report)
        end
      end

      context "and the update job does not belong to the repository" do
        let(:update_job) do
          FactoryBot.create(:update_job)
        end

        let(:expected_tags) do
          expected_context.merge({
                                   success: false,
                                   error_code: :not_found,
                                 })
        end

        before do
          rpc_call method: "GetJobLogs", params: params
        end

        it "returns a 404" do
          expect(response.status).to be(404)
        end

        it "increments an error metric" do
          expect(MetricsClient).
            to have_received(:timing).with("twirp.request",
                                           1.0,
                                           tags: expected_tags)
        end

        it "does not raise it as an exception" do
          expect(Failbot).not_to have_received(:report)
        end
      end

      context "and the handler raises an exception" do
        let(:error) { StandardError.new("database is gone.") }

        let(:expected_tags) do
          expected_context.merge({
                                   success: false,
                                   error_code: :internal,
                                 })
        end

        before do
          allow_any_instance_of(UpdateJobsService::V1::Handler).
            to receive(:get_job_logs).and_raise(error)

          rpc_call method: "GetJobLogs", params: params
        end

        it "returns a 500" do
          expect(response.status).to be(500)
        end

        it "increments an exception metric" do
          expect(MetricsClient).
            to have_received(:timing).with("twirp.request",
                                           1.0,
                                           tags: expected_tags)
        end

        it "tracks the request as an exception" do
          error_context = expected_error_context.merge(
            transaction: "GetJobLogs",
            rollup: "411aa36580564f055b2c7f39c98f44db68d4f234a7e435752f4009ed9bed2832",
          )
          expect(Failbot).
            to have_received(:report).with(error, error_context)
        end
      end
    end

    context "with an invalid request message" do
      before do
        rpc_call method: "GetJobLogs", params: "Hello World!"
      end

      it "returns a 400" do
        expect(response.status).to be(400)
      end

      it "does not raise it as an exception" do
        expect(Failbot).not_to have_received(:report)
      end

      it "does not increment an error metric" do
        expect(MetricsClient).
          not_to have_received(:timing).
          with("twirp.request", anything, anything)
      end
    end
  end
end
