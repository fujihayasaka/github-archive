require_relative "../spec_helper"
require_relative "../api_helper"

describe "GraphQL API" do
  let(:client) { ApiHelper::DependencyGraphClient.new }
  let(:graphql_packages_query) do <<~GRAPHQL
  {
    packageReleases(packageName: "rails", packageManager: RUBYGEMS) {
      nodes {
        packageName
      }
    }
  }
  GRAPHQL
  end

  it "makes an authenticated request" do
    status, response = client.graphql graphql_packages_query
    expect(status).to eq(200)
    expect(response["data"]["packageReleases"]["nodes"].length).to eq(0)
  end

  it "returns HTTP 401 when an invalid HMAC token is used." do
    status, response = client.graphql graphql_packages_query, hmac: "invalid-hmac"
    expect(status).to eq(401)
  end
end
