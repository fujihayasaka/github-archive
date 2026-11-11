# frozen_string_literal: true

require "rails_helper"

RSpec.describe EnableAutoMerge do
  subject(:action) { described_class.new(pull_request: pr) }

  let(:pr) { FactoryBot.create(:pull_request) }
  let(:graphql_endpoint) { Dependabot::Application.target_github_graphql_endpoint }
  let(:get_pull_request_id_action) { instance_double(GetPullRequestId) }

  before do
    allow(GitHubHelpers).to receive(:installation_access_token_for).and_return("token")
    allow(GetPullRequestId).to receive(:new).and_return(get_pull_request_id_action)
    allow(get_pull_request_id_action).to receive(:run).and_return("PR_somevalidID")
    stub_request(:post, graphql_endpoint).
      to_return(
        status: 200,
        body: enable_auto_merge_response_body,
        headers: { "Content-Type" => "application/json" },
      )
  end

  context "enable auto merge on a pull request" do
    let(:enable_auto_merge_response_body) do
      fixture "github_responses/graphql_enable_pull_request_auto_merge_success.json"
    end

    it "enables succesfully" do
      result = action.run
      expect(result).to be_instance_of(EnableAutoMerge::EnableAutoMergeResult)
      expect(result.success?).to be(true)
    end

    it "lists Dependabot as the actor" do
      response = action.send(:make_graphql_request, pr)
      expect(response.data.to_h["enablePullRequestAutoMerge"]["actor"]["login"]).to eq("dependabot[bot]")
    end
  end

  context "when the response is unprocessable" do
    let(:enable_auto_merge_response_body) do
      fixture "github_responses/graphql_enable_pull_request_auto_merge_node_not_found.json"
    end

    it "raises a missing subject error" do
      expect { action.run }.to raise_error(described_class::MissingSubjectError, /Could not resolve to a node/)
    end
  end

  context "when the branch is clean" do
    let(:enable_auto_merge_response_body) do
      fixture "github_responses/graphql_enable_pull_request_auto_merge_clean.json"
    end

    it "returns :clean" do
      result = action.run
      expect(result).to be_instance_of(EnableAutoMerge::EnableAutoMergeResult)
      expect(result.clean?).to be(true)
    end
  end

  context "when the query returns errors" do
    let(:enable_auto_merge_response_body) do
      fixture "github_responses/graphql_enable_pull_request_auto_merge_errors.json"
    end

    it "raises a validation error" do
      expect { action.run }.to raise_error(described_class::GitHubValidationError, /belongs to a different repository/)
    end
  end

  context "as the query was invalid" do
    let(:enable_auto_merge_response_body) do
      fixture "github_responses/graphql_enable_pull_request_auto_merge_query_error.json"
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
