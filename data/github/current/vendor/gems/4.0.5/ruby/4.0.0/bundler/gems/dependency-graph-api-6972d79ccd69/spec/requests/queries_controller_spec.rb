require "rails_helper"
require "dependency_snapshots_api/dependencies_client"
require_relative "../lib/monolith/features_helpers.rb"

describe QueriesController do
  include Monolith::FeaturesHelpers

  before(:each) do
    # Disable the DGP gateway by default
    allow_any_instance_of(Queries::ManifestsQuery).to receive(:dgp_available).and_return(false)
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

  describe "GraphQL error instrumentation" do
    before do
      allow(Rails.application.stats).to receive(:distribution)
      allow(Rails.application.stats).to receive(:increment)
      allow(Rails.application.stats).to receive(:decrement)
      allow(Rails.application.stats).to receive(:timing)
    end

    it "increments graphql.query.error for GraphQL execution errors" do
      post "/query",
        params: {
          query: <<-GRAPHQL
          {
            repositoryPackageReleases(ownerIds: []) {
              nodes {
                name
              }
            }
          }
          GRAPHQL
        },
        as: :json

      expect(Rails.application.stats).to have_received(:increment).with("graphql.query.error",
        tags: array_including("operation_name:anonymous", "mutation:false"))
    end

    it "preserves the named operation and error path in error tags" do
      post "/query",
        params: {
          query: <<-GRAPHQL
          query GetPackageReleases {
            repositoryPackageReleases(ownerIds: []) {
              nodes {
                name
              }
            }
          }
          GRAPHQL
        },
        as: :json

      expect(Rails.application.stats).to have_received(:increment).with("graphql.query.error",
        tags: array_including(
          "operation_name:GetPackageReleases",
          "mutation:false",
          "error_path:repositoryPackageReleases.nodes.name",
        ))
    end

    it "does not increment graphql.query.error for successful queries" do
      post "/query",
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
      expect(Rails.application.stats).not_to have_received(:increment).with("graphql.query.error", anything)
    end

    it "increments graphql.query.unhandled_error when an exception escapes query execution" do
      allow(Instrument).to receive(:increment)

      allow_any_instance_of(GraphQL::Query).to receive(:result).and_raise(RuntimeError, "unexpected boom")

      # The exception is re-raised but caught by Rails middleware, so we just make the request
      post "/query",
        params: { query: "{ manifests(repositoryIds: [1]) { nodes { filename } } }" },
        as: :json

      expect(Instrument).to have_received(:increment).with("graphql.query.unhandled_error",
        error_class: "RuntimeError",
        operation_name: anything,
        mutation: anything,
      )
    end

    it "rescues Rack::Timeout and returns 200 with GraphQL error response" do
      allow(Instrument).to receive(:increment)

      allow_any_instance_of(GraphQL::Query).to receive(:result).and_raise(Rack::Timeout::RequestTimeoutException.new({}))

      post "/query",
        params: { query: "{ manifests(repositoryIds: [1]) { nodes { filename } } }" },
        as: :json

      expect(response).to have_http_status(:ok)
      expect(Instrument).to have_received(:increment).with("graphql.query.timeout")
      expect(Instrument).not_to have_received(:increment).with("graphql.query.unhandled_error", any_args)

      body = JSON.parse(response.body)
      expect(body["data"]).to be_nil
      expect(body["errors"]).to be_present
      expect(body["errors"].first["message"]).to eq("Request timed out")
    end

    context "GraphQL timeout override" do
      it "lowers Rack::Timeout for GraphQL requests on fast-api hosts" do
        allow(Rails.application).to receive(:fast_api_host?).and_return(true)

        rt_info = Rack::Timeout::RequestDetails.new
        rt_info.timeout = DependencyGraph::Application::API_RACK_TIMEOUT

        allow_any_instance_of(ActionDispatch::Request).to receive(:env).and_wrap_original do |original, *args|
          env = original.call(*args)
          env["rack-timeout.info"] ||= rt_info
          env
        end

        post "/query",
          params: { query: "{ manifests(repositoryIds: [1]) { nodes { filename } } }" },
          as: :json

        expect(rt_info.timeout).to eq(DependencyGraph::Application::GRAPHQL_RACK_TIMEOUT)
      end

      it "does not modify Rack::Timeout on non-fast-api hosts" do
        allow(Rails.application).to receive(:fast_api_host?).and_return(false)

        rt_info = Rack::Timeout::RequestDetails.new
        rt_info.timeout = 120

        allow_any_instance_of(ActionDispatch::Request).to receive(:env).and_wrap_original do |original, *args|
          env = original.call(*args)
          env["rack-timeout.info"] ||= rt_info
          env
        end

        post "/query",
          params: { query: "{ manifests(repositoryIds: [1]) { nodes { filename } } }" },
          as: :json

        expect(rt_info.timeout).to eq(120)
      end
    end
  end
end
