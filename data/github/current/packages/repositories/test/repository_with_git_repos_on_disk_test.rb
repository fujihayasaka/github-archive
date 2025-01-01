# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

class RepositoryWithGitReposOnDiskTest < GitHub::TestCase
  include GitHub::DatabaseQueryWarningsTestHelpers
  include HydroMessageJobTestHelpers

  fixtures do
    @mojombo  = create(:user, login: "mojombo2", plan: "medium")
    @defunkt  = create(:user, login: "defunkt",  plan: "medium")
    @rtomayko = create(:user, login: "rtomayko")
    @facebox  = create(:repository, name: "facebox",  owner: @defunkt, from_example: :defunkt_facebox)
    @grit     = create(:repository, name: "grit",     owner: @mojombo, from_example: :mojombo_grit)
    @simple   = create(:repository, name: "simple",   owner: @rtomayko, from_example: :simple)
    @emojis   = create(:repository, name: "emojis",  owner: @defunkt, from_example: :emojis)
    example_repo_snapshot
  end

  setup do
    example_repo_restore
    @facebox.update_default_branch("master")
    @grit.update_default_branch("master")
  end

  test "can update HEAD (default branch)" do
    assert @facebox.update_default_branch("semis")
    assert_equal "semis", @facebox.default_branch
  end

  test "updating the default branch with the existing value does not make a db call" do
    # We read after updating the branch so we don't count looking up the current
    # checksum/cache key in the assert_no_queries block
    @facebox.update_default_branch("semis")
    @facebox.default_branch

    assert_no_queries do
      refute @facebox.update_default_branch("semis")
    end
    assert_equal "semis", @facebox.default_branch
  end

  if GitHub.use_elastomer_code_search?
    test "updating the default branch enqueues commit and legacy code search index updates" do
      now = Time.now
      timestamp = Timestamp.from_time(now)
      code_guid = AddToSearchIndexJob.guid("code", @facebox.id, "purge" => true)
      commit_guid = AddToSearchIndexJob.guid("commit", @facebox.id, "purge" => true)

      Timecop.freeze(now) do
        assert_enqueued_with(job: AddToSearchIndexJob, args: ["code", @facebox.id, { "submitted_at" => timestamp, "purge" => true, "guid" => code_guid }], queue: "index_low") do
          @facebox.update_default_branch("semis")
        end
      end
    end
  else
    test "updating the default branch enqueues commit but not legacy code search index updates" do
      now = Time.now
      timestamp = Timestamp.from_time(now)
      commit_guid = AddToSearchIndexJob.guid("commit", @facebox.id, "purge" => true)

      Timecop.freeze(now) do
        assert_enqueued_with(job: AddToSearchIndexJob, args: ["commit", @facebox.id, { "purge" => true, "submitted_at" => timestamp, "guid" => commit_guid }], queue: "index_low") do
          code_job_matcher = ->(job_args) do
            job_args[:job] == AddToSearchIndexJob &&
              job_args[:args][0] == "code" &&
              job_args[:args][1] == @facebox.id
          end
          assert_no_enqueued_jobs(only: code_job_matcher) do
            @facebox.update_default_branch("semis")
          end
        end
      end
    end
  end

  test "updating the default branch queues a job to rebuild commit contributions" do
    assert_enqueued_with(job: ContributionsBackfillJob, args: [@facebox.id, true]) do
      @facebox.update_default_branch("semis")
    end
  end

  test "updating the default branch queues a job to reinitialize manifest files" do
    reset_job_hash_locks(job: RepositoryDependencyManifestInitializationJob)
    assert_enqueued_with(job: RepositoryDependencyManifestInitializationJob, args: [@facebox.id]) do
      @facebox.update_default_branch("semis")
    end
  end

  test "updating the default branch to the same name does not queue a job to rebuild commit contributions" do
    assert_no_enqueued_jobs do
      @facebox.update_default_branch("master")
    end
  end

  test "can't update HEAD (default branch) to a non-existent branch" do
    refute @simple.update_default_branch("foo")
    assert_equal "master", @simple.default_branch
  end

  test "trying to update the default branch to a non-existent branch queues no jobs" do
    assert_no_enqueued_jobs do
      @simple.update_default_branch("foo")
    end
  end

  test "checking existence of default branch" do
    assert_predicate @simple, :default_branch_exists?

    @simple.default_branch_ref.delete(@simple.owner)
    refute_predicate @simple, :default_branch_exists?
  end

  test "should be able to access the git repo" do
    assert_match "Unnamed repository; edit this file",
      @grit.rpc.fs_read("description")
  end

  test "returns branches with heads committed by a specified user and sorted by date" do

    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      branch1_ref      = @grit.heads.find("diverge")
      branch1_metadata = { message: "tmp commit 1", committer: @defunkt }
      branch1_ref.append_commit(branch1_metadata, @defunkt) do |files|
        files.add("tmp1.txt", "some content")
      end

      branch2_ref      = @grit.heads.find("lazy_delegator")
      branch2_metadata = { message: "tmp commit 2", committer: @defunkt }
      branch2_ref.append_commit(branch2_metadata, @defunkt) do |files|
        files.add("tmp2.txt", "some content")
      end
    end

    branches = @grit.recently_touched_branches_for(@defunkt)

    assert_equal 2, branches.size
    assert_operator branches.first[:date], :>=, branches.second[:date]
  end

  test "returns recently-pushed branches whose heads are not so recent" do

    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      master_oid = @grit.heads.find("master").target_oid
      ref = @grit.heads.create("somebranch", master_oid, @defunkt)
      metadata = { message: "old commit", committer: @defunkt, committed_date: 2.hours.ago.iso8601 }
      ref.append_commit(metadata, @defunkt) do |files|
        files.add("yeahyeah", "did it")
      end
    end

    branches = @grit.recently_touched_branches_for(@defunkt)

    assert_equal 1, branches.size
    assert_equal ["somebranch"], branches.collect { |b|  b[:name] }
  end

  test "returns recently-pushed branches with emojis" do
    assert_no_query_warnings do

      perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
        master_oid = @grit.heads.find("master").target_oid
        ref = @grit.heads.create(GRIN_EMOJI, master_oid, @defunkt)
        metadata = { message: "old commit", committer: @defunkt, committed_date: 2.hours.ago.iso8601 }
        ref.append_commit(metadata, @defunkt) do |files|
          files.add("yeahyeah", "did it")
        end
      end

      branches = @grit.recently_touched_branches_for(@defunkt)

      assert_equal 1, branches.size
      assert_equal [GRIN_EMOJI], branches.collect { |b|  b[:name] }
    end
  end

  test "orders recently-pushed branches based on push date, not commit date" do

    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      branch1_ref      = @grit.heads.find("diverge")
      branch1_metadata = { message: "tmp commit 1", committer: @defunkt, committed_date: 2.minutes.ago.iso8601 }
      branch1_ref.append_commit(branch1_metadata, @defunkt) do |files|
        files.add("tmp1.txt", "some content")
      end

      push = Push.where(repository_id: @grit, pusher_id: @defunkt, ref: "refs/heads/diverge").last
      T.must(push).update(created_at: 1.minute.ago)

      master_oid = @grit.heads.find("master").target_oid
      ref = @grit.heads.create("somebranch", master_oid, @defunkt)
      metadata = { message: "old commit", committer: @defunkt, committed_date: 3.minutes.ago.iso8601 }
      ref.append_commit(metadata, @defunkt) do |files|
        files.add("yeahyeah", "did it")
      end

      push = Push.where(repository_id: @grit, pusher_id: @defunkt, ref: "refs/heads/somebranch").last
      T.must(push).update(created_at: 20.seconds.ago)
    end

    branches = @grit.recently_touched_branches_for(@defunkt)

    assert_equal 2, branches.size
    assert_equal %w[somebranch diverge], branches.collect { |b|  b[:name] }
  end

  test "doesn't error when recently touched branches times out" do
    GitRPC::Client.any_instance.stubs(:descendant_of).raises(GitRPC::SpawnFailure.new(GitRPC::Timer::Error.new("timeout"), []))
    assert_empty @grit.recently_touched_branches_for(@defunkt)
  end

  test "doesn't return recently touched branches with existing pull requests on the same repo" do
    branch_without_pr_name = "diverge"
    branch_with_pr_name    = "lazy_delegator"


    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      branch_without_pr_ref      = @grit.heads.find(branch_without_pr_name)
      branch_without_pr_metadata = { message: "tmp commit 1", committer: @defunkt }
      branch_without_pr_ref.append_commit(branch_without_pr_metadata, @defunkt) do |files|
        files.add("tmp1.txt", "some content")
      end

      branch_with_pr_ref      = @grit.heads.find(branch_with_pr_name)
      branch_with_pr_metadata = { message: "tmp commit 2", committer: @defunkt }
      branch_with_pr_ref.append_commit(branch_with_pr_metadata, @defunkt) do |files|
        files.add("tmp2.txt", "some content")
      end
    end

    issue = create(:issue,
      user: @grit.owner,
      repository: @grit,
      body: "you say you got a lotta whips, well i got a Lot",
    )

    PullRequest.create(
      repository: @grit,
      base_repository: @grit,
      base_user: @grit.owner,
      base_ref: @grit.default_branch,
      head_repository: @grit,
      head_user: @grit.owner,
      head_ref: branch_with_pr_name,
      issue: issue,
    )

    branches = @grit.recently_touched_branches_for(@defunkt)

    assert_equal 1, branches.size
    assert_equal branch_without_pr_name, branches.first[:name]
  end

  test "doesn't return recently touched branches with existing pull requests on a fork's source repo" do
    grit_fork = create(:fork_repository, forker: create(:user), fork_repo: @grit)
    grit_fork.root.reload
    example_repo :mojombo_grit, grit_fork # rubocop:disable GitHub/UseFromExampleInRepositoryFactory

    branch_without_pr_name = "diverge"
    branch_with_pr_name    = "lazy_delegator"


    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      branch_without_pr_ref      = grit_fork.heads.find(branch_without_pr_name)
      branch_without_pr_metadata = { message: "tmp commit 1", committer: grit_fork.owner }
      branch_without_pr_ref.append_commit(branch_without_pr_metadata, grit_fork.owner) do |files|
        files.add("tmp1.txt", "some content")
      end

      branch_with_pr_ref      = grit_fork.heads.find(branch_with_pr_name)
      branch_with_pr_metadata = { message: "tmp commit 2", committer: grit_fork.owner }
      branch_with_pr_ref.append_commit(branch_with_pr_metadata, grit_fork.owner) do |files|
        files.add("tmp2.txt", "some content")
      end
    end

    grit_fork.reload

    issue = create(:issue,
      user: grit_fork.owner,
      repository: @grit,
      body: "you say you got a lotta whips, well i got a Lot",
    )

    PullRequest.create(
      repository: @grit,
      base_repository: @grit,
      base_user: @grit.owner,
      base_ref: @grit.default_branch,
      head_repository: grit_fork,
      head_user: grit_fork.owner,
      head_ref: branch_with_pr_name,
      issue: issue,
    )

    branches = grit_fork.recently_touched_branches_for(grit_fork.owner)

    assert_equal 1, branches.size
    assert_equal branch_without_pr_name, branches.first[:name]
  end

  test "will return recently touched branches with existing closed pull requests on the same repo" do
    @grit.update_default_branch("master")
    default = @grit.heads.find(@grit.default_branch)

    branch_without_pr_name = "diverge"
    branch_with_pr_name    = "lazy_delegator"


    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      branch_without_pr_ref      = @grit.heads.find_or_build(branch_without_pr_name)
      branch_without_pr_metadata = { message: "tmp commit 1", committer: @defunkt }
      branch_without_pr_commit   = @grit.commits.create(branch_without_pr_metadata, default.target_oid) do |files|
        files.add("tmp1.txt", "some content")
      end
      branch_without_pr_ref.update(branch_without_pr_commit, @defunkt)

      branch_with_pr_ref      = @grit.heads.find_or_build(branch_with_pr_name)
      branch_with_pr_metadata = { message: "tmp commit 2", committer: @defunkt }
      branch_with_pr_commit   = @grit.commits.create(branch_with_pr_metadata, default.target_oid) do |files|
        files.add("tmp2.txt", "some content")
      end
      branch_with_pr_ref.update(branch_with_pr_commit, @defunkt)
    end

    issue = create(:issue,
      user: @grit.owner,
      repository: @grit,
      body: "you say you got a lotta whips, well i got a Lot",
    )

    PullRequest.create(
      repository: @grit,
      base_repository: @grit,
      base_user: @grit.owner,
      base_ref: @grit.default_branch,
      head_repository: @grit,
      head_user: @grit.owner,
      head_ref: branch_with_pr_name,
      issue: issue,
    )

    issue.close
    issue.update(closed_at: 61.minutes.ago)

    branches = @grit.recently_touched_branches_for(@defunkt)

    expected = [branch_without_pr_name, branch_with_pr_name]

    assert_equal expected.size, branches.size
    assert_equal expected.sort, branches.collect { |b|  b[:name] }.sort
  end

  test "will return recently touched branches with existing closed pull requests from a forked repo" do
    grit_fork = create(:fork_repository, forker: create(:user), fork_repo: @grit)
    grit_fork.root.reload
    grit_fork.update_default_branch("master")
    example_repo :mojombo_grit, grit_fork # rubocop:disable GitHub/UseFromExampleInRepositoryFactory

    grit_fork_default = grit_fork.heads.find(grit_fork.default_branch)
    parent_oid = grit_fork_default.target_oid

    branch_without_pr_name = "diverge"
    branch_with_pr_name    = "lazy_delegator"


    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      branch_without_pr_ref      = grit_fork.heads.find_or_build(branch_without_pr_name)
      branch_without_pr_metadata = { message: "tmp commit 1", committer: grit_fork.owner }
      branch_without_pr_commit   = grit_fork.commits.create(branch_without_pr_metadata, parent_oid) do |files|
        files.add("tmp1.txt", "some content")
      end
      branch_without_pr_ref.update(branch_without_pr_commit, grit_fork.owner)

      branch_with_pr_ref      = grit_fork.heads.find_or_build(branch_with_pr_name)
      branch_with_pr_metadata = { message: "tmp commit 2", committer: grit_fork.owner }
      branch_with_pr_commit   = grit_fork.commits.create(branch_with_pr_metadata, parent_oid) do |files|
        files.add("tmp2.txt", "some content")
      end
      branch_with_pr_ref.update(branch_with_pr_commit, grit_fork.owner)
    end

    grit_fork.reload

    issue = create(:issue,
      user: grit_fork.owner,
      repository: @grit,
      body: "you say you got a lotta whips, well i got a Lot",
    )

    PullRequest.create(
      repository: @grit,
      base_repository: @grit,
      base_user: @grit.owner,
      base_ref: @grit.default_branch,
      head_repository: grit_fork,
      head_user: grit_fork.owner,
      head_ref: branch_with_pr_name,
      issue: issue,
      user: issue.user,
    )

    issue.close
    issue.update(closed_at: 61.minutes.ago)

    branches = grit_fork.recently_touched_branches_for(grit_fork.owner)

    expected = [branch_without_pr_name, branch_with_pr_name]

    assert_equal expected.size, branches.size
    assert_equal expected.sort, branches.collect { |b|  b[:name] }.sort
  end

  test "is not empty when on disk" do
    refute @grit.empty?
    @grit.update_default_branch("master")
  end

  test "returns the project's license" do
    licensed_repo = create :repository, name: "licensed-repo", owner: @defunkt, created_by_user_id: @defunkt.id, from_example: :license_markdown
    licensed_repo.license_template = "mit"
    licensed_repo.initialize_git_repository_templates

    licensed_repo.set_licenses
    licensed_repo.reload

    assert_equal "mit", licensed_repo.license.key
    assert_nil @facebox.license
  end

  test "sets the project's license" do
    repo = create :repository, owner: @defunkt, name: "foo", created_by_user_id: @defunkt.id, from_example: :license_markdown
    repo.license_template = "mit"
    repo.initialize_git_repository_templates

    assert_equal 1, repo.set_licenses.count
    assert_equal "mit", repo.set_licenses.first[:license_key]
    repo.reload
    assert repo.repository_license
    assert_equal "mit", repo.repository_license.license.key

    @facebox.set_licenses
    assert_nil @facebox.repository_license
  end

  test "can calculate a breakdown of files by language" do
    breakdown = @facebox.files_by_language
    assert_equal %w(CSS HTML JavaScript Shell), breakdown.keys.sort
    assert_equal %w(facebox.css faceplant.css), breakdown["CSS"]
  end

  test "can retrieve the language stats as a hash" do
    @facebox.analyze_languages
    stats = @facebox.language_breakdown
    assert_equal 313, stats["Shell"]
    assert_equal 9478, stats["JavaScript"]
  end

  test "doesn't return recently touched branches that contain emojis with existing pull request" do
    without_pr = "another-one"
    with_pr    = "new-branch-💩"
    metadata_pr = { message: "tmp commit 1", committer: @defunkt }

    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      @emojis.heads.find(without_pr).append_commit(metadata_pr, @defunkt) do |files|
        files.add("tmp1.txt", "some content")
      end
      @emojis.heads.find(with_pr).append_commit(metadata_pr, @defunkt) do |files|
        files.add("tmp2.txt", "some content")
      end
    end

    issue = create :issue, repository: @emojis, user: @emojis.owner

    PullRequest.create_for(@emojis,
                           base:  "master",
                           head:  with_pr,
                           user:  @emojis.owner,
                           issue: issue,
    )

    branches = @emojis.recently_touched_branches_for(@defunkt)

    assert_equal 1, branches.size
    assert_equal without_pr, branches.first[:name]
  end

  context "#deployment_environments" do
    test "it returns an array of all environments" do
      master_oid = @grit.heads.find("master").target_oid

      environments = %w[production staging canary]
      environments.each do |environment|
        create :deployment, repository: @grit, sha: master_oid, environment: environment
      end

      assert_equal environments.sort, @grit.deployment_environments.sort
    end
  end

  context "#ranked_deployment_environments" do
    test "returns all environments ordered by number of deploys" do
      master_oid = @grit.heads.find("master").target_oid

      num_of_prod_deploys = 5
      num_of_staging_deploys = 7
      num_of_canary_deploys = 1

      num_of_prod_deploys.times    { create :deployment, repository: @grit, sha: master_oid, environment: "prod"    }
      num_of_staging_deploys.times { create :deployment, repository: @grit, sha: master_oid, environment: "staging" }
      num_of_canary_deploys.times  { create :deployment, repository: @grit, sha: master_oid, environment: "canary"  }

      expected_result = [
        [num_of_staging_deploys, "staging"],
        [num_of_prod_deploys, "prod"],
        [num_of_canary_deploys, "canary"],
      ]

      assert_equal expected_result, @grit.ranked_deployment_environments
    end
  end

  context "#ranked_active_deployment_environments" do
    test "returns all active environments case insensitively ordered by number of deploys" do
      Repository.any_instance.stubs(:can_use_environments?).returns(true)
      master_oid = @grit.heads.find("master").target_oid

      num_of_prod_deploys = 5
      num_of_staging_deploys = 7
      num_of_canary_deploys = 1

      num_of_prod_deploys.times    { create :deployment, repository: @grit, sha: master_oid, environment: "prod"    }
      num_of_staging_deploys.times { create :deployment, repository: @grit, sha: master_oid, environment: "staging" }
      num_of_canary_deploys.times  { create :deployment, repository: @grit, sha: master_oid, environment: "canary"  }

      expected_result = [
        [num_of_staging_deploys, "staging"],
        [num_of_prod_deploys, "prod"], # case sensitive
        [num_of_canary_deploys, "canary"],
      ]

      assert_equal expected_result, @grit.ranked_active_deployment_environments

      @grit.environments.find_by_name("staging").destroy!
      @grit.environments.find_by_name("prod").update!(name: "Prod")

      after_deletion_expected_result = [
        [num_of_prod_deploys, "prod"], # case insensitive now as the environment name is `Prod`
        [num_of_canary_deploys, "canary"],
      ]

      assert_equal after_deletion_expected_result, @grit.ranked_active_deployment_environments

    end

    test "returns all deployments ordered by number of deploys if repo cannot use environments feature" do
      Repository.any_instance.stubs(:can_use_environments?).returns(false)
      master_oid = @grit.heads.find("master").target_oid

      num_of_prod_deploys = 5
      num_of_staging_deploys = 7
      num_of_canary_deploys = 1

      num_of_prod_deploys.times    { create :deployment, repository: @grit, sha: master_oid, environment: "prod"    }
      num_of_staging_deploys.times { create :deployment, repository: @grit, sha: master_oid, environment: "staging" }
      num_of_canary_deploys.times  { create :deployment, repository: @grit, sha: master_oid, environment: "canary"  }

      @grit.environments.find_by_name("staging").destroy!
      @grit.environments.find_by_name("prod").update!(name: "Prod")

      # all deployments should be returned regardless of the environments status
      expected_result = [
        [num_of_staging_deploys, "staging"],
        [num_of_prod_deploys, "prod"],
        [num_of_canary_deploys, "canary"],
      ]

      assert_equal expected_result, @grit.ranked_active_deployment_environments
    end
  end

  context "#frequent_deploy_environments" do
    test "returns most frequent environments in order" do
      master_oid = @grit.heads.find("master").target_oid

      5.times    { create :deployment, repository: @grit, sha: master_oid, environment: "prod"    }
      7.times { create :deployment, repository: @grit, sha: master_oid, environment: "staging" }
      1.times  { create :deployment, repository: @grit, sha: master_oid, environment: "canary"  }

      expected_result = %w[staging prod]

      assert_equal expected_result, @grit.frequent_deploy_environments(first: 2)
    end
  end

  context "#global_health_files_repository?" do
    test "true for public org-owned .github repo" do
      dot_github_repo = create(:repository, owner: create(:organization), name: ".github")
      assert dot_github_repo.public?
      assert dot_github_repo.owner.organization?
      assert_equal dot_github_repo.name, ".github"
      assert dot_github_repo.global_health_files_repository?
    end

    test "true for public user-owned .github repo" do
      dot_github_repo = create(:repository, owner: create(:user), name: ".github")
      assert dot_github_repo.public?
      assert_equal dot_github_repo.name, ".github"
      refute dot_github_repo.owner.organization?
      assert dot_github_repo.global_health_files_repository?
    end

    test "false for private org-owned .github repo" do
      dot_github_repo = create(:private_repository, owner: create(:organization), name: ".github")
      assert dot_github_repo.owner.organization?
      assert_equal dot_github_repo.name, ".github"
      refute dot_github_repo.public?
      refute dot_github_repo.global_health_files_repository?
    end

    test "false for public org-owned repo with different name" do
      repo = create(:repository, owner: create(:organization), name: "hack-the-planet")
      assert repo.public?
      assert repo.owner.organization?
      refute repo.global_health_files_repository?
    end

    test "false for inactive org-owned .github repo" do
      dot_github_repo = create(:repository, owner: create(:organization), name: ".github", active: false)
      assert dot_github_repo.owner.organization?
      assert_equal dot_github_repo.name, ".github"
      assert dot_github_repo.public?
      refute dot_github_repo.global_health_files_repository?
    end
  end
end
