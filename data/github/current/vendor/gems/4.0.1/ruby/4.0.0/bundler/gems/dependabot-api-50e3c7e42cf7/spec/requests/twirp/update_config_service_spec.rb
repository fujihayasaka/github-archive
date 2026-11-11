# frozen_string_literal: true

require "twirp_helper"

RSpec.describe DependabotApi::V1::UpdateConfigsService, type: :request do
  include_context "internal twirp api"

  let(:start_time) { Time.now.utc }
  let(:end_time) { start_time + 1.second }

  before do
    allow(Failbot).to receive(:report)
    allow(MetricsClient).to receive(:timing)
    allow_any_instance_of(Services::RackApp).
      to receive(:time_now).and_return(start_time, end_time)
  end

  describe "DeactivateUpdateConfigs" do
    let(:expected_context) do
      {
        content_type: "application/protobuf",
        rpc_method: :DeactivateUpdateConfigs,
      }
    end

    let(:expected_error_context) do
      {
        "http.request.header.content-type": "application/protobuf",
        "rpc.method": :DeactivateUpdateConfigs,
      }
    end

    context "authentication" do
      let(:hmac_token) do
        "garbage"
      end

      let(:params) do
        {
          repository_github_id: 42,
        }
      end

      let(:expected_tags) do
        expected_context.merge({
                                 success: false,
                                 error_code: :unauthenticated,
                               })
      end

      before do
        FactoryBot.create(:repo, github_id: 42)
        rpc_call method: "DeactivateUpdateConfigs", params: params
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
      let(:params) do
        {
          repository_github_id: 42,
        }
      end

      let(:expected_tags) do
        expected_context.merge({
                                 success: true,
                                 error_code: nil,
                               })
      end

      context "and the repository exists" do
        before do
          FactoryBot.create(:repo, github_id: 42)
          rpc_call method: "DeactivateUpdateConfigs", params: params
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
        let(:expected_tags) do
          expected_context.merge({
                                   success: false,
                                   error_code: :not_found,
                                 })
        end

        before do
          rpc_call method: "DeactivateUpdateConfigs", params: params
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
          allow_any_instance_of(UpdateConfigsService::V1::Handler).
            to receive(:deactivate_update_configs).and_raise(error)

          rpc_call method: "DeactivateUpdateConfigs", params: params
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
            transaction: "DeactivateUpdateConfigs",
            rollup: "0782354d7fb5da930bd9bc4ab68d1960",
          )
          expect(Failbot).
            to have_received(:report).with(error, error_context)
        end
      end
    end

    context "with an invalid request message" do
      before do
        FactoryBot.create(:repo, github_id: 42)
        rpc_call method: "DeactivateUpdateConfigs", params: "Hello World!"
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

  describe "ListUpdateConfigs" do
    let(:expected_context) do
      {
        content_type: "application/protobuf",
        rpc_method: :ListUpdateConfigs,
      }
    end

    let(:expected_error_context) do
      {
        "http.request.header.content-type": "application/protobuf",
        "rpc.method": :ListUpdateConfigs,
      }
    end

    context "authentication" do
      let(:hmac_token) do
        "garbage"
      end

      let(:params) do
        {
          repository_github_id: 42,
        }
      end

      let(:expected_tags) do
        expected_context.merge({
                                 success: false,
                                 error_code: :unauthenticated,
                               })
      end

      before do
        FactoryBot.create(:repo, github_id: 42)
        rpc_call method: "ListUpdateConfigs", params: params
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
      let(:params) do
        {
          repository_github_id: 42,
        }
      end

      let(:expected_tags) do
        expected_context.merge({
                                 success: true,
                                 error_code: nil,
                               })
      end

      context "and the repository exists" do
        before do
          FactoryBot.create(:repo, github_id: 42)
          rpc_call method: "ListUpdateConfigs", params: params
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
        let(:expected_tags) do
          expected_context.merge({
                                   success: false,
                                   error_code: :not_found,
                                 })
        end

        before do
          rpc_call method: "ListUpdateConfigs", params: params
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
          allow_any_instance_of(UpdateConfigsService::V1::Handler).
            to receive(:list_update_configs).and_raise(error)

          rpc_call method: "ListUpdateConfigs", params: params
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
            transaction: "ListUpdateConfigs",
            rollup: "d30272bd9c28b7a7746a51902c8a4d87",
          )
          expect(Failbot).
            to have_received(:report).with(error, error_context)
        end
      end
    end

    context "with an invalid request message" do
      before do
        FactoryBot.create(:repo, github_id: 42)
        rpc_call method: "ListUpdateConfigs", params: "Hello World!"
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

  describe "RepositoryStatus" do
    let(:expected_context) do
      {
        content_type: "application/protobuf",
        rpc_method: :RepositoryStatus,
      }
    end

    let(:expected_error_context) do
      {
        "http.request.header.content-type": "application/protobuf",
        "rpc.method": :RepositoryStatus,
      }
    end

    let(:params) do
      {
        repository_github_id: 42,
      }
    end

    context "and the repository exists" do
      let(:expected_tags) do
        expected_context.merge({
                                 success: true,
                                 error_code: nil,
                               })
      end

      before do
        FactoryBot.create(:repo, github_id: 42)
        rpc_call method: "RepositoryStatus", params: params
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
      let(:expected_tags) do
        expected_context.merge({
                                 success: false,
                                 error_code: :not_found,
                               })
      end

      before do
        rpc_call method: "RepositoryStatus", params: params
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
        allow_any_instance_of(UpdateConfigsService::V1::Handler).
          to receive(:repository_status).and_raise(error)

        rpc_call method: "RepositoryStatus", params: params
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
          transaction: "RepositoryStatus",
          rollup: "1e9e785a2f531b73c1f2ea42eff0754a",
        )
        expect(Failbot).
          to have_received(:report).with(error, error_context)
      end
    end
  end

  describe "ResyncConfigFile" do
    let(:expected_context) do
      {
        content_type: "application/protobuf",
        rpc_method: :ResyncConfigFile,
      }
    end
    let(:expected_error_context) do
      {
        "http.request.header.content-type": "application/protobuf",
        "rpc.method": :ResyncConfigFile,
      }
    end

    context "authentication" do
      let(:hmac_token) do
        "garbage"
      end

      let(:params) do
        {
          repository_github_id: 42,
        }
      end

      let(:expected_tags) do
        expected_context.merge({
                                 success: false,
                                 error_code: :unauthenticated,
                               })
      end

      before do
        FactoryBot.create(:repo, github_id: 42)
        rpc_call method: "ResyncConfigFile", params: params
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
      let(:params) do
        {
          repository_github_id: 42,
        }
      end

      let(:expected_tags) do
        expected_context.merge({
                                 success: true,
                                 error_code: nil,
                               })
      end

      context "and the repository exists" do
        before do
          FactoryBot.create(:repo, github_id: 42)
          rpc_call method: "ResyncConfigFile", params: params
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
        let(:expected_tags) do
          expected_context.merge({
                                   success: false,
                                   error_code: :failed_precondition,
                                 })
        end

        before do
          rpc_call method: "ResyncConfigFile", params: params
        end

        it "returns a 404" do
          expect(response.status).to be(412)
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
          allow_any_instance_of(UpdateConfigsService::V1::Handler).
            to receive(:resync_config_file).and_raise(error)

          rpc_call method: "ResyncConfigFile", params: params
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
            transaction: "ResyncConfigFile",
            rollup: "3b07d134b85e6967e9dd6aff2bf146bf",
          )
          expect(Failbot).
            to have_received(:report).with(error, error_context)
        end
      end
    end

    context "with an invalid request message" do
      before do
        FactoryBot.create(:repo, github_id: 42)
        rpc_call method: "ResyncConfigFile", params: "Hello World!"
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
