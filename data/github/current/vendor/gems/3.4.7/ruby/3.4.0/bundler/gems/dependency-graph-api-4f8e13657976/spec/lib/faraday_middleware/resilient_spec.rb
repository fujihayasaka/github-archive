require "rails_helper"
require "faraday_middleware/resilient"

describe DependencyGraph::FaradayMiddleware::Resilient do
  let(:client) do
    Faraday.new(url: "http://dg.test") do |conn|
      conn.use DependencyGraph::FaradayMiddleware::Resilient, name: "resilient-spec", options: {
        # Some default options that should allow us to trip the circuit breaker really quickly
        sleep_window_seconds: 10,
        error_threshold_percentage: 1,
        request_volume_threshold: 1,
        window_size_in_seconds: 2,
        bucket_size_in_seconds: 1,
        instrumenter: ActiveSupport::Notifications,
      }

      conn.adapter :test do |stub|
        # good endpoint
        stub.get("/ping") do |env|
          [
            200,
            { 'Content-Type': "text/plain", },
            "pong"
          ]
        end

        # bad endpoint
        stub.get("/boom") do
          [
            500,
            { 'Content-Type': "text/plain", },
            "boom"
          ]
        end
      end
    end
  end

  before do
    allow(Rails.application.stats).to receive(:increment).and_call_original
  end

  it "trips the circuit breaker after a series of bad requests" do
    response = client.get("/ping")
    expect(response.status).to eq(200)
    expect(response.headers["Resilient"]).to be_nil

    expect(Rails.application.stats).to have_received(:increment).with("resilient.circuit_breaker.allowed", anything)

    5.times do
      client.get("/boom")
    end

    response = client.get("/ping")
    expect(response.status).to eq(502)
    expect(response.headers["Resilient"]).to eq("yes")

    expect(Rails.application.stats).to have_received(:increment).with("resilient.circuit_breaker.rejected", anything).at_least(:once)
  end
end
