# frozen_string_literal: true

require "twirp_helper"

RSpec.describe DependabotApi::V1::HealthService, type: :request do
  include_context "internal twirp api"

  let(:start_time) { Time.now.utc }
  let(:end_time) { start_time + 1.second }

  before do
    allow(Failbot).to receive(:report)
    allow(MetricsClient).to receive(:timing)
    allow_any_instance_of(Services::RackApp).
      to receive(:time_now).and_return(start_time, end_time)
  end

  describe "NoSuchMethod" do
    before { rpc_call method: "NoSuchMethod" }

    it "returns a 404" do
      expect(response.status).to be(404)
    end

    it "does not record a request timing event" do
      expect(MetricsClient).
        not_to have_received(:timing).with("twirp.request", anything, anything)
    end

    it "does not track a bad request as an exception" do
      expect(Failbot).not_to have_received(:report)
    end
  end

  describe "Ping" do
    let(:expected_context) do
      {
        content_type: "application/protobuf",
        rpc_method: :Ping,
      }
    end

    let(:expected_error_context) do
      {
        "http.request.header.content-type": "application/protobuf",
        "rpc.method": :Ping,
      }
    end

    context "when everything is good" do
      let(:expected_tags) do
        expected_context.merge({
                                 success: true,
                                 error_code: nil,
                               })
      end

      before { rpc_call method: "Ping" }

      it "returns a 200" do
        expect(response.status).to be(200)
      end

      it "records a successful request metric" do
        expect(MetricsClient).
          to have_received(:timing).with("twirp.request",
                                         1.00,
                                         tags: expected_tags)
      end
    end

    context "when there is an internal exception" do
      let(:error) { StandardError.new("lp0 on fire.") }

      let(:expected_tags) do
        expected_context.merge({
                                 success: false,
                                 error_code: :internal,
                               })
      end

      before do
        allow_any_instance_of(HealthService::V1::Handler).
          to receive(:ping).and_raise(error)

        rpc_call method: "Ping"
      end

      it "returns a 500" do
        expect(response.status).to be(500)
      end

      it "records an unsuccessful request metric" do
        expect(MetricsClient).
          to have_received(:timing).with("twirp.request",
                                         1.00,
                                         tags: expected_tags)
      end

      it "tracks the request as an exception" do
        error_context = expected_error_context.merge(
          transaction: "Ping",
          rollup: "40ad97891edc96cbf264d6f61b366bdff8b697a5a8b4ec5b8f432841e0c56a03",
        )
        expect(Failbot).to have_received(:report).with(error, error_context)
      end
    end

    context "when the client has passed bad input" do
      before do
        rpc_call method: "Ping", params: "Hello World"
      end

      it "returns a 400" do
        expect(response.status).to be(400)
      end

      it "does not record a request timing event" do
        expect(MetricsClient).
          not_to have_received(:timing).
          with("twirp.request", anything, anything)
      end

      it "does not track a bad request as an exception" do
        expect(Failbot).not_to have_received(:report)
      end
    end
  end
end
