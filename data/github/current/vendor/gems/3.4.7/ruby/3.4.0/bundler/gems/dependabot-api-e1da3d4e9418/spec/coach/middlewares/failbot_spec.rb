# frozen_string_literal: true

require "rails_helper"

RSpec.describe Middlewares::Failbot do
  subject(:instance) { described_class.new(context, null_middleware, config) }

  let(:context) do
    { request: instance_double(ActionDispatch::Request) }
  end
  let(:config) { { route_class: Routes::Ping } }

  it "sets the failbot context to the route class" do
    expect(::Dependabot::Exceptions).to receive(:push).with(transaction: "Routes::Ping")
    instance.call
  end
end
