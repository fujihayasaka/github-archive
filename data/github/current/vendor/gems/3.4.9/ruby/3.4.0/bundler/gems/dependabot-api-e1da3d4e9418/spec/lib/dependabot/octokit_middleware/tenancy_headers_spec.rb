# frozen_string_literal: true

require "rails_helper"
require "github_helpers"

RSpec.describe Dependabot::OctokitMiddleware::TenancyHeaders do
  let(:account) { create(:account) }
  let(:middleware) { described_class.new(app, tenant: account.tenant) }
  let(:app) { ->(env) { Faraday::Response.new(env) } }

  it "sets the X-GitHub-Tenant header", :proxima do
    env = { request_headers: {} }
    response = middleware.call(env)

    expect(response.env[:request_headers]["X-GitHub-Tenant"]).
      to eq(account.tenant.slug)
  end

  it "omits the X-GitHub-Tenant header", proxima: false do
    env = { request_headers: {} }
    response = middleware.call(env)

    expect(response.env[:request_headers]).not_to have_key("X-GitHub-Tenant")
  end

  it "calls the next middleware in the stack" do
    env = { request_headers: {} }
    allow(app).to receive(:call).with(env).and_return(Faraday::Response.new(env))

    middleware.call(env)

    expect(app).to have_received(:call).with(env)
  end
end
