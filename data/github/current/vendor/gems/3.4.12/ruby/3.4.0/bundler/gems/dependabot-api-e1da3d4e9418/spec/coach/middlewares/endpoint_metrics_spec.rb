# frozen_string_literal: true

require "rails_helper"

RSpec.describe Middlewares::EndpointMetrics do
  subject(:instance) { described_class.new(context, null_middleware, config) }

  let(:context) do
    { request: instance_double(ActionDispatch::Request) }
  end
  let(:config) { { route_class: Routes::Ping } }

  it "logs that the endpoint was requested" do
    expect(MetricsClient).to receive(:increment).with("request", tags: { endpoint: "Routes::Ping" })
    instance.call
  end
end
