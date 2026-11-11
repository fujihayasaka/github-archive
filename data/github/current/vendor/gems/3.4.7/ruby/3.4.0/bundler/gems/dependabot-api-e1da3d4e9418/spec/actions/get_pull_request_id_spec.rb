# frozen_string_literal: true

require "rails_helper"

RSpec.describe GetPullRequestId do
  subject(:action) { described_class.new(pull_request: pr) }

  let(:pr) { FactoryBot.create(:pull_request) }
  let(:graphql_endpoint) { Dependabot::Application.target_github_graphql_endpoint }

  before do
    allow(GitHubHelpers).to receive(:installation_access_token_for).and_return("token")
    stub_request(:post, graphql_endpoint).
      to_return(
        status: 200,
        body: get_pull_request_id_response_body,
        headers: { "Content-Type" => "application/json" },
      )
  end

  context "gets the pull request id" do
    let(:get_pull_request_id_response_body) do
      fixture "github_responses/graphql_get_pull_request_id_success.json"
    end

    it "returns the id" do
      expect(action.run).to eq("PR_kwDOJGio3s5LfY5K")
    end
  end

  context "when the response is unprocessable" do
    let(:get_pull_request_id_response_body) do
      fixture "github_responses/graphql_get_pull_request_id_node_not_found.json"
    end

    it "raises a missing subject error" do
      expect { action.run }.to raise_error(described_class::MissingSubjectError, /Could not resolve to a node/)
    end
  end

  context "when the query returns errors" do
    let(:get_pull_request_id_response_body) do
      fixture "github_responses/graphql_get_pull_request_id_errors.json"
    end

    it "raises a validation error" do
      expect { action.run }.to raise_error(described_class::GitHubValidationError, /belongs to a different repository/)
    end
  end

  context "as the query was invalid" do
    let(:get_pull_request_id_response_body) do
      fixture "github_responses/graphql_get_pull_request_id_query_error.json"
    end

    it "raises an exception" do
      expect { action.run }.
        to raise_error(
          described_class::GraphQLQueryError,
          "Variable databaseId of type Int! was provided invalid value",
        )
    end
  end
end
