require "rails_helper"
require "dependency_snapshots_api/dependencies_client"
require_relative "../lib/monolith/features_helpers.rb"

describe QueriesController do
  include Monolith::FeaturesHelpers

  before do
    DependencyGraph.flipper.disable(:dependency_graph_dgp_backed_npm_graphql)
  end

  before(:each) do
    allow_any_instance_of(DependencyGraphAPI::DependencySnapshotsAPI::DependenciesClient)
      .to receive(:get_dependencies_for_repository).and_return(twirp_response)
  end

  let(:twirp_response) do
    Twirp::ClientResp.new(
      data: Github::DependencySnapshotsApi::GetDependenciesForRepositoryResponse.new(manifests: {})
    )
  end

  it "instruments Query-Type header as a tag" do
    allow(Rails.application.stats).to receive(:distribution)
    allow(Rails.application.stats).to receive(:increment)

    post "/query",
      headers: {
        "X-GitHub-DepGraph-Query-Type" => "TestQuery",
        "GitHub-DepGraph-User-Type" => "crawler"
      },
      params: {
        query: <<-GRAPHQL
        {
          manifests(repositoryIds: [100]) {
            nodes {
              filename
            }
          }
        }
        GRAPHQL
      },
      as: :json

    expect(response).to be_successful

    expected_tags = [
      "controller:QueriesController", "action:create", "status:200", "query_type:TestQuery", "user_type:crawler"
    ]

    expect(Rails.application.stats).to have_received(:distribution).with("action_controller.request.dist.time", anything,
      hash_including(tags: array_including(*expected_tags)))

    expect(Rails.application.stats).to have_received(:increment).with("action_controller.request",
      hash_including(tags: array_including(*expected_tags)))
  end
end
