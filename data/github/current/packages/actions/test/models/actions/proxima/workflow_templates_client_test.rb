# typed: true
# frozen_string_literal: true

require "test_helper"

class Actions::Proxima::WorkflowTemplatesClientTest < GitHub::TestCase
  BASE_URL = "#{GitHub.dotcom_host_protocol}://#{GitHub.dotcom_api_host_name}"
  STARTER_WORKFLOWS_FOLDERS = %w[automation ci code-scanning deployments icons pages]

  setup do
    @token = "bearer token"
    @sha = "be552580a63fc68faa5036cf1ae2646d3ee1bb37"
    @repo_owner, @repo_name = "actions/starter-workflows".split("/")

    @connection = GitHub::FaradayClient::External.new({ url: BASE_URL }) do |f|
      f.adapter Faraday.default_adapter
    end
    @token_generator = stub(generate_token: @token)
  end

  context "#files_query" do
    test "generates an appropriate query" do
      starter_workflows = Actions::Proxima::WorkflowTemplatesClient.new(
        repo_owner: @repo_owner,
        repo_name: @repo_name,
        connection: @connection,
        token_generator: @token_generator,
      )

      expected_query = <<~'GRAPHQL'
        query ($repo_owner: String!, $repo_name: String!) {
          repository(name: $repo_name, owner: $repo_owner) {
            automation:object(expression: "be552580a63fc68faa5036cf1ae2646d3ee1bb37:automation") {
              ...FilesWithContentsFragment
            }
            automationproperties:object(expression: "be552580a63fc68faa5036cf1ae2646d3ee1bb37:automation/properties") {
              ...FilesWithContentsFragment
            }
            ci:object(expression: "be552580a63fc68faa5036cf1ae2646d3ee1bb37:ci") {
              ...FilesWithContentsFragment
            }
            ciproperties:object(expression: "be552580a63fc68faa5036cf1ae2646d3ee1bb37:ci/properties") {
              ...FilesWithContentsFragment
            }
            codescanning:object(expression: "be552580a63fc68faa5036cf1ae2646d3ee1bb37:code-scanning") {
              ...FilesWithContentsFragment
            }
            codescanningproperties:object(expression: "be552580a63fc68faa5036cf1ae2646d3ee1bb37:code-scanning/properties") {
              ...FilesWithContentsFragment
            }
            deployments:object(expression: "be552580a63fc68faa5036cf1ae2646d3ee1bb37:deployments") {
              ...FilesWithContentsFragment
            }
            deploymentsproperties:object(expression: "be552580a63fc68faa5036cf1ae2646d3ee1bb37:deployments/properties") {
              ...FilesWithContentsFragment
            }
            icons:object(expression: "be552580a63fc68faa5036cf1ae2646d3ee1bb37:icons") {
              ...FilesWithContentsFragment
            }
            pages:object(expression: "be552580a63fc68faa5036cf1ae2646d3ee1bb37:pages") {
              ...FilesWithContentsFragment
            }
            pagesproperties:object(expression: "be552580a63fc68faa5036cf1ae2646d3ee1bb37:pages/properties") {
              ...FilesWithContentsFragment
            }
          }
        }

        fragment FilesWithContentsFragment on Tree {
          files:entries {
            path,
            object {
              ... on Blob {
                text,
                isTruncated
              }
            }
          }
        }
      GRAPHQL

      files_query = starter_workflows.files_query(@sha, STARTER_WORKFLOWS_FOLDERS)
      assert_equal expected_query, files_query
    end
  end

  context "#all_templates" do
    test "raises an error when the request fails" do
      stub_request(:post, /#{GitHub.dotcom_api_host_name}#{GitHub.dotcom_graphql_api_prefix}\z/)
      .to_return(status: 401, body: JSON.generate({
        message: "Bad credentials",
        documentation_url: "https://docs.github.com/graphql",
      }))

      starter_workflows = Actions::Proxima::WorkflowTemplatesClient.new(
        repo_owner: @repo_owner,
        repo_name: @repo_name,
        connection: @connection,
        token_generator: @token_generator,
      )

      assert_raises Actions::Proxima::WorkflowTemplatesError, match: /GraphQL request failed/ do
        starter_workflows.fetch_templates(@sha, STARTER_WORKFLOWS_FOLDERS)
      end
    end

    test "raises an error when the response cannot be parsed" do
      stub_request(:post, /#{GitHub.dotcom_api_host_name}#{GitHub.dotcom_graphql_api_prefix}\z/)
      .to_return(status: 200, body: "{lol")

      starter_workflows = Actions::Proxima::WorkflowTemplatesClient.new(
        repo_owner: @repo_owner,
        repo_name: @repo_name,
        connection: @connection,
        token_generator: @token_generator,
      )

      assert_raises Actions::Proxima::WorkflowTemplatesError, match: /failed to parse response/ do
        starter_workflows.fetch_templates(@sha, STARTER_WORKFLOWS_FOLDERS)
      end
    end

    test "raises an error when the response contains errors" do
      stub_request(:post, /#{GitHub.dotcom_api_host_name}#{GitHub.dotcom_graphql_api_prefix}\z/)
      .to_return(status: 200, body: JSON.generate({
        "errors" => [{
            "extensions" => { "value" => nil, "problems" => [{ "path" => [], "explanation" => "Expected value to not be null" }] },
            "locations" => [{ "line" => 1, "column" => 30 }],
            "message" => "Variable $repo_name of type String! was provided invalid value",
        }]
      }))

      starter_workflows = Actions::Proxima::WorkflowTemplatesClient.new(
        repo_owner: @repo_owner,
        repo_name: @repo_name,
        connection: @connection,
        token_generator: @token_generator,
      )

      assert_raises Actions::Proxima::WorkflowTemplatesError, match: /GraphQL response contained errors/ do
        starter_workflows.fetch_templates(@sha, STARTER_WORKFLOWS_FOLDERS)
      end
    end

    test "returns workflow template files from dotcom" do
      VCR.use_cassette("actions/graphql-starter-workflows") do
        starter_workflows = Actions::Proxima::WorkflowTemplatesClient.new(
          repo_owner: @repo_owner,
          repo_name: @repo_name,
          connection: @connection,
          token_generator: @token_generator,
        )

        expected_folders = %w[automation automationproperties ci ciproperties codescanning codescanningproperties deployments deploymentsproperties icons pages pagesproperties]
        workflow_files = starter_workflows.fetch_templates(@sha, STARTER_WORKFLOWS_FOLDERS)
        assert_equal expected_folders, workflow_files.keys

        expected_folders.each do |folder|
          alias_name = folder.gsub(/[^\w]/, "")

          assert workflow_files.dig(alias_name), "expected #{folder} to exist"
          assert workflow_files.dig(alias_name, "files").count > 0, "expected files to exist for #{folder}"
        end
      end
    end
  end
end
