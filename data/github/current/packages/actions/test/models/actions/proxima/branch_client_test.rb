# typed: true
# frozen_string_literal: true

require "test_helper"

class Actions::Proxima::BranchClientTest < GitHub::TestCase
  BASE_URL = "#{GitHub.dotcom_host_protocol}://#{GitHub.dotcom_api_host_name}"

  setup do
    @token = "bearer token"
    @branch = "main"
    @nwo = "actions/starter-workflows"
    @branch_uri = "/repos/#{@nwo}/git/trees/#{@branch}"

    @connection = GitHub::FaradayClient::External.new({ url: BASE_URL }) do |f|
      f.adapter Faraday.default_adapter
    end

    @token_generator = stub(generate_token: @token)
  end

  context "#sha_for_branch" do
    test "raises an error when the request fails" do
      stub_request(:get, /#{GitHub.dotcom_api_host_name}#{@branch_uri}\z/)
      .to_return(status: 401, body: JSON.generate({
        message: "Bad credentials",
        documentation_url: "https://docs.github.com/graphql",
      }))

      branch_client = Actions::Proxima::BranchClient.new(
        connection: @connection,
        token_generator: @token_generator,
      )

      assert_raises(Actions::Proxima::WorkflowTemplatesError, match: /request failed/i) do
        branch_client.sha_for_branch(@nwo, @branch)
      end
    end

    test "raises an error when the response cannot be parsed" do
      stub_request(:get, /#{GitHub.dotcom_api_host_name}#{@branch_uri}\z/)
      .to_return(status: 200, body: "{ lol")

      branch_client = Actions::Proxima::BranchClient.new(
        connection: @connection,
        token_generator: @token_generator,
      )

      assert_raises(Actions::Proxima::WorkflowTemplatesError, match: /failed to parse response/i) do
        branch_client.sha_for_branch(@nwo, @branch)
      end
    end

    test "raises an error when the response contains errors" do
      stub_request(:get, /#{GitHub.dotcom_api_host_name}#{@branch_uri}\z/)
      .to_return(status: 200, body: "{}")

      branch_client = Actions::Proxima::BranchClient.new(
        connection: @connection,
        token_generator: @token_generator,
      )

      assert_raises(Actions::Proxima::WorkflowTemplatesError, match: /parsed response didn't contain sha/i) do
        branch_client.sha_for_branch(@nwo, @branch)
      end
    end

    test "returns workflow template files from dotcom" do
      expected_sha = "be552580a63fc68faa5036cf1ae2646d3ee1bb37"

      stub_request(:get, /#{GitHub.dotcom_api_host_name}#{@branch_uri}\z/)
      .to_return(status: 200, body: JSON.generate({
        "sha" => expected_sha,
          "url" => "https://api.github.com/repos/actions/starter-workflows/git/trees/be552580a63fc68faa5036cf1ae2646d3ee1bb37",
          "tree" => [
            { "path" => ".gitattributes", "mode" => "100644", "type" => "blob", "sha" => "176a458f94e0ea5272ce67c36bf30b6be9caf623", "size" => 12, "url" => "https://api.github.com/repos/actions/starter-workflows/git/blobs/176a458f94e0ea5272ce67c36bf30b6be9caf623" },
            { "path" => ".github", "mode" => "040000", "type" => "tree", "sha" => "b183c79a176a31f4458356874279b0c5e7a5ccd0", "url" => "https://api.github.com/repos/actions/starter-workflows/git/trees/b183c79a176a31f4458356874279b0c5e7a5ccd0" },
            { "path" => ".gitignore", "mode" => "100644", "type" => "blob", "sha" => "c5364f299fc99a61017a7277b19e4b43672b6988", "size" => 22, "url" => "https://api.github.com/repos/actions/starter-workflows/git/blobs/c5364f299fc99a61017a7277b19e4b43672b6988" },
            { "path" => ".pre-commit-config.yaml", "mode" => "100644", "type" => "blob", "sha" => "0377bfac7bf1ad0f8813b0140e4349851556d637", "size" => 195, "url" => "https://api.github.com/repos/actions/starter-workflows/git/blobs/0377bfac7bf1ad0f8813b0140e4349851556d637" },
            { "path" => ".vscode", "mode" => "040000", "type" => "tree", "sha" => "5ec5eb914e8cd4e197112db76cc91c09fa9251bd", "url" => "https://api.github.com/repos/actions/starter-workflows/git/trees/5ec5eb914e8cd4e197112db76cc91c09fa9251bd" },
            { "path" => "CODEOWNERS", "mode" => "100644", "type" => "blob", "sha" => "2ed2e33dcfff22dadf369f495abf6e1fc256a27c", "size" => 400, "url" => "https://api.github.com/repos/actions/starter-workflows/git/blobs/2ed2e33dcfff22dadf369f495abf6e1fc256a27c" },
            { "path" => "CONTRIBUTING.md", "mode" => "100644", "type" => "blob", "sha" => "2a0e55fff6da04447fb5099b5eefe733012a2031", "size" => 1548, "url" => "https://api.github.com/repos/actions/starter-workflows/git/blobs/2a0e55fff6da04447fb5099b5eefe733012a2031" },
            { "path" => "LICENSE", "mode" => "100644", "type" => "blob", "sha" => "d4528d7eea310fb9fbb03479fd12b8e3917032a6", "size" => 1154, "url" => "https://api.github.com/repos/actions/starter-workflows/git/blobs/d4528d7eea310fb9fbb03479fd12b8e3917032a6" },
            { "path" => "README.md", "mode" => "100644", "type" => "blob", "sha" => "d8ccca4d0293e318b48314177af0babbe69d4399", "size" => 3860, "url" => "https://api.github.com/repos/actions/starter-workflows/git/blobs/d8ccca4d0293e318b48314177af0babbe69d4399" },
            { "path" => "automation", "mode" => "040000", "type" => "tree", "sha" => "286be6c6789d8c5cdb6479a34b39c22f2dfff9c8", "url" => "https://api.github.com/repos/actions/starter-workflows/git/trees/286be6c6789d8c5cdb6479a34b39c22f2dfff9c8" },
            { "path" => "ci", "mode" => "040000", "type" => "tree", "sha" => "97ba73c79de35407347eb78f659b4638d6f9dbda", "url" => "https://api.github.com/repos/actions/starter-workflows/git/trees/97ba73c79de35407347eb78f659b4638d6f9dbda" },
            { "path" => "code-scanning", "mode" => "040000", "type" => "tree", "sha" => "57b0374dd049e02ef80dd0b172bf9072483724a0", "url" => "https://api.github.com/repos/actions/starter-workflows/git/trees/57b0374dd049e02ef80dd0b172bf9072483724a0" },
            { "path" => "deployments", "mode" => "040000", "type" => "tree", "sha" => "f3cc433d1d8d707ea633577338ec78685aea3132", "url" => "https://api.github.com/repos/actions/starter-workflows/git/trees/f3cc433d1d8d707ea633577338ec78685aea3132" },
            { "path" => "icons", "mode" => "040000", "type" => "tree", "sha" => "ad87b5569f79f97d07e56a0a31d45087be0ec23c", "url" => "https://api.github.com/repos/actions/starter-workflows/git/trees/ad87b5569f79f97d07e56a0a31d45087be0ec23c" },
            { "path" => "pages", "mode" => "040000", "type" => "tree", "sha" => "d44df37b8544a699ce8a4d5d291c4898d57cc73f", "url" => "https://api.github.com/repos/actions/starter-workflows/git/trees/d44df37b8544a699ce8a4d5d291c4898d57cc73f" },
            { "path" => "script", "mode" => "040000", "type" => "tree", "sha" => "3e7a4c18d4d728f60ca49d58ceac73bdef26cc29", "url" => "https://api.github.com/repos/actions/starter-workflows/git/trees/3e7a4c18d4d728f60ca49d58ceac73bdef26cc29" }
          ],
          "truncated" => false
        }))

      branch_client = Actions::Proxima::BranchClient.new(
        connection: @connection,
        token_generator: @token_generator,
      )

      sha = branch_client.sha_for_branch(@nwo, @branch)

      assert_equal expected_sha, sha
    end
  end
end
