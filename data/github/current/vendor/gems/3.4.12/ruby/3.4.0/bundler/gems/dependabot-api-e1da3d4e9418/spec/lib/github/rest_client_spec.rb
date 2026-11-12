# frozen_string_literal: true

require "rails_helper"

RSpec.describe GitHub::RESTClient do
  subject(:client) { described_class.new(max_retries:) }

  let(:max_retries) { 3 }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:github_org_url) { github_url + "orgs/github" }
  let(:user_url) { github_url + "user" }
  let(:json_header) { { "Content-Type" => "application/json" } }

  before do
    stub_request(:get, github_org_url).
      to_return(status: 200, body: "{}", headers: json_header)
  end

  it { is_expected.to be_a(Octokit::Client) }

  it "retries common failures by default" do
    stub_request(:get, user_url).to_raise(Faraday::ConnectionFailed)

    expect(client.middleware.handlers).to include(Faraday::Retry::Middleware)

    expect { client.user }.to raise_error(Faraday::ConnectionFailed)
    expect(WebMock).to have_requested(:get, user_url).times(max_retries + 1)
  end

  it "uses the default dependabot user-agent and target github api endpoint" do
    client.organization("github")
    expect(WebMock).to have_requested(:get, github_org_url).
      with(headers: { "User-Agent" => %r{github/dependabot-api \(Octokit Ruby Gem \d+\.\d+\.\d+\)} })
  end

  it "does not mutate the global octokit middleware stack" do
    expect(client.middleware).not_to equal(Octokit.middleware)
  end
end
