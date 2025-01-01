# typed: true
# frozen_string_literal: true

require "test_helper"

class ActionsWorkflowTemplatesLoaderTest < GitHub::TestCase
  include FeatureFlagHelper
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @owner = create :user, login: "monalisa"
    @repo = create :repository, name: "starter-workflows", owner: @owner, from_example: :simple

    @empty_repo = create :repository, name: "empty", owner: @owner

    @commit_metadata = { committer: @repo.owner, message: "Updating a file" }

    @greetingsYaml = <<~YAML
      on:
        push:
          branches:
            - $default-branch
        jobs:
          build:
            runs-on: ubuntu-latest
            steps:
              - uses: actions/checkout@main
                env:
                  REGISTRY: $registry-url(npm)
    YAML

    @master = @repo.heads.find_or_build("master")
    @svg_content = <<~SVG
    <svg version="1.1" baseProfile="full" width="300" height="200" xmlns="http://www.w3.org/2000/svg">
      <rect width="100%" height="100%" fill="red" />
    </svg>
    SVG
    commit = @master.append_commit(@commit_metadata, @repo.owner) do |files|
      files.add("automation/greetings.yml", @greetingsYaml)
      files.add("automation/properties/greetings.properties.json", <<~JSON
        {
          "name": "Greetings",
          "creator": "Bob the builder",
          "description": "the-description",
          "filePatterns": ["^package.json$"],
          "iconName": "the-icon-name",
          "categories": ["Automation", "SDLC"]
        }
        JSON
      )
      files.add("ci/blank.yml", @greetingsYaml)
      files.add("ci/properties/blank.properties.json", <<~JSON
        {
          "name": "Simple workflow",
          "description": "test-description",
          "iconName": "test-icon-name",
          "categories": ["Test"]
        }
        JSON
      )
      files.add("ci/bad-yaml-extension.xyml", @greetingsYaml)
      files.add("ci/properties/bad-yaml-extension.properties.json", <<~JSON
        {
          "name": "Simple workflow",
          "description": "test-description",
          "iconName": "test-icon-name",
          "categories": ["Test"]
        }
        JSON
      )
      files.add("icons/the-icon-name.svg", @svg_content)
      files.add("icons/bad-svg-extension.xsvg", @svg_content)
      files.add("code-scanning/placeholder.txt", @svg_content)
    end
  end

  setup do
    GitHub.cache.allow = /actions:workflow_templates:.*/
    GitHub.cache.clear
  end

  def loader
    Actions::WorkflowTemplatesLoader.new(@repo.nwo, Actions::WorkflowTemplates::STARTER_WORKFLOWS_FOLDERS)
  end

  context "#all" do
    test "loads expected data from the repository" do
      res = loader.all
      assert_equal 2, res.length
      assert_equal "automation/greetings", res.first["id"]
    end

    test "memoizes the data even if it is nil" do
      t = loader
      t.expects(:cached_load_from_repo).once.returns(nil)
      t.all
      t.all # Second call should be memoized
    end

    test "cache include the folders key" do
      loader1 = Actions::WorkflowTemplatesLoader.new(@repo.nwo, ["ci"])
      content = loader1.all
      assert content.length == 1
      assert_equal "Simple workflow", content[0]["name"]

      # try to load the automation folder, it should not return the result from ci folder.
      loader2 = Actions::WorkflowTemplatesLoader.new(@repo.nwo, ["automation"])
      content = loader2.all
      assert content.length == 1
      assert_equal "Greetings", content[0]["name"]
    end
  end

  context "#cached_load_from_repo (private)" do
    test "returns an empty arry if the repository does not exist" do
      t = Actions::WorkflowTemplatesLoader.new("missing/repo", Actions::WorkflowTemplates::STARTER_WORKFLOWS_FOLDERS)
      assert_equal [], t.send(:cached_load_from_repo)
    end

    test "returns an empty array if the repository is empty" do
      t = Actions::WorkflowTemplatesLoader.new(@empty_repo.nwo, Actions::WorkflowTemplates::STARTER_WORKFLOWS_FOLDERS)
      assert_equal [], t.send(:cached_load_from_repo)
    end

    test "caches the load" do
      Actions::WorkflowTemplatesLoader.any_instance.expects(:load_from_repo).once.returns("the-result")

      t = loader # This will call cached_load_from_repo itself
      t.send(:cached_load_from_repo) # Second direct call should hit cache
    end
  end

  context "#load_from_repo (private)" do
    test "loads data from the configured repository" do
      res = loader.send(:load_from_repo, @repo, @repo.root_directory.commit_sha, Actions::WorkflowTemplates::STARTER_WORKFLOWS_FOLDERS)
      # This also verifies that the .xyml and .xsvg files were not loaded
      assert_equal 2, res.length

      greeting = res.first

      assert_equal "automation/greetings", greeting["id"]
      assert_equal Base64.encode64(@greetingsYaml).gsub("\n", ""), greeting["data"]
      assert_equal "Greetings", greeting["name"]
      assert_equal %w[Automation SDLC], greeting["categories"]
      assert_equal "Bob the builder", greeting["creator"]
      assert_equal "the-description", greeting["description"]
      assert_equal ["^package.json$"], greeting["filePatterns"]
      assert_equal "the-icon-name", greeting["iconName"]
      assert_equal "data:image/svg+xml;base64,#{Base64.encode64(@svg_content).gsub("\n", "")}", greeting["iconRawUrl"]
      assert_equal "https://github.com/#{@repo.nwo}/blob/#{@repo.root_directory.commit_sha}/automation/greetings.yml", greeting["templateUrl"]
      assert_equal @repo.nwo, greeting["sourceRepository"]
    end

    test "handles expected folders not existing, returning nil" do
      loader = Actions::WorkflowTemplatesLoader.new(@repo.nwo, ["non-existent"], "owner")
      res = loader.send(:load_from_repo, @repo, @repo.root_directory.commit_sha, ["non-existent"])
      assert_equal [], res
    end

    test "handles one of expected folders not existing, still returning the other results" do
      loader = Actions::WorkflowTemplatesLoader.new(@repo.nwo, Actions::WorkflowTemplates::STARTER_WORKFLOWS_FOLDERS + ["non-existent"], "owner")
      res = loader.send(:load_from_repo, @repo, @repo.root_directory.commit_sha,  Actions::WorkflowTemplates::STARTER_WORKFLOWS_FOLDERS + ["non-existent"])
      assert_equal 2, res.length
    end

    test "handles missing yml by dropping the data" do
      branch = @repo.heads.find_or_build("no-yml")
      branch.update(@master.target_oid, @repo.owner)
      commit = branch.append_commit({ message: "removing blank.yml", committer: @repo.owner }, @repo.owner) do |files|
        files.remove("ci/blank.yml")
      end

      loader = Actions::WorkflowTemplatesLoader.new(@repo.nwo, [""], "owner")
      res = loader.send(:load_from_repo, @repo, branch.sha, [""])

      assert_equal 1, res.length
      refute_equal "ci", res.first["id"]
    end

    test "handles missing json properties by dropping the data" do
      branch = @repo.heads.find_or_build("no-json")
      branch.update(@master.target_oid, @repo.owner)
      commit = branch.append_commit({ message: "removing blank.properties.json", committer: @repo.owner }, @repo.owner) do |files|
        files.remove("ci/properties/blank.properties.json")
      end

      loader = Actions::WorkflowTemplatesLoader.new(@repo.nwo, [""], "owner")
      res = loader.send(:load_from_repo, @repo, branch.sha, [""])

      assert_equal 1, res.length
      refute_equal "ci", res.first["id"]
    end

    test "handles invalid json" do
      branch = @repo.heads.find_or_build("bad-json")
      branch.update(@master.target_oid, @repo.owner)
      commit = branch.append_commit({ message: "adding bad json", committer: @repo.owner }, @repo.owner) do |files|
        files.add("ci/properties/blank.properties.json", "{\"hanging\":\"comma\",}")
      end

      loader = Actions::WorkflowTemplatesLoader.new(@repo.nwo, [""], "owner")
      res = loader.send(:load_from_repo, @repo, branch.sha, [""])

      assert_equal 1, res.length
      refute_equal "ci", res.first["id"]
    end

    test "handles one of expected folders being a blob, still returning the other results" do
      loader = Actions::WorkflowTemplatesLoader.new(@repo.nwo, Actions::WorkflowTemplates::STARTER_WORKFLOWS_FOLDERS + ["empty_file"], "owner")
      res = loader.send(:load_from_repo, @repo, @repo.root_directory.commit_sha, Actions::WorkflowTemplates::STARTER_WORKFLOWS_FOLDERS + ["empty_file"])
      assert_equal 2, res.length
    end
  end
end
