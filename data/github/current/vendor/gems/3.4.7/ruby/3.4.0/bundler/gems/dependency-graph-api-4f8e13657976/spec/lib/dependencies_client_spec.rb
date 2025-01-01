require "rails_helper"
require_relative "../../lib/dependency_snapshots_api/dependencies_client"

RSpec.describe DependencyGraphAPI::DependencySnapshotsAPI::DependenciesClient do
  let(:client) { described_class.new }
  let(:repository_id) { 12345 }
  let(:base_purl) { "pkg:/npm/%40actions/core" }
  let(:version_range) { ">=1.0.0" }

  describe "#get_dependencies_for_repository" do
    it "calls the client with the correct parameters, not including relationship_filter" do
      request = Github::DependencySnapshotsApi::GetDependenciesForRepositoryRequest.new(
        repository_id: repository_id,
        include_internal_snapshots: false,
        include_root_ancestors: false,
        relationship_filter: nil
      )

      expect(client.client).to receive(:get_dependencies_for_repository).with(request)
      client.get_dependencies_for_repository(repository_id)
    end

    it "correctly translates the incoming relationship filter to ds-api's proto" do
      supported_relationship_filters = {
        # see proto/twirp/v1/dependency_graph_api.proto for LHS,
        # and https://github.com/github/dependency-snapshots-api/blob/main/proto/dependencies.proto for the RHS
        nil => nil,
        :RELATIONSHIP_UNKNOWN => :RELATIONSHIP_UNKNOWN,
        :RELATIONSHIP_DIRECT => :RELATIONSHIP_DIRECT,
        :RELATIONSHIP_TRANSITIVE => :RELATIONSHIP_TRANSITIVE,
        :RELATIONSHIP_INCONCLUSIVE => :RELATIONSHIP_UNKNOWN, # there is no "inconclusive" relationship in ds-api
        :TEST_INVALID_FILTER => nil,
       }

      supported_relationship_filters.each do |dgapi_relationship, dsapi_relationship|
        expected_request = Github::DependencySnapshotsApi::GetDependenciesForRepositoryRequest.new(
          repository_id: repository_id,
          include_internal_snapshots: false,
          include_root_ancestors: false,
          relationship_filter: dsapi_relationship
        )

        expect(client.client).to receive(:get_dependencies_for_repository).with(expected_request)
        client.get_dependencies_for_repository(repository_id, relationship_filter: dgapi_relationship)
      end
    end
  end

  describe "#repositories_containing_dependency" do
    it "calls the client with the correct parameters" do
      request = Github::DependencySnapshotsApi::RepositoriesContainingDependencyRequest.new(
        base_purl: base_purl,
        version_range: version_range
      )

      expect(client.client).to receive(:repositories_containing_dependency).with(request)
      client.repositories_containing_dependency(base_purl, version_range)
    end
  end
end
