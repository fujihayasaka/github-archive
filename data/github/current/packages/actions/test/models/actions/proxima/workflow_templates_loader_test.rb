# typed: true
# frozen_string_literal: true

require "test_helper"

class Actions::Proxima::WorkflowTemplatesLoaderTest < GitHub::TestCase
  STARTER_WORKFLOWS_FOLDERS = %w[automation ci code-scanning deployments icons pages]

  include DogstatsTestHelpers

  setup do
    @repo_nwo = "actions/starter-workflows"
    @repo_owner, @repo_name = @repo_nwo.split("/")
    GitHub.stubs(:actions_starter_workflows_nwo).returns(@repo_nwo)

    @token = "bearer token"
    @branch = "main"
    @sha = "be552580a63fc68faa5036cf1ae2646d3ee1bb37"
    @workflow_folders = %w[automation automation/properties ci ci/properties code-scanning code-scanning/properties deployments deployments/properties icons pages pages/properties]

    @connection = GitHub::FaradayClient::Internal.new(url: "http://example.invalid")
    @token_generator = stub(generate_token: @token)
    @workflow_templates_client = Actions::Proxima::WorkflowTemplatesClient.new(
      repo_owner: @repo_owner,
      repo_name: @repo_name,
      connection: @connection,
      token_generator: @token_generator,
    )
    @branch_client = Actions::Proxima::BranchClient.new(
      connection: @connection,
      token_generator: @token_generator,
    )

    @workflow_templates_loader = Actions::Proxima::WorkflowTemplatesLoader.new(
      @repo_nwo,
      STARTER_WORKFLOWS_FOLDERS,
      "default",
      @branch,
      token_generator: @token_generator,
      branch_client: @branch_client,
      workflow_templates_client: @workflow_templates_client,
    )
  end

  context "#all" do
    test "returns an empty array when fetching the branch sha fails" do
      @branch_client.expects(:sha_for_branch).with(@repo_nwo, @branch).raises(Actions::Proxima::WorkflowTemplatesError.new("request failed", url: "", status: 401))

      templates = @workflow_templates_loader.all

      assert_equal [], templates
      assert_dogstats_increment(1, "actions.proxima.workflow.templates.all.error")
    end

    test "returns an empty array when no sha is found" do
      @branch_client.expects(:sha_for_branch).with(@repo_nwo, @branch).returns(nil)

      templates = @workflow_templates_loader.all

      assert_equal [], templates
    end

    test "returns an empty array when fetching the starter workflow folders fails" do
      @branch_client.expects(:sha_for_branch).with(@repo_nwo, @branch).returns(@sha)
      @workflow_templates_client.expects(:fetch_templates).with(@sha, @workflow_folders).raises(Actions::Proxima::WorkflowTemplatesError.new("request failed", url: "", status: 401))

      templates = @workflow_templates_loader.all

      assert_equal [], templates
      assert_dogstats_increment(1, "actions.proxima.workflow.templates.all.error")
    end

    test "returns an empty array when fetching the starter workflow returns nil" do
      @branch_client.expects(:sha_for_branch).with(@repo_nwo, @branch).returns(@sha)
      @workflow_templates_client.expects(:fetch_templates).with(@sha, @workflow_folders).returns(nil)

      templates = @workflow_templates_loader.all

      assert_equal [], templates
    end

    test "returns only workflow templates which aren't truncated" do
      workflow_templates_client_response = {
        "automation" => { "files" => [
          {
            "path" => "automation/greetings.yml",
            "object" => {
              "text" => "name: Greetings\n\non: [pull_request_target, issues]\n\njobs:\n  greeting:\n    runs-on: ubuntu-latest\n    permissions:\n      issues: write\n      pull-requests: write\n    steps:\n    - uses: actions/first-interaction@v1\n      with:\n        repo-token: ${{ secrets.GITHUB_TOKEN }}\n        issue-message: \"Message that will be displayed on users' first issue\"\n        pr-message: \"Message that will be displayed on users' first pull request\"\n",
              "isTruncated" => false
            }
          },
          {
            "path" => "automation/label.yml",
            "object" => {
              "text" => "# This workflow will triage pull requests and apply a label based on the\n# paths that are modified in the pull request.\n#\n# To use this workflow, you will need to set up a .github/labeler.yml\n# file with configuration.  For more information, see:\n# https://github.com/actions/labeler\n\nname: Labeler\non: [pull_request_target]\n\njobs:\n  label:\n\n    runs-on: ubuntu-latest\n    permissions:\n      contents: read\n      pull-requests: write\n\n    steps:\n    - uses: actions/labeler@v4\n      with:\n        repo-token: \"${{ secrets.GITHUB_TOKEN }}\"\n",
              "isTruncated" => false
            }
          },
          { "path" => "automation/manual.yml",
            "object" => {
              "text" => "# This is a basic workflow that is manually triggered\n\nname: Manual workflow\n\n# Controls when the action will run. Workflow runs when manually triggered using the UI\n# or API.\non:\n  workflow_dispatch:\n    # Inputs the workflow accepts.\n    inputs:\n      name:\n        # Friendly description to be shown in the UI instead of 'name'\n        description: 'Person to greet'\n        # Default value if no value is explicitly provided\n        default: 'World'\n        # Input has to be provided for the workflow to run\n",
              "isTruncated" => true
            }
          },
          {
            "path" => "automation/properties", "object" => {} },
          {
            "path" => "automation/stale.yml",
            "object" => {
              "text" => "# This workflow warns and then closes issues and PRs that have had no activity for a specified amount of time.\n#\n# You can adjust the behavior by modifying this file.\n# For more information, see:\n# https://github.com/actions/stale\nname: Mark stale issues and pull requests\n\non:\n  schedule:\n  - cron: $cron-daily\n\njobs:\n  stale:\n\n    runs-on: ubuntu-latest\n    permissions:\n      issues: write\n      pull-requests: write\n\n    steps:\n    - uses: actions/stale@v5\n      with:\n        repo-token: ${{ secrets.GITHUB_TOKEN }}\n stale-issue-message: 'Stale issue message'\n        stale-pr-message: 'Stale pull request message'\n        stale-issue-label: 'no-issue-activity'\n        stale-pr-label: 'no-pr-activity'\n",
              "isTruncated" => false
            }
          }
        ] },

        "automationproperties" => { "files" => [
          {
            "path" => "automation/properties/greetings.properties.json",
            "object" => {
              "text" => "{\n    \"name\": \"Greetings\",\n    \"description\": \"Greets users who are first time contributors to the repo\",\n    \"iconName\": \"octicon smiley\",\n    \"categories\": [\"Automation\", \"SDLC\"]\n}\n",
              "isTruncated" => false
            }
          },
          {
            "path" => "automation/properties/label.properties.json",
            "object" => {
              "text" => "{\n    \"name\": \"Labeler\",\n    \"description\": \"Labels pull requests based on the files changed\",\n    \"iconName\": \"octicon tag\",\n    \"categories\": [\"Automation\", \"SDLC\"]\n}\n",
              "isTruncated" => true
            }
          },
          {
            "path" => "automation/properties/manual.properties.json",
            "object" => {
              "text" => "{\n    \"name\": \"Manual workflow\",\n    \"description\": \"Simple workflow that is manually triggered.\",\n    \"iconName\": \"octicon person\",\n    \"categories\": [\"Automation\"]\n}\n",
              "isTruncated" => false
            }
          },
          {
            "path" => "automation/properties/stale.properties.json",
            "object" => {
              "text" => "{\n    \"name\": \"Stale\",\n    \"description\": \"Checks for stale issues and pull requests\",\n    \"iconName\": \"octicon clock\",\n    \"categories\": [\"Automation\", \"SDLC\"]\n}\n",
              "isTruncated" => false
              }
            }
        ] }
      }

      @branch_client.expects(:sha_for_branch).with(@repo_nwo, @branch).returns(@sha)
      @workflow_templates_client.expects(:fetch_templates).with(@sha, @workflow_folders).returns(workflow_templates_client_response)

      templates = @workflow_templates_loader.all
      assert_equal 2, templates.count

      assert_nil templates.find { |t| t["id"] == "automation/manual.yml" }, "truncated workflow file should be filtered out"
      assert_nil templates.find { |t| t["id"] == "automation/label.yml" }, "workflow file with truncated properties should be filtered out"
    end

    test "fetches workflow templates from dotcom" do
      workflow_templates_loader = Actions::Proxima::WorkflowTemplatesLoader.new(
        @repo_nwo,
        STARTER_WORKFLOWS_FOLDERS,
        "default",
        "main",
        token_generator: @token_generator,
      )

      VCR.use_cassette("actions/workflow-templates-loader-test") do
        workflow_templates = workflow_templates_loader.all

        assert_dogstats_gauge_value(1384, "actions.proxima.workflow.templates.cache.cache_size")

        assert_equal 168, workflow_templates.count

        assert_equal({
          "id" => "automation/greetings",
          "data" => "bmFtZTogR3JlZXRpbmdzCgpvbjogW3B1bGxfcmVxdWVzdF90YXJnZXQsIGlzc3Vlc10KCmpvYnM6CiAgZ3JlZXRpbmc6CiAgICBydW5zLW9uOiB1YnVudHUtbGF0ZXN0CiAgICBwZXJtaXNzaW9uczoKICAgICAgaXNzdWVzOiB3cml0ZQogICAgICBwdWxsLXJlcXVlc3RzOiB3cml0ZQogICAgc3RlcHM6CiAgICAtIHVzZXM6IGFjdGlvbnMvZmlyc3QtaW50ZXJhY3Rpb25AdjEKICAgICAgd2l0aDoKICAgICAgICByZXBvLXRva2VuOiAke3sgc2VjcmV0cy5HSVRIVUJfVE9LRU4gfX0KICAgICAgICBpc3N1ZS1tZXNzYWdlOiAiTWVzc2FnZSB0aGF0IHdpbGwgYmUgZGlzcGxheWVkIG9uIHVzZXJzJyBmaXJzdCBpc3N1ZSIKICAgICAgICBwci1tZXNzYWdlOiAiTWVzc2FnZSB0aGF0IHdpbGwgYmUgZGlzcGxheWVkIG9uIHVzZXJzJyBmaXJzdCBwdWxsIHJlcXVlc3QiCg==",
          "name" => "Greetings",
          "categories" => %w[Automation SDLC],
          "labels" => [],
          "creator" => nil,
          "description" => "Greets users who are first time contributors to the repo",
          "filePatterns" => nil,
          "iconName" => "octicon smiley",
          "iconRawUrl" => nil,
          "templateUrl" => "https://github.com/actions/starter-workflows/blob/be552580a63fc68faa5036cf1ae2646d3ee1bb37/automation/greetings.yml",
          "sourceRepository" => "actions/starter-workflows",
          "source" => "default"
          }, workflow_templates.first)
      end
    end

    test "caches workflow templates in memcached" do
      sha = "be552580a63fc68faa5036cf1ae2646d3ee1bb37"
      expected_templates = 168

      workflow_templates_loader = Actions::Proxima::WorkflowTemplatesLoader.new(
        @repo_nwo,
        STARTER_WORKFLOWS_FOLDERS,
        "default",
        "main",
        token_generator: @token_generator,
        branch_client: @branch_client
      )
      @branch_client.expects(:sha_for_branch).returns(sha)

      VCR.use_cassette("actions/workflow-templates-loader-test") do
        with_cache_enabled do
          workflow_templates = workflow_templates_loader.all
          assert_equal expected_templates, workflow_templates.count

          folders_hash = Digest::SHA256.hexdigest(@workflow_folders.join("-"))
          cache_key = "actions:workflow_templates:#{Actions::Proxima::WorkflowTemplatesLoader::CACHE_VERSION}:#{sha}:#{folders_hash}"

          assert GitHub.cache.exist?(cache_key)

          cached_result = GitHub.cache.get(cache_key)
          assert_equal 168, cached_result.count

          assert_equal({
            "id" => "automation/greetings",
            "data" => "bmFtZTogR3JlZXRpbmdzCgpvbjogW3B1bGxfcmVxdWVzdF90YXJnZXQsIGlzc3Vlc10KCmpvYnM6CiAgZ3JlZXRpbmc6CiAgICBydW5zLW9uOiB1YnVudHUtbGF0ZXN0CiAgICBwZXJtaXNzaW9uczoKICAgICAgaXNzdWVzOiB3cml0ZQogICAgICBwdWxsLXJlcXVlc3RzOiB3cml0ZQogICAgc3RlcHM6CiAgICAtIHVzZXM6IGFjdGlvbnMvZmlyc3QtaW50ZXJhY3Rpb25AdjEKICAgICAgd2l0aDoKICAgICAgICByZXBvLXRva2VuOiAke3sgc2VjcmV0cy5HSVRIVUJfVE9LRU4gfX0KICAgICAgICBpc3N1ZS1tZXNzYWdlOiAiTWVzc2FnZSB0aGF0IHdpbGwgYmUgZGlzcGxheWVkIG9uIHVzZXJzJyBmaXJzdCBpc3N1ZSIKICAgICAgICBwci1tZXNzYWdlOiAiTWVzc2FnZSB0aGF0IHdpbGwgYmUgZGlzcGxheWVkIG9uIHVzZXJzJyBmaXJzdCBwdWxsIHJlcXVlc3QiCg==",
            "name" => "Greetings",
            "categories" => %w[Automation SDLC],
            "labels" => [],
            "creator" => nil,
            "description" => "Greets users who are first time contributors to the repo",
            "filePatterns" => nil,
            "iconName" => "octicon smiley",
            "iconRawUrl" => nil,
            "templateUrl" => "https://github.com/actions/starter-workflows/blob/be552580a63fc68faa5036cf1ae2646d3ee1bb37/automation/greetings.yml",
            "sourceRepository" => "actions/starter-workflows",
            "source" => "default"
            }, cached_result.first)
        end
      end
    end

    test "returns cached value without calling dotcom" do
      sha = "be552580a63fc68faa5036cf1ae2646d3ee1bb37"
      workflow_templates_client = @workflow_templates_client

      cached_results = [{
        "id" => "automation/greetings",
        "data" => "bmFtZTogR3JlZXRpbmdzCgpvbjogW3B1bGxfcmVxdWVzdF90YXJnZXQsIGlzc3Vlc10KCmpvYnM6CiAgZ3JlZXRpbmc6CiAgICBydW5zLW9uOiB1YnVudHUtbGF0ZXN0CiAgICBwZXJtaXNzaW9uczoKICAgICAgaXNzdWVzOiB3cml0ZQogICAgICBwdWxsLXJlcXVlc3RzOiB3cml0ZQogICAgc3RlcHM6CiAgICAtIHVzZXM6IGFjdGlvbnMvZmlyc3QtaW50ZXJhY3Rpb25AdjEKICAgICAgd2l0aDoKICAgICAgICByZXBvLXRva2VuOiAke3sgc2VjcmV0cy5HSVRIVUJfVE9LRU4gfX0KICAgICAgICBpc3N1ZS1tZXNzYWdlOiAiTWVzc2FnZSB0aGF0IHdpbGwgYmUgZGlzcGxheWVkIG9uIHVzZXJzJyBmaXJzdCBpc3N1ZSIKICAgICAgICBwci1tZXNzYWdlOiAiTWVzc2FnZSB0aGF0IHdpbGwgYmUgZGlzcGxheWVkIG9uIHVzZXJzJyBmaXJzdCBwdWxsIHJlcXVlc3QiCg==",
        "name" => "Greetings",
        "categories" => %w[Automation SDLC],
        "labels" => [],
        "creator" => nil,
        "description" => "Greets users who are first time contributors to the repo",
        "filePatterns" => nil,
        "iconName" => "octicon smiley",
        "iconRawUrl" => nil,
        "templateUrl" => "https://github.com/actions/starter-workflows/blob/be552580a63fc68faa5036cf1ae2646d3ee1bb37/automation/greetings.yml",
        "sourceRepository" => "actions/starter-workflows",
        "source" => "default"
      }]

      workflow_templates_loader = Actions::Proxima::WorkflowTemplatesLoader.new(
        @repo_nwo,
        STARTER_WORKFLOWS_FOLDERS,
        "default",
        "main",
        token_generator: @token_generator,
        branch_client: @branch_client,
        workflow_templates_client: workflow_templates_client,
      )
      @branch_client.expects(:sha_for_branch).returns(sha)

      with_cache_enabled do
        workflow_templates_client.expects(:fetch_templates).never

        folders_hash = Digest::SHA256.hexdigest(@workflow_folders.join("-"))
        cache_key = "actions:workflow_templates:#{Actions::Proxima::WorkflowTemplatesLoader::CACHE_VERSION}:#{sha}:#{folders_hash}"

        GitHub.cache.set(cache_key, cached_results)
        assert GitHub.cache.exist?(cache_key)

        workflow_templates = workflow_templates_loader.all
        assert_equal cached_results, workflow_templates

        assert_dogstats_gauge_value(ObjectSpace.memsize_of(cached_results), "actions.proxima.workflow.templates.cache.cache_size")
      end
    end

    test "checks for updated sha only once per hour" do
      sha = "be552580a63fc68faa5036cf1ae2646d3ee1bb37"

      # Need to use different loaders so memoization doesn't interfere with the test
      workflow_template_loaders = 4.times.map do
        Actions::Proxima::WorkflowTemplatesLoader.new(
          @repo_nwo,
          STARTER_WORKFLOWS_FOLDERS,
          "default",
          "main",
          token_generator: @token_generator,
          branch_client: @branch_client,
          workflow_templates_client: @workflow_templates_client,
        )
      end
      Actions::Proxima::WorkflowTemplatesLoader.any_instance.stubs(:cached_fetch_templates).returns([])

      @branch_client.expects(:sha_for_branch).once.returns(sha)

      Timecop.freeze do
        T.must(workflow_template_loaders[0]).all
        T.must(workflow_template_loaders[1]).all
        T.must(workflow_template_loaders[2]).all
        T.must(workflow_template_loaders[3]).all
      end

      assert_dogstats_increment(1, "actions.proxima.workflow.templates.sha_retrieved_from_dotcom")
      assert_dogstats_increment(3, "actions.proxima.workflow.templates.sha_retrieved_from_kv")
    end

    test "checks for updated sha after an hour" do
      sha = "be552580a63fc68faa5036cf1ae2646d3ee1bb37"

      # Need to use different loaders so memoization doesn't interfere with the test
      workflow_template_loaders = 4.times.map do
        Actions::Proxima::WorkflowTemplatesLoader.new(
          @repo_nwo,
          STARTER_WORKFLOWS_FOLDERS,
          "default",
          "main",
          token_generator: @token_generator,
          branch_client: @branch_client,
          workflow_templates_client: @workflow_templates_client,
        )
      end
      Actions::Proxima::WorkflowTemplatesLoader.any_instance.stubs(:cached_fetch_templates).returns([])

      @branch_client.expects(:sha_for_branch).twice.returns(sha)

      time = Time.now
      Timecop.travel(time) do
        T.must(workflow_template_loaders[0]).all
        T.must(workflow_template_loaders[1]).all
      end
      Timecop.travel(time + 65.minutes) do
        T.must(workflow_template_loaders[2]).all
        T.must(workflow_template_loaders[3]).all
      end

      assert_dogstats_increment(2, "actions.proxima.workflow.templates.sha_retrieved_from_dotcom")
      assert_dogstats_increment(2, "actions.proxima.workflow.templates.sha_retrieved_from_kv")
    end
  end
end
