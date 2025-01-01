# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class ChecksSerializersTest < Api::SerializerTestCase
  include PlatformTestHelpers::InterfaceHelpers
  include PushTestHelper

  fixtures do
    @owner        = create :paid_user, login: "octocat"
    @org          = create :organization, admin: @owner, login: "github"
    @repo         = create :private_repository, owner: @owner, name: "Hello-World", from_example: :rebase_pull_request
    @github_app   = create :integration, default_permissions: { "checks" => :write },
                      name: "Super-Duper", owner: @org, url: "http://super-duper.com"
    @installation = make_integration_installation integration: @github_app, repository: @repo

    # Use existing git repo `rebase_pull_request`
    # Which lives in test/fixtures/git/examples/rebase_pull_request.git

    @pull = create(:pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: @repo,
      head_user: @repo.owner,
      head_ref: "contrib",
      user: @repo.owner,
    )

    # Make a new commit on contrib branch,
    # so that there is a diff to compare after a Push of that commit
    @before = @repo.heads.find("contrib").target_oid
    metadata = { message: "blah", committer: @owner }
    commit = @repo.heads.find("contrib").append_commit(metadata, @owner) do |files|
      files.add("foo", "dsfdsfsdfsd")
    end
    @sha = commit.oid

    # Create a Push for the fresh commit(s) on the feature branch.
    perform_enqueued_jobs(only: [CreateCheckSuitesJob]) do
      trigger_push_event(
        @repo.shard_path,
        @owner.login,
        [["refs/heads/contrib", @before, @sha]],
        Time.now,
        perform_hydro_push_jobs: [HydroRepositoriesOnPushJob]
      )
      @push = push_accessor.freeze.by_repo_id_and_after(repository_id: @repo.id, after: @sha).freeze
    end
    @check_suite  = CheckSuite.where(push_id: @push.id).last
    @check_run    = create :check_run, check_suite: @check_suite, creator: @owner, status: "queued"
    output_attrs = { name: "coverage",
                     title: "Report",
                     summary: "All good.",
                     text: "Lots more info about Report \n\n and more data.",
                     images: [{
                        alt: "80% coverage",
                        image_url: "http://example.com/graph.png",
                        caption: "The coverage decreased by 1%, and is now at 80%." },
                      ],
                    }
    @check_run.update(output_attrs)
    @check_run.annotations.create({
      filename: "README.md",
      annotation_level: "warning",
      message: "This might be a problem, because reasons.",
      start_line: "122",
      end_line: "123",
      repository: @check_run.repository,
    })

    # Create a second pull request that matches @push
    @repo.heads.create("base",  @repo.heads.find("master").commit, @repo.owner)
    create(:pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "base",
      head_repository: @repo,
      head_user: @repo.owner,
      head_ref: "contrib",
      user: @repo.owner,
    )
  end

  context "check_run_hash" do
    test "returns expected data" do
      output = serialize_hash_method("check_run_hash", @check_run, repo: @repo)

      assert_equal "queued", output["status"]
    end

    test "returns the visible_name as the name" do
      check_run_with_display_name = create :check_run, check_suite: @check_suite, creator: @owner, status: "queued", name: "xxx", display_name: "CI"
      output = serialize_hash_method("check_run_hash", check_run_with_display_name, repo: @repo)

      assert_equal "CI", output["name"]
    end

    test "output is present but empty when CheckRun has no output attributes" do
      another_check_run = create :check_run, check_suite: @check_suite, creator: @owner, status: "in_progress"
      output = serialize_hash_method("check_run_hash", another_check_run, repo: @repo)

      assert output["output"]
      assert_nil output["output"]["title"]
    end

    test "output is present when CheckRun has output attributes" do
      output = serialize_hash_method("check_run_hash", @check_run, repo: @repo)

      assert_equal "Report", output["output"]["title"]
      assert_equal "All good.", output["output"]["summary"]
      assert_equal "Lots more info about Report \n\n and more data.", output["output"]["text"]
      assert_equal 1, output["output"]["annotations_count"]
      assert_match /repos\/#{@repo.owner}\/#{@repo}\/check-runs\/#{@check_run.id}\/annotations/, output["output"]["annotations_url"]
    end

    test "includes all matching pull requests" do
      output = serialize_hash_method("check_run_hash", @check_run, repo: @repo)

      assert_equal 2, output["pull_requests"].count
    end
  end

  context "simple_check_suite_hash" do
    test "push is optional" do
      attrs = {
        repository_id: @repo.id,
        github_app_id: @github_app.id,
        creator_id: @owner.id,
        head_branch: "master",
        head_sha: "0" * 40,
        status: "requested",
      }
      suite = CheckSuite.create(attrs)
      output = serialize_hash_method("simple_check_suite_hash", suite, {})
      assert_nil output["before"]
      assert_nil output["after"]
      assert_nil output["push"]
    end
  end

  context "check_suite_hash" do
    test "includes head commit" do
      commit = @repo.heads.find("master").commit
      attrs = {
        repository_id: @repo.id,
        github_app_id: @github_app.id,
        creator_id: @owner.id,
        head_branch: "master",
        head_sha: commit.oid,
        status: "requested",
      }
      suite = CheckSuite.create(attrs)
      output = serialize_hash_method("check_suite_hash", suite, {})
      assert_equal commit.message, output["head_commit"]["message"]
    end

    test "includes an array of pull request hashes" do
      output = serialize_hash_method("check_suite_hash", @check_suite, {})
      assert_equal 2, output["pull_requests"].count
    end
  end

  context "check_annotation_hash" do
    test "returns expected data" do
      output = serialize_hash_method("check_annotation_hash", @check_run.annotations.first, {})

      assert_equal "README.md", output["path"]
      assert_equal "#{GitHub.url}/#{@repo.nwo}/blob/#{@sha}/README.md", output["blob_href"]
      assert_equal "warning", output["annotation_level"]
      assert_equal "This might be a problem, because reasons.", output["message"]
      assert_equal 122, output["start_line"]
      assert_equal 123, output["end_line"]
    end
  end

  context "#check_suite_preferences_hash" do
    test "returns expected data" do
      output = serialize_hash_method("check_suite_preferences_hash", @repo, {})

      assert_equal @repo.id, output["repository"]["id"]
      auto_trigger_output = output["preferences"]["auto_trigger_checks"]
      assert_equal @github_app.id, auto_trigger_output[0]["app_id"]
      assert_equal true, auto_trigger_output[0]["setting"]
    end

    test "returns one preference per IntegrationInstallation" do
      repo_a = create :private_repository, owner: @org, name: "Repo A"
      repo_b = create :private_repository, owner: @org, name: "Repo B"
      installation = make_integration_installation(target: @org, repositories: [repo_a, repo_b], permissions: { "checks" => :write })

      output = serialize_hash_method("check_suite_preferences_hash", repo_a, {})

      assert_equal 1, output["preferences"]["auto_trigger_checks"].count
    end
  end

  context "#check_runs_hash" do
    test "payload is valid" do
      3.times do
        create(:check_run, check_suite: @check_suite, creator: @owner, status: "queued")
      end
      runs = CheckRun.annotate("cross-shard-query-exempted").last(3)
      app = Api::App.new!

      runs = app.paginate_rel(runs, { per_page: 100, page: 1 })

      output = serialize_hash_method("check_runs_hash", { check_runs: runs, total_count: runs.total_entries }, repo: @repo)

    end
  end

  context "#check_suites_hash" do
    test "payload is valid" do
      suites = CheckSuite.where(head_sha: @sha, repository_id: @repo.id)
      app = Api::App.new!

      suites = app.paginate_rel(suites, { per_page: 100, page: 1 })
      output = serialize_hash_method("check_suites_hash", { check_suites: suites, total_count: suites.total_entries }, {})

    end
  end
end
